# The repos that get the GitHub baseline in ./baseline.nix. Personal accounts
# have no account-wide rulesets, so a repo must be listed here, with
# `agents`, before the agents' app (teleomycete, ./apps.nix) goes on it.
# Changing this file changes the agents' guardrails: review it as a policy
# change. To bring a repo under management, follow "Onboarding a repo" in
# CLAUDE.md.
#
# Per repo:
# - repository (required): the repo's settings (github_repository), imported
#   on first apply. Set `visibility`, `description` and `homepage_url`, and
#   `topics` to manage them; the rest come from ./repository.nix's defaults.
# - agents: the coding agents (teleomycete) work on the repo, so it gets
#   "Require approval", "Agent branches" and "Agent-only branches", and needs
#   an `approve` environment for teleoid's key. Public repos only.
# - requiredChecks: GitHub Actions check names "Require CI" waits for. Without
#   any, the repo gets no "Require CI". Public repos only.
# - rulesetIds: existing rulesets to import instead of creating duplicates,
#   keyed like baseline.nix's rulesets
# - agentsInstalled (needs agents): teleomycete is installed, so it may
#   bypass "Agent-only branches". GitHub rejects an app as a bypass actor
#   before it's installed, so this is a follow-up to the install.
# - dependabot (needs agents): the repo runs Dependabot (a
#   .github/dependabot.yml), which bypasses "Agent branches" to push its
#   `dependabot/**` branches. GitHub rejects it where Dependabot doesn't run.
# - updaterBypass (needs agents): teleotrope may skip "Require approval" and "Agent
#   branches" to merge flake updates. Only for repos whose required checks
#   build the flake (stackptr/rc#768). The bypass alone doesn't make update
#   PRs auto-merge: auto-merge still waits for an approval, so the update
#   workflow has to wait for the checks and merge with
#   `gh pr merge --admin --match-head-commit`, as rc's update.yml does
#   (stackptr/rc#772, stackptr/rc#773).
# - oidc: the repo's workflows use OIDC; subjects then include the ref, so
#   cloud trust policies can match ref:refs/heads/main
# - environments.<name> (public repos only, without GitHub Pro):
#   - adopt: the environment existed before ops managed it; import it
#   - mainPolicyId: its existing `main` deployment branch policy, to import.
#     Creating one where it already exists fails. List them with
#     `gh api repos/stackptr/<repo>/environments/<env>/deployment-branch-policies`.
#     The locked provider then replaces the imported policy once (deletes and
#     recreates it, so for a few seconds no branch can deploy), because its
#     read never sets `repository` or `environment`. Remove the ID once that
#     apply lands: the policy it names is gone.
#   - deploy: it deploys, so it also requires my approval
#   - variables: its variables (vars.<NAME>), which aren't secret, like an
#     app's client ID
#
# An environment's secrets are in ./sealed.json, sealed to its public key by
# `just seal <repo> <environment> <NAME>`. Only GitHub can decrypt them, so
# they're safe to commit, and state holds only the ciphertext.
{
  actions = {
    agents = true;
    repository = {
      visibility = "public";
      description = "";
      homepage_url = "";
    };
    requiredChecks = ["check" "action (ubuntu-latest)" "action (macos-latest)"];
    environments = {
      # The reusable approve workflow, called from this repo's approve.yml
      # (teleoid)
      approve.variables.APPROVER_CLIENT_ID = "Iv23likJzKNAteBwoYdc";
      # smoke.yml, which posts real messages (SLACK_BOT_TOKEN)
      notify = {};
    };
  };
  rc = {
    requiredChecks = map (host: "build (${host})") [
      "glyph, x86_64-linux, ubuntu-latest"
      "Rhizome, aarch64-darwin, macos-latest"
      "Stroma, aarch64-darwin, macos-latest"
      "lobtop, aarch64-darwin, macos-latest"
      "spore, x86_64-linux, ubuntu-latest"
      "zeta, aarch64-linux, ubuntu-24.04-arm"
    ];
    # Created by hand (stackptr/rc#733, stackptr/rc#784)
    rulesetIds = {
      require_ci = 10414171;
      require_approval = 25745892;
      agent_branches = 25753101;
      agent_only_branches = 26123828;
    };
    updaterBypass = true;
    agents = true;
    agentsInstalled = true;
    dependabot = true;
    repository = {
      visibility = "public";
      description = "🖥️ System configuration flake for NixOS and nix-darwin";
      homepage_url = "";
      topics = ["dotfiles" "home-manager" "nix" "nix-darwin" "nix-flake" "nixos" "nixos-configuration"];
    };
    environments = {
      # App keys for approve.yml (teleoid) and update.yml (teleotrope)
      approve = {
        adopt = true;
        variables.APPROVER_CLIENT_ID = "Iv23likJzKNAteBwoYdc";
      };
      update = {
        adopt = true;
        variables.UPDATER_CLIENT_ID = "Iv23liMg01Js73TxJmX4";
      };
      # deploy.yml, one per host
      glyph = {
        adopt = true;
        deploy = true;
      };
      # No reviewer: deploy.yml deploys main to spore daily so security fixes
      # reach the internet-facing host without waiting on me, and a reviewer
      # would hold every scheduled run. It still only runs main, so a deploy
      # someone else starts could only do what the schedule does within a day.
      spore.adopt = true;
      zeta = {
        adopt = true;
        deploy = true;
      };
      # ci.yml's main-only push to the attic cache (ATTIC_TOKEN)
      attic = {};
      # Slack alerts from ci.yml, deploy.yml and port-scan.yml on main
      # (SLACK_BOT_TOKEN)
      notify = {};
    };
  };
  resume = {
    agents = true;
    repository = {
      visibility = "public";
      description = "";
      homepage_url = "";
    };
    environments = {
      # The reusable approve workflow (teleoid)
      approve.variables.APPROVER_CLIENT_ID = "Iv23likJzKNAteBwoYdc";
      # release.yml's push to the Attic cache (ATTIC_TOKEN)
      attic = {};
    };
  };
}
