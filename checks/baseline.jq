# Invariants of the GitHub baseline, checked over the rendered config with no
# credentials (`nix flake check`, so on every PR). Prints each violation and
# fails if there are any. It catches mistakes, not intent: a PR can edit this
# file too, so review changes to it as policy changes.
#
# $apps: infrastructure/github/apps.nix; $repos: the names in repos.nix

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

(.resource.github_repository_ruleset // {} | [.[]]) as $rulesets
| (.resource.github_workflow_repository_permissions // {} | [.[]]) as $permissions
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
    ( $repos[] as $repo
      | rulesetNames[] as $name
      | select([$rulesets[] | select(.repository == $repo and .name == $name)] | length != 1)
      | "\($repo): needs exactly one \"\($name)\" ruleset"
    ),
    ( $repos[] as $repo
      | select(
          [ $permissions[]
            | select(.repository == $repo
                and .default_workflow_permissions == "read"
                and .can_approve_pull_request_reviews == false)
          ] | length != 1)
      | "\($repo): GITHUB_TOKEN must be read-only and unable to approve PRs"
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
    )
  ]
| if . == [] then "baseline: ok" else (join("\n") + "\n" | halt_error(1)) end
