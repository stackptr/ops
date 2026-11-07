# Invariants of the GitHub baseline, checked over the rendered config with no
# credentials (`nix flake check`, so on every PR). Prints each violation and
# fails if there are any. It catches mistakes, not intent: a PR can edit this
# file too, so review changes to it as policy changes.
#
# $apps: infrastructure/github/apps.nix; $repos: infrastructure/github/repos.nix

# The apps that may bypass each ruleset of a repo with options $cfg. Any
# other bypass actor besides the admin role is a violation, so no app
# (teleoid included) becomes one by accident; teleomycete bypasses only
# "Agent-only branches", and only once installed (`agentsInstalled`).
def allowed($name; $cfg):
  ( if $cfg.flakeUpdates // false then [$apps.teleotrope.id] else [] end ) as $updater
  | {
      "Require CI": [],
      "Require approval": $updater,
      "Agent branches": ($updater + (if $cfg.dependabot // false then [$apps.dependabot.id] else [] end)),
      "Agent-only branches": (if $cfg.agentsInstalled // false then [$apps.teleomycete.id] else [] end)
    }[$name] // [];


# The rulesets a repo gets: none if private (they need GitHub Pro); "Require
# CI" if it has checks to require; the agents' three if agents work on it;
# "Release tags" if its tags are releases; "Protect default branch" if
# nothing else guards its default branch
def expectedRulesets($cfg):
  if ($cfg.repository.visibility // "public") != "public" then []
  else
    (if ($cfg.requiredChecks // []) != [] then ["Require CI"] else [] end)
    + (if $cfg.agents // false then ["Require approval", "Agent branches", "Agent-only branches"] else [] end)
    + (if $cfg.releaseTags // false then ["Release tags"] else [] end)
    + (if ($cfg.requiredChecks // []) == [] and ($cfg.agents // false | not) then ["Protect default branch"] else [] end)
  end;

# What the rendered config may contain: the blocks, provider and resource
# types in use. Anything else (a `data` source like `external` or `http`, a
# `module`, another provider, a provisioner) could run code during `tofu
# plan`, which runs in `plan` with credentials and no reviewer for config
# changes. Extend these only on purpose.
def allowedBlocks: ["import", "provider", "removed", "resource", "terraform", "variable"];
def allowedTerraform: ["backend", "encryption", "required_providers"];
def allowedResources: [
  "github_actions_environment_secret",
  "github_actions_environment_variable",
  "github_actions_repository_oidc_subject_claim_customization_template",
  "github_repository",
  "github_repository_environment",
  "github_repository_environment_deployment_policy",
  "github_repository_ruleset",
  "github_workflow_repository_permissions"
];

(.resource.github_repository_ruleset // {} | [.[]]) as $rulesets
| (.resource.github_workflow_repository_permissions // {} | [.[]]) as $permissions
| (.resource.github_repository // {} | [.[]]) as $repositories
| (.resource.github_repository_environment // {} | to_entries) as $environments
| (.resource.github_repository_environment_deployment_policy // {}) as $policies
| [
    ( keys - allowedBlocks | .[]
      | "top-level \"\(.)\" isn't allowed: data sources, modules and the like run code during the plan"
    ),
    ( .terraform // {} | keys - allowedTerraform | .[]
      | "terraform.\(.) isn't allowed"
    ),
    ( (.terraform.required_providers // {} | keys) + (.provider // {} | keys) | unique - ["github"] | .[]
      | "provider \"\(.)\" isn't allowed: only github"
    ),
    ( .resource // {} | keys - allowedResources | .[]
      | "resource type \(.) isn't allowed; extend allowedResources in checks/baseline.jq on purpose"
    ),
    ( .resource // {} | to_entries[] | .key as $type | .value | to_entries[]
      | select(.value | has("provisioner") or has("connection"))
      | "\($type).\(.key): provisioners aren't allowed"
    ),
    ( $rulesets[] as $r
      | ($r.bypass_actors // [])[]
      | select(
          (.actor_type == "RepositoryRole" and .actor_id == 5)
          or (.actor_type == "Integration" and (.actor_id as $id | any(allowed($r.name; $repos[$r.repository] // {})[]; . == $id)))
          | not)
      | "\($r.repository): \"\($r.name)\" can't have bypass actor \(.actor_type) \(.actor_id)"
    ),
    ( $repos | to_entries[] | .key as $repo | expectedRulesets(.value)[] as $name
      | select([$rulesets[] | select(.repository == $repo and .name == $name)] | length != 1)
      | "\($repo): needs exactly one \"\($name)\" ruleset"
    ),
    ( $rulesets[] as $r
      | select(any(expectedRulesets($repos[$r.repository] // {})[]; . == $r.name) | not)
      | "\($r.repository): shouldn't have the \"\($r.name)\" ruleset"
    ),
    # The admin role bypasses the default branch's rulesets in the repo's
    # `adminBypass` mode ("pull_request": only by merging a PR), and every
    # other ruleset always, so a weakened mode stands out
    ( $rulesets[] as $r
      | ($r.conditions.ref_name.include | index("~DEFAULT_BRANCH") != null) as $default
      | (if $default then ($repos[$r.repository].adminBypass // "always") else "always" end) as $mode
      | ($r.bypass_actors // [])[]
      | select(.actor_type == "RepositoryRole" and .actor_id == 5 and .bypass_mode != $mode)
      | "\($r.repository): the admin role must bypass \"\($r.name)\" in \($mode) mode, not \(.bypass_mode)"
    ),
    ( $rulesets[]
      | select(.name == "Protect default branch" and (.conditions.ref_name.include != ["~DEFAULT_BRANCH"]
          or (.rules | .deletion != true or .non_fast_forward != true)))
      | "\(.repository): \"Protect default branch\" must block deleting and force-pushing the default branch"
    ),
    ( $rulesets[]
      | select(.name == "Release tags" and (.target != "tag" or .conditions.ref_name.include != ["~ALL"]
          or (.rules | .creation != true or .update != true or .deletion != true)))
      | "\(.repository): \"Release tags\" must restrict creating, moving and deleting every tag"
    ),
    ( $rulesets[]
      | select(.name == "Require CI" and ((.rules.required_status_checks.required_check // []) | length) == 0)
      | "\(.repository): \"Require CI\" needs at least one required check"
    ),
    # Agents need rulesets, which private repos can't have, and my own PRs
    # there merge through teleoid's approval, whose key lives in `approve`
    ( $repos | to_entries[] | select(.value.agents // false) | .key as $repo
      | ( select([$repositories[] | select(.name == $repo and .visibility == "public")] | length != 1)
          | "\($repo): agents need a public repository"
        ),
        ( select([$environments[] | select(.value.repository == $repo and .value.environment == "approve")] | length != 1)
          | "\($repo): agents need an `approve` environment (teleoid's key, for approve.yml)"
        )
    ),
    # teleotrope's credentials for update.yml, and only where it may merge
    ( $repos | to_entries[] | select(.value.flakeUpdates // false) | .key as $repo
      | select([$environments[] | select(.value.repository == $repo and .value.environment == "update")] | length != 1)
      | "\($repo): flakeUpdates needs an `update` environment (teleotrope's key, for update.yml)"
    ),
    ( $repos | keys[] as $repo
      | select(
          [ $permissions[]
            | select(.repository == $repo
                and .default_workflow_permissions == "read"
                and .can_approve_pull_request_reviews == false)
          ] | length != 1)
      | "\($repo): GITHUB_TOKEN must be read-only and unable to approve PRs"
    ),
    # Without its github_repository, a repo's settings go unmanaged, and
    # dropping it from a config that had it would destroy the repository
    ( $repos | keys[] as $repo
      | select([$repositories[] | select(.name == $repo)] | length != 1)
      | "\($repo): needs exactly one github_repository (`repository` in repos.nix)"
    ),
    ( $repositories[]
      | select(.archive_on_destroy != true or .lifecycle.prevent_destroy != true)
      | "\(.name): github_repository must set archive_on_destroy and prevent_destroy"
    ),
    ( $environments[]
      | select(
          .value.deployment_branch_policy != {protected_branches: false, custom_branch_policies: true}
          or $policies[.key].branch_pattern != "main")
      | "\(.value.repository): environment \(.value.environment) must be limited to main"
    ),
    ( $environments[]
      | select(.value.can_admins_bypass != false)
      | "\(.value.repository): environment \(.value.environment) must not let admins bypass its protections"
    ),
    ( .resource.github_actions_secret // {} | keys[]
      | "repository-level secret \(.): secrets go in environments"
    ),
    ( .resource.github_actions_environment_secret // {} | to_entries[]
      | select(.value | has("plaintext_value") or has("value"))
      | "secret \(.key): commit only sealed values (encrypted_value)"
    ),
    # A sealed box is 48 bytes plus the value, so 64 base64 characters (or
    # fewer) means an empty value: a failed command piped into `just seal`
    ( .resource.github_actions_environment_secret // {} | to_entries[]
      | select((.value.encrypted_value // "") | length <= 64)
      | "secret \(.key): sealed value is empty; seal it again"
    )
  ]
| if . == [] then "baseline: ok" else (join("\n") + "\n" | halt_error(1)) end
