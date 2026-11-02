# GitHub, as the stackptr account. The provider comes from nixpkgs through the
# flake (opentofu.withPlugins in flake.nix), not the registry, so flake.lock
# pins it. CI authenticates as one of two GitHub Apps through GITHUB_TOKEN:
# teleopsis in the `plan` environment and teleozyme in `production` (see
# ./apps.nix for why both can write). Locally, `GITHUB_TOKEN=$(gh auth token)`.
{
  imports = [./baseline.nix];

  terraform.required_providers.github.source = "integrations/github";

  provider.github.owner = "stackptr";
}
