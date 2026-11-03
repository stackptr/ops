# Repository settings, for repos in ./repos.nix that set `repository`. The
# locked provider sends every setting on update, and unset booleans and
# strings mean false and empty rather than "leave alone", so `repository`
# must state each one; otherwise an apply turns off issues, auto-merge and
# the like. Values not set here (security_and_analysis, pages, the default
# branch) are left as they are.
#
# Destroying a github_repository deletes the repository, so dropping a repo
# from ./repos.nix (or its `repository`) fails the plan rather than deleting
# it: remove it from state with `tofu state rm` first.
{lib, ...}: let
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
