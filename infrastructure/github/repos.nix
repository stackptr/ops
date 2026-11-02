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
# - oidc: the repo's workflows use OIDC; subjects then include the ref, so
#   cloud trust policies can match ref:refs/heads/main
# - environments.<name>:
#   - adopt: the environment existed before ops managed it; import it
#   - mainPolicyId: its existing `main` deployment branch policy, to import.
#     Creating one where it already exists fails. List them with
#     `gh api repos/stackptr/<repo>/environments/<env>/deployment-branch-policies`.
#   - deploy: it deploys, so it also requires my approval
#   - secrets.<NAME>: a value sealed to the environment's public key with
#     `just seal <repo> <environment>`. Only GitHub can decrypt it, so it's
#     safe to commit, and state holds only this ciphertext.
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
    environments = {
      # App keys for approve.yml (teleoid) and update.yml (teleotrope)
      # (approve had no branch policy; ops created its `main` one)
      approve.adopt = true;
      update = {
        adopt = true;
        mainPolicyId = 64125768;
      };
      # deploy.yml, one per host
      glyph = {
        adopt = true;
        deploy = true;
        mainPolicyId = 64122768;
      };
      spore = {
        adopt = true;
        deploy = true;
        mainPolicyId = 64122731;
      };
      zeta = {
        adopt = true;
        deploy = true;
        mainPolicyId = 64122797;
      };
    };
  };
}
