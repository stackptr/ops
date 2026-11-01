tofu_dir := "tofu"

# Generate OpenTofu JSON config from Terranix
build:
  nix build .#terraformConfiguration -o {{tofu_dir}}/config.tf.json

# Initialize OpenTofu (runs build first). Recipes that touch state need
# AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (an R2 API token for the state
# bucket), TF_VAR_state_endpoint, and TF_VAR_state_passphrase.
init *args: build
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
plan *args: build
  tofu -chdir={{tofu_dir}} plan {{args}}

# Apply infrastructure changes
apply *args: build
  tofu -chdir={{tofu_dir}} apply {{args}}

# Destroy managed infrastructure
destroy *args: build
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

# Seal a secret for infrastructure/github/repos.nix: reads the value on stdin
# and prints the ciphertext for environments.<env>.secrets.<NAME>
seal repo env:
  #!/usr/bin/env bash
  set -euo pipefail
  key=$(gh api "repos/stackptr/{{repo}}/environments/{{env}}/secrets/public-key" --jq .key)
  python3 scripts/seal.py "$key"

# Validate OpenTofu config
validate *args: build
  tofu -chdir={{tofu_dir}} validate {{args}}

# Format Nix files
fmt:
  nix fmt
