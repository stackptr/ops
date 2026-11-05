tofu_dir := "tofu"

# Recipes that run with credentials (init, plan, apply, destroy) refuse to run
# anything but main's code: tofu executes the provider and Nix evaluation of
# whatever is checked out, so an agent's branch would run with my credentials,
# and on macOS Nix doesn't sandbox builds by default. OPS_ALLOW_BRANCH=1
# overrides it, for my own branches only. In CI the environments already
# admit only main.
_on-main:
  #!/usr/bin/env bash
  set -euo pipefail
  if [[ ${GITHUB_ACTIONS:-} == true || ${OPS_ALLOW_BRANCH:-} == 1 ]]; then exit 0; fi
  if [[ -n $(git status --porcelain --untracked-files=no) ]]; then
    echo "error: uncommitted changes; commit them, or OPS_ALLOW_BRANCH=1 if they're mine" >&2
    exit 1
  fi
  head=$(git rev-parse HEAD)
  main=$(git rev-parse origin/main)
  if [[ $head != "$main" ]]; then
    echo "error: HEAD (${head::7}) isn't origin/main (${main::7}). Check out main, or OPS_ALLOW_BRANCH=1 for my own branch, never an agent's" >&2
    exit 1
  fi

# Generate OpenTofu JSON config from Terranix
build:
  nix build .#terraformConfiguration -o {{tofu_dir}}/config.tf.json

# Initialize OpenTofu (runs build first). Recipes that touch state need
# AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (an R2 API token for the state
# bucket), TF_VAR_state_endpoint, and TF_VAR_state_passphrase.
init *args: _on-main build
  #!/usr/bin/env bash
  set -euo pipefail
  # Fail with the missing name, not an S3 error, unless there's no backend
  if [[ " {{args}} " != *" -backend=false "* ]]; then
    for var in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TF_VAR_state_endpoint TF_VAR_state_passphrase; do
      if [[ -z ${!var:-} ]]; then
        echo "error: $var is not set (in CI it comes from the environment's STATE_* secrets and the STATE_ENDPOINT variable)" >&2
        exit 1
      fi
    done
  fi
  tofu -chdir={{tofu_dir}} init {{args}}

# Show execution plan
plan *args: _on-main build
  tofu -chdir={{tofu_dir}} plan {{args}}

# Apply infrastructure changes
apply *args: _on-main build
  tofu -chdir={{tofu_dir}} apply {{args}}

# Destroy managed infrastructure
destroy *args: _on-main build
  tofu -chdir={{tofu_dir}} destroy {{args}}

# Display generated Terraform JSON
show-config: build
  cat {{tofu_dir}}/config.tf.json | jq

# Diff the generated config against another revision's (default: origin/main).
# Needs no credentials: this is the PR preview in CI.
diff rev="origin/main": build
  #!/usr/bin/env bash
  set -euo pipefail
  base=$(nix build "git+file://$PWD?rev=$(git rev-parse '{{rev}}')#terraformConfiguration" --no-link --print-out-paths)
  diff -u --label '{{rev}}' --label HEAD <(jq -S . "$base") <(jq -S . {{tofu_dir}}/config.tf.json) || [ $? -eq 1 ]

# Seal a secret into infrastructure/github/sealed.json: reads the value on
# stdin and stores it, sealed to the environment's public key, as
# <repo>.<env>.<name>. The environment must already exist in GitHub.
seal repo env name:
  #!/usr/bin/env bash
  set -euo pipefail
  key=$(gh api "repos/stackptr/{{repo}}/environments/{{env}}/secrets/public-key" --jq .key)
  value=$(nix run .#seal -- "$key")
  file=infrastructure/github/sealed.json
  jq --arg r '{{repo}}' --arg e '{{env}}' --arg n '{{name}}' --arg v "$value" \
    '.[$r][$e][$n] = $v' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
  echo "Sealed {{name}} for {{repo}}/{{env}} into $file" >&2

# Validate OpenTofu config
validate *args: build
  tofu -chdir={{tofu_dir}} validate {{args}}

# Format Nix files
fmt:
  nix fmt
