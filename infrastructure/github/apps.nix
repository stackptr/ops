# The GitHub Apps that act on the baseline's repos. The provider can't set an
# app's permissions or, with app credentials, its installations
# (github_app_installation_repository needs a user token), so both are
# managed by hand in each app's settings and recorded here. Keep this in step.
#
# `id` is the app (integration) ID, as rulesets name bypass actors; it is not
# the bot's user ID.
{
  # The coding agents (Paseo and OpenCode on glyph). Installed only on repos
  # in ./repos.nix. Never a bypass actor except on "Agent-only branches", and
  # never Workflows or Administration.
  teleomycete = {
    id = 5433982;
    permissions = "Contents, Pull requests and Issues read/write";
  };

  # Opens and merges flake updates (update.yml); bypasses "Require approval"
  # and "Agent branches" on repos with `updaterBypass`.
  teleotrope = {
    id = 5445588;
    permissions = "Contents and Pull requests read/write";
  };

  # Approves my own PRs (approve.yml, on pull_request_target). Its approval
  # only counts with Contents: write. Never a bypass actor, so its ID isn't
  # needed here.
  teleoid = {
    id = null;
    permissions = "Contents and Pull requests read/write";
  };

  # ops's plan credential, its key in ops's `plan` environment: runs plans,
  # the daily drift check and the repository-secret check. Installed on every
  # repo in ./repos.nix. Never a bypass actor.
  #
  # Administration is write, not read, only because GitHub shows a ruleset's
  # bypass actors to credentials that can edit it. Read-only, every plan
  # showed them as missing and drift in who may bypass went undetected
  # (stackptr/ops#3). So `plan` can edit settings too; R2 writes and every
  # apply still go through `production`.
  teleopsis = {
    id = null;
    permissions = "Administration read/write; Actions, Environments and Secrets read";
  };

  # ops's apply credential, its key in ops's `production` environment behind
  # my approval. Administration write is close to admin on every repo it's
  # installed on (rulesets, deploy keys), so it's installed only on repos in
  # ./repos.nix. Never a bypass actor.
  teleozyme = {
    id = null;
    permissions = "Administration, Environments and Actions read/write; Secrets read";
  };
}
