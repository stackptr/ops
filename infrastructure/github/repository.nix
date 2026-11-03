# Repository settings: `defaults` below, overridden by each repo's
# `repository` in ./repos.nix. The locked provider sends every setting on
# update, and unset booleans and strings mean false and empty rather than
# "leave alone", so `defaults` states every setting the provider sends except
# the ones that differ per repo, which each repo must set: `visibility` (a
# private repo missing it would be made public), `description` and
# `homepage_url` (both blanked if missing; "" for none). Settings not sent
# (security_and_analysis, pages, the default branch, and topics unless set)
# are left as they are.
#
# Destroying a github_repository deletes the repository. Three guards:
# - prevent_destroy fails a plan that destroys one, but only while the
#   resource is in the config: dropping a repo from ./repos.nix takes it away.
# - archive_on_destroy is kept in state, so a destroy that gets past the
#   config archives the repository instead of deleting it.
# - The plan job fails if the plan destroys or replaces any
#   github_repository, so no apply runs (.github/workflows/infrastructure.yml).
# A repo's `repository` can't override either setting, and checks/baseline.jq
# requires both for every repo in ./repos.nix. To stop managing a repo, drop
# it in the same change as adding
#   removed = [{from = "github_repository.<repo>"; lifecycle.destroy = false;}];
# which forgets it from state without destroying it.
{lib, ...}: let
  # Repos without `repository` fail checks/baseline.jq rather than evaluation
  repos = lib.filterAttrs (_: cfg: cfg ? repository) (import ./repos.nix);

  # OpenTofu resource names can't contain dots (zx.dev)
  id = lib.replaceStrings ["."] ["_"];

  required = ["visibility" "description" "homepage_url"];

  defaults = {
    has_issues = true;
    has_projects = false;
    has_wiki = false;
    has_discussions = false;
    has_downloads = false;
    is_template = false;
    vulnerability_alerts = false;
    web_commit_signoff_required = false;
    # PRs are squash-merged, with the PR title as the commit's subject and
    # the commits' messages (and their trailers) as its body
    allow_merge_commit = false;
    allow_squash_merge = true;
    allow_rebase_merge = true;
    squash_merge_commit_title = "PR_TITLE";
    squash_merge_commit_message = "COMMIT_MESSAGES";
    allow_auto_merge = true;
    allow_update_branch = true;
    delete_branch_on_merge = true;
  };

  settings = repo: cfg: let
    missing = lib.filter (key: !(cfg.repository ? ${key})) required;
  in
    if missing == []
    then
      defaults
      // cfg.repository
      // {
        name = repo;
        archive_on_destroy = true;
        lifecycle.prevent_destroy = true;
      }
    else throw "repos.nix: ${repo}.repository must set ${lib.concatStringsSep ", " missing}";
in {
  resource.github_repository = lib.mapAttrs' (repo: cfg: lib.nameValuePair (id repo) (settings repo cfg)) repos;

  import =
    lib.mapAttrsToList (repo: _: {
      to = "github_repository.${id repo}";
      id = repo;
    })
    repos;
}
