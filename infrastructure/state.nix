# Remote state in a Cloudflare R2 bucket, encrypted client-side by OpenTofu.
#
# The bucket is created by hand, outside this config: the state can't manage
# the bucket it lives in. Credentials come from AWS_ACCESS_KEY_ID and
# AWS_SECRET_ACCESS_KEY (an R2 API token): OpenTofu rejects sensitive values in
# backend config. An AWS provider added later must take its own credentials in
# its provider block so it doesn't pick these up. The endpoint and passphrase
# come from TF_VAR_state_endpoint and TF_VAR_state_passphrase.
{
  variable = {
    state_endpoint = {
      type = "string";
      description = "R2 S3 endpoint, https://<account-id>.r2.cloudflarestorage.com";
    };
    state_passphrase = {
      type = "string";
      sensitive = true;
      description = "Passphrase for state and plan encryption (at least 16 characters)";
    };
  };

  terraform.backend.s3 = {
    bucket = "ops-state";
    key = "ops.tfstate";
    region = "auto";
    endpoints.s3 = "\${var.state_endpoint}";
    use_path_style = true;
    use_lockfile = true;

    # R2 is not AWS: skip the AWS-only lookups and checksums it doesn't support
    skip_credentials_validation = true;
    skip_region_validation = true;
    skip_requesting_account_id = true;
    skip_metadata_api_check = true;
    skip_s3_checksum = true;
  };

  terraform.encryption = {
    key_provider.pbkdf2.state.passphrase = "\${var.state_passphrase}";
    method.aes_gcm.state.keys = "\${key_provider.pbkdf2.state}";
    state = {
      method = "method.aes_gcm.state";
      enforced = true;
    };
    plan = {
      method = "method.aes_gcm.state";
      enforced = true;
    };
  };
}
