# Repository settings, from each repo's `repository` in ./repos.nix. The
# locked provider sends every setting on update, and unset booleans and
# strings mean false and empty rather than "leave alone", so `repository`
# must state each one; otherwise an apply turns off issues, auto-merge and
# the like. Values not set here (security_and_analysis, pages, the default
# branch) are left as they are.
#
# Destroying a github_repository deletes the repository. Three guards:
# - prevent_destroy fails a plan that destroys one, but only while the
#   resource is in the config: dropping a repo from ./repos.nix takes it away.
# - archive_on_destroy is kept in state, so a destroy that gets past the
#   config archives the repository instead of deleting it.
# - The plan job fails if the plan destroys or replaces any
#   github_repository, so no apply runs (.github/workflows/infrastructure.yml).
# checks/baseline.jq requires `repository` and both settings for every repo in
# ./repos.nix. To stop managing a repo, drop it in the same change as adding
#   removed = [{from = "github_repository.<repo>"; lifecycle.destroy = false;}];
# which forgets it from state without destroying it.
{lib, ...}: let
  # Repos without `repository` fail checks/baseline.jq rather than evaluation
  repos = lib.filterAttrs (_: cfg: cfg ? repository) (import ./repos.nix);

  # OpenTofu resource names can't contain dots (zx.dev)
  id = lib.replaceStrings ["."] ["_"];
in {
  resource.github_repository = lib.mapAttrs' (repo: cfg:
    lib.nameValuePair (id repo) ({
        name = repo;
        archive_on_destroy = true;
        lifecycle.prevent_destroy = true;
      }
      // cfg.repository))
  repos;

  import =
    lib.mapAttrsToList (repo: _: {
      to = "github_repository.${id repo}";
      id = repo;
    })
    repos;
}
