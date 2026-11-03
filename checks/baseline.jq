# Invariants of the GitHub baseline, checked over the rendered config with no
# credentials (`nix flake check`, so on every PR). Prints each violation and
# fails if there are any. It catches mistakes, not intent: a PR can edit this
# file too, so review changes to it as policy changes.
#
# $apps: infrastructure/github/apps.nix; $repos: infrastructure/github/repos.nix

# The apps that may bypass each ruleset. Any other bypass actor besides the
# admin role is a violation, so no app (teleoid included) becomes one by
# accident, and teleomycete bypasses only "Agent-only branches".
def allowed($name):
  {
    "Require CI": [],
    "Require approval": [$apps.teleotrope.id],
    "Agent branches": [$apps.teleotrope.id],
    "Agent-only branches": [$apps.teleomycete.id]
  }[$name] // [];

def rulesetNames: ["Require CI", "Require approval", "Agent branches", "Agent-only branches"];

# The rulesets a repo gets: none if private (they need GitHub Pro); "Require
# CI" if it has checks to require; the other three if agents work on it
def expectedRulesets($cfg):
  if ($cfg.repository.visibility // "public") != "public" then []
  else
    (if ($cfg.requiredChecks // []) != [] then ["Require CI"] else [] end)
    + (if $cfg.agents // false then rulesetNames[1:] else [] end)
  end;

(.resource.github_repository_ruleset // {} | [.[]]) as $rulesets
| (.resource.github_workflow_repository_permissions // {} | [.[]]) as $permissions
| (.resource.github_repository // {} | [.[]]) as $repositories
| (.resource.github_repository_environment // {} | to_entries) as $environments
| (.resource.github_repository_environment_deployment_policy // {}) as $policies
| [
    ( $rulesets[] as $r
      | ($r.bypass_actors // [])[]
      | select(
          (.actor_type == "RepositoryRole" and .actor_id == 5)
          or (.actor_type == "Integration" and (.actor_id as $id | any(allowed($r.name)[]; . == $id)))
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
