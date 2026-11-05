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
#   an `approve` environment for teleoid's key. Public repos only. Only for
#   repos the agents may change unattended: their Contents write also covers
#   releases (tags, assets), which no branch ruleset guards, and their token
#   reaches every repo teleomycete is installed on.
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
# - adminBypass: how the admin role bypasses the default branch's rulesets.
#   "always" (the default) or "pull_request": only by merging a PR, so no one,
#   cloud sessions acting as me included, pushes straight to the default
#   branch. Other branches' rulesets are always bypassed.
# - releaseTags: the repo's tags are releases that other repos pin (and their
#   Dependabot upgrades to), so only the admin role may create, move or
#   delete tags ("Release tags"). Public repos only.
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
    # Callers pin its releases; release.yml publishes one per tag
    releaseTags = true;
    agentsInstalled = true;
    # .github/dependabot.yml (GitHub Actions versions)
    dependabot = true;
    repository = {
      visibility = "public";
      description = "🧩 Shared actions and workflows";
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
  # No agents: I download its release assets (chat.md, the agent bundles,
  # skill zips) and paste them into claude.ai, and Contents write (any agent
  # token) could replace them without a PR. Change it from a supervised session.
  llm-profile = {
    repository = {
      visibility = "public";
      description = "Persistent system prompt for use with LLMs";
      homepage_url = "";
    };
    requiredChecks = ["words"];
    # release.yml's Slack notices (SLACK_BOT_TOKEN)
    environments.notify = {};
  };
  flakes = {
    agents = true;
    agentsInstalled = true;
    repository = {
      visibility = "public";
      description = "❄️ Nix development environments and templates";
      homepage_url = "";
      topics = ["nix" "nix-flake" "nix-template"];
    };
    # ci.yml builds each development environment, on PRs and main
    requiredChecks = map (target: "build (${target})") [
      "x86_64-linux, ubuntu-latest"
      "aarch64-darwin, macos-latest"
    ];
    # The reusable approve workflow (teleoid). No cache secret: CI pushes
    # nowhere.
    environments.approve.variables.APPROVER_CLIENT_ID = "Iv23likJzKNAteBwoYdc";
  };
  # This repo. Its environments hold the credentials every plan and apply run
  # with.
  ops = {
    agents = true;
    agentsInstalled = true;
    # Admins (cloud sessions acting as me included) change main only by
    # merging a PR, as ops's hand-made ruleset already required
    adminBypass = "pull_request";
    repository = {
      visibility = "public";
      description = "⚙️ GitOps configuration";
      homepage_url = "";
    };
    # infrastructure.yml's credential-free PR job
    requiredChecks = ["check"];
    # Created by hand. It also required a PR and blocked deletion, which
    # "Require approval" now does (#4)
    rulesetIds.require_ci = 26143610;
    environments = {
      # The reusable approve workflow (teleoid)
      approve.variables.APPROVER_CLIENT_ID = "Iv23likJzKNAteBwoYdc";
      # ci.yml's push to Attic on main (ATTIC_TOKEN)
      attic.adopt = true;
      # Plans and the daily drift and secrets checks, as teleopsis (its key,
      # the state credentials and SLACK_BOT_TOKEN are set by hand)
      plan = {
        adopt = true;
        variables.OPS_APP_CLIENT_ID = "Iv23liHIbNxGMNV2EESv";
      };
      # Applies, as teleozyme, after my approval: where this repo's own apply
      # runs. Its key and the state credentials are set by hand.
      production = {
        adopt = true;
        deploy = true;
        variables.OPS_APP_CLIENT_ID = "Iv23li6ESrImBQd0fDvU";
      };
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
  # No agents: cjohns.com/resume serves its `latest` release asset, which
  # Contents write (and so any agent token) could replace without a PR.
  # Change it from a supervised session instead.
  resume.repository = {
    visibility = "public";
    description = "💼 Professional experience";
    homepage_url = "";
  };
  "zx.dev" = {
    agents = true;
    agentsInstalled = true;
    repository = {
      visibility = "public";
      description = "🌐 personal website";
      homepage_url = "https://zx.dev";
      topics = ["nix-flake" "personal-website" "zola"];
    };
    requiredChecks = ["build"];
    # Created by hand; it only blocked force pushes
    rulesetIds.require_ci = 12057014;
    # The reusable approve workflow (teleoid). No cache secret: rc's CI pushes
    # the site to Attic as part of spore's build.
    environments.approve.variables.APPROVER_CLIENT_ID = "Iv23likJzKNAteBwoYdc";
  };
}
