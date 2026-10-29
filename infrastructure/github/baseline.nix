# The GitHub baseline, applied to every repo in ./repos.nix. It exists so the
# agents' app can be installed on a repo without its branches reaching
# secrets or bypassing review (stackptr/ops#3). Changes here change the
# agents' guardrails: review them as policy changes.
#
# - "Require approval" ruleset on the default branch: a PR with one approval
#   of its latest push; no force-pushes or deletions. Only the admin role and,
#   where a repo needs it, the updater app may bypass it. Never the agents'
#   app.
# - GITHUB_TOKEN is read-only by default and can't approve PRs, so a branch
#   workflow can't approve its own PR.
# - Secrets live only in environments, and every environment is limited to
#   main. Environments that deploy also need my approval.
# - Repos using OIDC put the ref in the subject claim.
#
# Repository-level secrets are banned too, but OpenTofu can't see resources
# it doesn't manage: the `secrets` job in .github/workflows/infrastructure.yml
# checks for them daily.
{lib, ...}: let
  repos = import ./repos.nix;

  # stackptr's user ID
  me = 4542907;

  # Repo admin, a built-in role with a fixed ID
  adminRole = 5;

  # OpenTofu resource names can't contain dots (zx.dev)
  id = lib.replaceStrings ["."] ["_"];

  ref = type: name: "${type}.${name}";

  forRepos = f: lib.concatMapAttrs (repo: cfg: f repo cfg) repos;

  forEnvironments = f:
    forRepos (repo: cfg:
      lib.concatMapAttrs (env: envCfg: f repo env ({secrets = {};} // envCfg)) (cfg.environments or {}));
in {
  data.github_app.teleotrope.slug = "teleotrope";

  resource.github_repository_ruleset = forRepos (repo: cfg: {
    ${id repo} = {
      repository = repo;
      name = "Require approval";
      target = "branch";
      enforcement = "active";
      conditions.ref_name = {
        include = ["~DEFAULT_BRANCH"];
        exclude = [];
      };
      rules = {
        deletion = true;
        non_fast_forward = true;
        pull_request = {
          required_approving_review_count = 1;
          dismiss_stale_reviews_on_push = true;
          require_last_push_approval = true;
        };
      };
      bypass_actors =
        [
          {
            actor_id = adminRole;
            actor_type = "RepositoryRole";
            bypass_mode = "always";
          }
        ]
        ++ lib.optional (cfg.updaterBypass or false) {
          actor_id = "\${data.github_app.teleotrope.id}";
          actor_type = "Integration";
          bypass_mode = "always";
        };
    };
  });

  resource.github_workflow_repository_permissions = forRepos (repo: _: {
    ${id repo} = {
      repository = repo;
      default_workflow_permissions = "read";
      can_approve_pull_request_reviews = false;
    };
  });

  resource.github_actions_repository_oidc_subject_claim_customization_template = forRepos (repo: cfg:
    lib.optionalAttrs (cfg.oidc or false) {
      ${id repo} = {
        repository = repo;
        use_default = false;
        include_claim_keys = ["repo" "ref"];
      };
    });

  resource.github_repository_environment = forEnvironments (repo: env: cfg: {
    "${id repo}_${env}" =
      {
        repository = repo;
        environment = env;
        deployment_branch_policy = {
          protected_branches = false;
          custom_branch_policies = true;
        };
      }
      // lib.optionalAttrs (cfg.deploy or false) {
        reviewers.users = [me];
      };
  });

  resource.github_repository_environment_deployment_policy = forEnvironments (repo: env: _: {
    "${id repo}_${env}" = {
      repository = repo;
      environment = "\${${ref "github_repository_environment" "${id repo}_${env}"}.environment}";
      branch_pattern = "main";
    };
  });

  resource.github_actions_environment_secret = forEnvironments (repo: env: cfg:
    lib.mapAttrs' (name: sealed:
      lib.nameValuePair "${id repo}_${env}_${name}" {
        repository = repo;
        environment = "\${${ref "github_repository_environment" "${id repo}_${env}"}.environment}";
        secret_name = name;
        encrypted_value = sealed;
      })
    cfg.secrets);

  import =
    lib.mapAttrsToList (repo: cfg: {
      to = ref "github_repository_ruleset" (id repo);
      id = "${repo}:${toString cfg.rulesetId}";
    }) (lib.filterAttrs (_: cfg: cfg ? rulesetId) repos)
    ++ lib.attrValues (forEnvironments (repo: env: cfg:
      lib.optionalAttrs (cfg.adopt or false) {
        "${id repo}_${env}" = {
          to = ref "github_repository_environment" "${id repo}_${env}";
          id = "${repo}:${env}";
        };
      }));
}
