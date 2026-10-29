# The repos that get the GitHub baseline in ./baseline.nix. Personal accounts
# have no account-wide rulesets, so a repo must be listed here before the
# agents' app (teleomycete) goes on it. Changing this file changes the
# agents' guardrails: review it as a policy change.
#
# Per repo:
# - rulesetId: import an existing "Require approval" ruleset instead of
#   creating a second one
# - updaterBypass: teleotrope (the updater app) may skip the approval rule
# - oidc: the repo's workflows use OIDC; subjects then include the ref, so
#   cloud trust policies can match ref:refs/heads/main
# - environments.<name>:
#   - adopt: the environment existed before ops managed it; import it
#   - deploy: it deploys, so it also requires my approval
#   - secrets.<NAME>: a value sealed to the environment's public key with
#     `just seal <repo> <environment>`. Only GitHub can decrypt it, so it's
#     safe to commit, and state holds only this ciphertext.
{
  rc = {
    # Created by hand in stackptr/rc#733
    rulesetId = 25745892;
    # Opens and merges rc's daily flake updates (stackptr/rc#732)
    updaterBypass = true;
    environments = {
      # App keys for approve.yml (teleoid) and update.yml (teleotrope)
      approve.adopt = true;
      update.adopt = true;
      # deploy.yml, one per host
      glyph = {
        adopt = true;
        deploy = true;
      };
      spore = {
        adopt = true;
        deploy = true;
      };
      zeta = {
        adopt = true;
        deploy = true;
      };
    };
  };
}
