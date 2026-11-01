tofu_dir := "tofu"

# Generate OpenTofu JSON config from Terranix
build:
  nix build .#terraformConfiguration -o {{tofu_dir}}/config.tf.json

# Initialize OpenTofu (runs build first). Recipes that touch state need
# AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (an R2 API token for the state
# bucket), TF_VAR_state_endpoint, and TF_VAR_state_passphrase.
init *args: build
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

# Validate OpenTofu config
validate *args: build
  tofu -chdir={{tofu_dir}} validate {{args}}

# Format Nix files
fmt:
  nix fmt
