tofu_dir := "tofu"

# Generate OpenTofu JSON config from Terranix
build:
  nix build .#terraformConfiguration -o {{tofu_dir}}/config.tf.json

# Initialize OpenTofu (runs build first)
init: build
  tofu -chdir={{tofu_dir}} init

# Show execution plan
plan: build
  tofu -chdir={{tofu_dir}} plan

# Apply infrastructure changes
apply: build
  tofu -chdir={{tofu_dir}} apply

# Destroy managed infrastructure
destroy: build
  tofu -chdir={{tofu_dir}} destroy

# Display generated Terraform JSON
show-config: build
  cat {{tofu_dir}}/config.tf.json | jq

# Validate OpenTofu config
validate: build
  tofu -chdir={{tofu_dir}} validate

# Format Nix files
fmt:
  nix fmt
