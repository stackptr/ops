# The repos that get the GitHub baseline in ./baseline.nix. Personal accounts
# have no account-wide rulesets, so a repo must be listed here before the
# agents' app (teleomycete, ./apps.nix) goes on it. Changing this file changes
# the agents' guardrails: review it as a policy change.
#
# Per repo:
# - requiredChecks: GitHub Actions check names "Require CI" waits for. Every
#   repo needs at least one, since every repo gets all four rulesets.
# - rulesetIds: existing rulesets to import instead of creating duplicates,
#   keyed like baseline.nix's rulesets
# - updaterBypass: teleotrope may skip "Require approval" and "Agent
#   branches" to merge flake updates. Only for repos whose required checks
#   build the flake (stackptr/rc#768). The bypass alone doesn't make update
#   PRs auto-merge: auto-merge still waits for an approval, so the update
#   workflow has to wait for the checks and merge with
#   `gh pr merge --admin --match-head-commit`, as rc's update.yml does
#   (stackptr/rc#772, stackptr/rc#773).
# - repository: the repo's settings (github_repository), imported on first
#   apply. State every one: see ./repository.nix
# - oidc: the repo's workflows use OIDC; subjects then include the ref, so
#   cloud trust policies can match ref:refs/heads/main
# - environments.<name>:
#   - adopt: the environment existed before ops managed it; import it
#   - mainPolicyId: its existing `main` deployment branch policy, to import.
#     Creating one where it already exists fails. List them with
#     `gh api repos/stackptr/<repo>/environments/<env>/deployment-branch-policies`.
#     The locked provider then replaces the imported policy once (deletes and
#     recreates it, so for a few seconds no branch can deploy), because its
#     read never sets `repository` or `environment`. Remove the ID once that
#     apply lands: the policy it names is gone.
#   - deploy: it deploys, so it also requires my approval
#
# An environment's secrets are in ./sealed.json, sealed to its public key by
# `just seal <repo> <environment> <NAME>`. Only GitHub can decrypt them, so
# they're safe to commit, and state holds only the ciphertext.
{
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
    repository = {
      description = "🖥️ System configuration flake for NixOS and nix-darwin";
      homepage_url = "";
      visibility = "public";
      topics = ["dotfiles" "home-manager" "nix" "nix-darwin" "nix-flake" "nixos" "nixos-configuration"];
      has_issues = true;
      has_projects = false;
      has_wiki = false;
      has_discussions = false;
      has_downloads = false;
      is_template = false;
      vulnerability_alerts = false;
      web_commit_signoff_required = false;
      # PRs are squash-merged, so the title becomes the commit message
      allow_merge_commit = false;
      allow_squash_merge = true;
      allow_rebase_merge = true;
      squash_merge_commit_title = "COMMIT_OR_PR_TITLE";
      squash_merge_commit_message = "COMMIT_MESSAGES";
      merge_commit_title = "MERGE_MESSAGE";
      merge_commit_message = "PR_TITLE";
      allow_auto_merge = true;
      allow_update_branch = true;
      # Partial flake updates open a branch per run (rc's update.yml), and
      # cloud sessions can't delete branches
      delete_branch_on_merge = true;
    };
    environments = {
      # App keys for approve.yml (teleoid) and update.yml (teleotrope)
      approve.adopt = true;
      update.adopt = true;
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
}
