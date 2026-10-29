# The GitHub baseline, applied to every repo in ./repos.nix. It exists so the
# agents' app can be installed on a repo without its branches reaching
# secrets or bypassing review (stackptr/ops#3). Changes here change the
# agents' guardrails: review them as policy changes.
#
# Four rulesets per repo (a bypass actor skips every rule in its ruleset, so
# rules with different bypass actors live in separate rulesets):
# - Require CI (default branch): the repo's checks pass; no force-pushes.
#   Only the admin role bypasses it.
# - Require approval (default branch): a PR with one approval of its latest
#   push; no force-pushes or deletions. The admin role and, with
#   `updaterBypass`, teleotrope bypass it.
# - Agent branches (every branch but the default and agents/**): only bypass
#   actors create, update or delete them, so agents can't push to the branch
#   behind my PR, which teleoid would then approve. The admin role and, with
#   `updaterBypass`, teleotrope bypass it.
# - Agent-only branches (agents/**): only the admin role and teleomycete
#   create or update them, so teleoid (Contents: write) can't push there.
#   Deletions and force-pushes stay allowed, for agents rebasing.
#
# Also: GITHUB_TOKEN is read-only by default and can't approve PRs; secrets
# live only in environments, every environment is limited to main, and
# deploy environments need my approval; repos using OIDC put the ref in the
# subject claim.
#
# The invariants (who may bypass what, every repo has every ruleset) are
# checked over the rendered config by checks/baseline.jq, without
# credentials. Repository-level secrets are banned too, but OpenTofu can't
# see what it doesn't manage: the workflow's `secrets` job checks for them.
{lib, ...}: let
  repos = import ./repos.nix;
  apps = import ./apps.nix;

  # stackptr's user ID
  me = 4542907;

  # GitHub Actions' integration ID, which required checks come from
  githubActions = 15368;

  admin = {
    # Repo admin, a built-in role with a fixed ID
    actor_id = 5;
    actor_type = "RepositoryRole";
    bypass_mode = "always";
  };

  app = name: {
    actor_id = apps.${name}.id;
    actor_type = "Integration";
    bypass_mode = "always";
  };

  defaultBranch = {
    include = ["~DEFAULT_BRANCH"];
    exclude = [];
  };

  agentBranches = "refs/heads/agents/**";

  rulesets = cfg: let
    updater = lib.optional (cfg.updaterBypass or false) (app "teleotrope");
  in {
    require_ci = {
      name = "Require CI";
      conditions.ref_name = defaultBranch;
      rules = {
        non_fast_forward = true;
        required_status_checks.required_check =
          map (context: {
            inherit context;
            integration_id = githubActions;
          })
          cfg.requiredChecks;
      };
      bypass_actors = [admin];
    };

    require_approval = {
      name = "Require approval";
      conditions.ref_name = defaultBranch;
      rules = {
        deletion = true;
        non_fast_forward = true;
        pull_request = {
          required_approving_review_count = 1;
          dismiss_stale_reviews_on_push = true;
          require_last_push_approval = true;
        };
      };
      bypass_actors = [admin] ++ updater;
    };

    agent_branches = {
      name = "Agent branches";
      conditions.ref_name = {
        include = ["~ALL"];
        exclude = ["~DEFAULT_BRANCH" agentBranches];
      };
      rules = {
        creation = true;
        update = true;
        deletion = true;
        non_fast_forward = true;
      };
      bypass_actors = [admin] ++ updater;
    };

    agent_only_branches = {
      name = "Agent-only branches";
      conditions.ref_name = {
        include = [agentBranches];
        exclude = [];
      };
      rules = {
        creation = true;
        update = true;
      };
      bypass_actors = [admin (app "teleomycete")];
    };
  };

  # OpenTofu resource names can't contain dots (zx.dev)
  id = lib.replaceStrings ["."] ["_"];

  forRepos = f: lib.concatMapAttrs f repos;

  forEnvironments = f:
    forRepos (repo: cfg:
      lib.concatMapAttrs (env: envCfg: f repo env ({secrets = {};} // envCfg)) (cfg.environments or {}));

  environment = repo: env: "\${github_repository_environment.${id repo}_${env}.environment}";
in {
  resource.github_repository_ruleset = forRepos (repo: cfg:
    lib.mapAttrs' (key: ruleset:
      lib.nameValuePair "${id repo}_${key}" ({
          repository = repo;
          target = "branch";
          enforcement = "active";
        }
        // ruleset))
    (rulesets cfg));

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
      environment = environment repo env;
      branch_pattern = "main";
    };
  });

  resource.github_actions_environment_secret = forEnvironments (repo: env: cfg:
    lib.mapAttrs' (name: sealed:
      lib.nameValuePair "${id repo}_${env}_${name}" {
        repository = repo;
        environment = environment repo env;
        secret_name = name;
        encrypted_value = sealed;
      })
    cfg.secrets);

  import = let
    rulesetImports = repo: cfg:
      lib.mapAttrsToList (key: rulesetId: {
        to = "github_repository_ruleset.${id repo}_${key}";
        id = "${repo}:${toString rulesetId}";
      }) (cfg.rulesetIds or {});

    environmentImports = repo: cfg:
      lib.mapAttrsToList (env: _: {
        to = "github_repository_environment.${id repo}_${env}";
        id = "${repo}:${env}";
      }) (lib.filterAttrs (_: envCfg: envCfg.adopt or false) (cfg.environments or {}));
  in
    lib.concatLists (lib.mapAttrsToList (repo: cfg: rulesetImports repo cfg ++ environmentImports repo cfg) repos);
}
