# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

Infrastructure as code for my personal GitHub and cloud services. Terranix modules in Nix compile to OpenTofu JSON, which OpenTofu applies.

- `infrastructure/`: Terranix modules; `default.nix` is the root and imports the rest
- `infrastructure/state.nix`: R2 state backend and client-side state encryption
- `infrastructure/github/`: GitHub as the stackptr account. `repos.nix` is the one list of repos that get the baseline; `baseline.nix` is the policy applied to each; `apps.nix` records the GitHub Apps, their IDs and permissions; `sealed.json` holds environment secrets, sealed
- `checks/baseline.jq`: the baseline's invariants, checked over the rendered config by `nix flake check`
- `scripts/seal.py`: seals a secret to a GitHub public key; packaged with PyNaCl as the flake's `seal`, which `just seal` runs through `nix run`, so it works outside the dev shell
- `tofu/`: OpenTofu working directory; `config.tf.json` is generated (gitignored)
- `.github/workflows/infrastructure.yml`: credential-free checks and a rendered-config diff on PRs; plan, then approved apply, on main; daily drift check
- `.github/workflows/ci.yml`: builds the config; on main only, pushes it to the Attic cache from the main-only `attic` environment, with the attic client from a fixed rev (bump it by hand)

## Common Commands

```bash
just build            # Terranix -> tofu/config.tf.json
just init             # build, then tofu init
just plan             # build, then tofu plan; extra args pass through (just plan -lock=false)
just show-config      # pretty-print the generated JSON
just diff [rev]       # diff the generated JSON against another revision's (default origin/main); needs no credentials
just seal <repo> <env> <NAME> # seal a secret (stdin) into sealed.json; needs `gh` logged in
just fmt              # alejandra
```

Anything that touches state needs `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (an R2 token for the `ops-state` bucket), `TF_VAR_state_endpoint`, and `TF_VAR_state_passphrase`.

## Guardrails

- Merging to main plans against live infrastructure, and the `apply` job applies that saved plan once I approve it in the `production` environment. Don't merge a PR, or approve a deployment, unless asked.
- Approving `production` runs that commit's code, not just its plan. When a push changes `.github/`, `flake.*`, `Justfile`, `scripts/` or `checks/`, the plan job flags it on the run page; review those changes before approving.
- Don't run `just apply` or `just destroy` locally; CI applies. Local apply is break-glass only, and only when asked.
- The repo is public, so plan output in PR comments and Actions logs is public. Mark anything secret as `sensitive` so tofu redacts it.

## State and credentials

- State is in R2, locked with `use_lockfile`, and encrypted with OpenTofu state encryption (pbkdf2 + AES-GCM, enforced for state and plans). Losing the passphrase means losing the state.
- Branch and PR CI gets no credentials: `tofu plan` runs provider code and Nix evaluation of whatever it's given. PRs get `nix fmt --check`, `nix flake check`, and `just diff` against the base branch as their preview. Never add a repository-level secret, and never reference an environment from a job that runs on branches.
- Two environments, both limited to main with admin bypass off, hold the same secret names: `plan` (read-only R2 token, no reviewer) and `production` (read-write token, me as required reviewer). Plans use `-lock=false`, since the read-only token can't take the lock, and save the plan as an artifact; it's encrypted, because plan encryption is enforced. `apply` applies exactly that plan, and tofu rejects it as stale if state changed in between.
- Backend credentials have to come from `AWS_*` env vars: OpenTofu rejects sensitive values in backend config. A provider that reads `AWS_*` (the AWS provider) must take its credentials in its provider block so it doesn't pick up the R2 token.

## GitHub baseline

The baseline (`infrastructure/github/baseline.nix`) is what makes it safe to install the agents' app (teleomycete) on a repo: up to four rulesets (Require CI where the repo has `requiredChecks`; Require approval, Agent branches and Agent-only branches where it has `agents`; Release tags, protecting every tag, where it has `releaseTags`; none on private repos, which would need GitHub Pro), read-only `GITHUB_TOKEN` that can't approve PRs, secrets only in main-only environments with no admin bypass (deploy environments also need my approval, except rc's `spore`, which deploys main on a schedule), and OIDC subjects that include the ref. See stackptr/ops#3, stackptr/rc#763, and rc's CLAUDE.md "GitHub apps and rulesets" for how the three apps and four rulesets fit together.

- `repos.nix`, `baseline.nix`, `apps.nix` and `checks/baseline.jq` set the agents' own guardrails. A change to any of them is a policy change: say why in the PR description.
- Bypass actors: only the admin role, teleotrope (on Require approval and Agent branches, for repos with `updaterBypass`), Dependabot (on Agent branches, for repos with `dependabot`, so it can push its `dependabot/**` branches) and teleomycete (on Agent-only branches, for repos with `agentsInstalled`). GitHub rejects an app as a bypass actor (422 "must be part of the ruleset source") unless it's installed on the repo, or for Dependabot, running there; that's why both are options rather than defaults. teleoid is never one. `checks/baseline.jq` enforces this as an allowlist, so extend the allowlist only on purpose. Never set `can_approve_pull_request_reviews = true`.
- Every repo gets `infrastructure/github/repository.nix`'s settings defaults (rc's: squash and rebase merges, PR title as the squash subject, auto-merge, delete merged branches) and sets only `visibility`, `description`, `homepage_url` and optionally `topics`. Contradictory options (agents on a private repo, `updaterBypass` without agents) fail evaluation.
- Install teleomycete only on repos with `agents`, and only once the apply adding the repo has landed: the agents' token covers every repo in the installation, and until then nothing stops it pushing anywhere. Import anything it already has (`rulesetIds`, and `adopt` and `mainPolicyId` on environments) rather than creating duplicates. Creating a deployment branch policy that already exists fails with "Provider produced inconsistent result after apply … root object was present, but now absent"; import it by ID (`mainPolicyId`) instead. The locked provider (6.8.3) never sets `repository` or `environment` when it reads a policy, so the plan after an import replaces it once: it deletes and recreates the identical policy, and for a few seconds no branch can deploy (it fails closed). Remove the `mainPolicyId` once that apply lands, since the policy it names is gone.
- Environment variables (`environments.<name>.variables`, like an app's client ID) are managed here too; creating one that already exists updates it, so they need no import.
- App installations and permissions are managed by hand in each app's settings and recorded in `apps.nix`; keep the record in step.
- Secrets go in `sealed.json`, sealed to their environment's public key: `printf %s "$value" | just seal <repo> <env> <NAME>`, or pipe the value straight from its source. Only GitHub can decrypt them, so they're safe to commit, and state holds only the ciphertext. Never put a plaintext secret in Nix, a variable, or state. The environment must exist in GitHub before you seal for it, so a new environment lands in one apply and its secrets in the next. A key from `sealed.json` with no matching environment in `repos.nix` fails evaluation.
- OpenTofu can't see repository-level secrets it doesn't manage; the workflow's `secrets` job checks for them daily and alerts #alerts.
- The provider comes from nixpkgs (`opentofu.withPlugins` in `flake.nix`), so `flake.lock` is its supply chain. Write against the locked provider's schema (check `nix eval` of `terraform-providers.integrations_github.version`), not the registry's latest docs.
- CI authenticates as two GitHub Apps through `GITHUB_TOKEN`: teleopsis in `plan`, teleozyme in `production`. teleopsis has Administration write, not read: GitHub shows a ruleset's bypass actors only to credentials that can edit it, and read-only plans showed them missing and couldn't detect drift in them. So the `plan` environment can edit GitHub settings; R2 state writes and every apply still need `production`. `github_app_installation_repository` doesn't work with app tokens, and a fine-grained PAT can add repos to an installation but not list them, so installations stay manual rather than putting a classic `repo` token in CI.

## Onboarding a repo

In order; each step waits for the one before to apply.

1. **Survey it.** Settings (`gh api repos/stackptr/<repo>`; check `has_pull_requests` is true, since the locked provider can't set it and agents need PRs), rulesets and their IDs, environments and their `main` policy IDs, environment variables, repo-level secrets, and workflows: their triggers, the secrets each job reads, and the check names on a recent PR. A required check must run on `pull_request`, or PRs never get it.
2. **Install teleopsis and teleozyme** on the repo by hand. Without them the plan can't read it.
3. **Add it to `repos.nix`** in one PR: `repository`, `requiredChecks`, `rulesetIds` and `adopt`/`mainPolicyId` for what exists, an environment (main-only) for each group of secrets its workflows use, their `variables`, and, for agents, `agents = true` (plus `dependabot = true` if it has a `.github/dependabot.yml`) and an `approve` environment with `variables.APPROVER_CLIENT_ID`. Not `agentsInstalled` yet. The plan shows the settings moving to the defaults; check nothing else changes. From this apply, my own PRs there need an admin merge until step 6.
4. **Seal its secrets** in a second PR, once the environments exist: each workflow secret, and for agents `APPROVER_PRIVATE_KEY` in `approve` (teleoid's key, the same in every repo).
5. **For agents, install teleoid** on the repo by hand. It's not a bypass actor, so it can come any time before step 6's approve caller first runs.
6. **Change the repo itself**, in a PR there that you push (agents can't touch workflows): each job that reads a secret declares its `environment:`, privileged jobs run only from main and pin their tools rather than taking them from the branch's lock file, and with agents, a caller of the reusable approve workflow in stackptr/actions (with `secrets: inherit`). Then delete the repo-level secrets; until then the daily `secrets` job fails for the repo.
7. **For agents, install teleomycete** by hand, then set `agentsInstalled = true` in a one-line PR so it may push `agents/**`. Between the two, every branch is already guarded: "Agent-only branches" lets only the admin role push there. For flake updates that merge themselves, install teleotrope and set `updaterBypass` too.

## Terranix gotchas

- Escape OpenTofu interpolation in Nix strings: `"\${var.foo}"`.
- Where OpenTofu wants a static reference rather than an expression, JSON syntax takes a bare traversal string with no `${}`. For example, the encryption block's `method = "method.aes_gcm.state"`; `"${method.aes_gcm.state}"` fails with "A single static variable reference is required".
- Flakes only see tracked files: `git add` a new module before `nix build`.

## Sandboxed sessions

Cloud sessions can't download GitHub tarballs (`github:` inputs fail with HTTP 403) but can `git clone` public repos. To build, override each `github:` input with a shallow git fetch of its locked rev. That includes nixpkgs: the first fetch takes a few minutes, but the channel tarball is a different nixpkgs, so tool versions wouldn't match CI's.

```bash
# Prints --override-input flags for the root inputs and terranix's inputs
flags=$(jq -r '.nodes as $n
  | [["", .nodes.root.inputs], ["terranix/", .nodes.terranix.inputs]][]
  | .[0] as $p | .[1] | to_entries[] | select(.value | type == "string") | .key as $k
  | $n[.value].locked | select(.type == "github")
  | "--override-input \($p)\($k) git+https://github.com/\(.owner)/\(.repo)?rev=\(.rev)&shallow=1"' flake.lock)
nix build .#terraformConfiguration $flags --no-write-lock-file
nix flake check $flags --no-write-lock-file
nix fmt $flags --no-write-lock-file -- --check .
```

`just` recipes call `nix build` without these flags, so run their commands by hand.

To test backend or workflow changes without R2, run MinIO as the S3 endpoint (`NIXPKGS_ALLOW_INSECURE=1 nix build --impure nixpkgs#minio nixpkgs#minio-client`) and point `TF_VAR_state_endpoint` at it. MinIO's `readonly` policy stands in for the plan job's read-only token.

## Branching

- Branch naming: `type-short-slug`, where `type` is one of `feat`, `fix`, `chore`, `refactor` and the slug is 2 to 4 words, e.g. `feat-cloudflare-dns`, `fix-drift-check`.
- In cloud sessions, use this scheme even when the session assigns a `claude/…` branch name.
- PR title: `type: short description`, e.g. `feat: manage cloudflare dns`. PRs are squash-merged, so the title becomes the commit message.
- PR description: a brief summary of what changed, what to test or verify, and any secrets or manual setup the change needs.
- When work diverges from what its issue stipulates (an item skipped or done differently, or scope added or dropped), comment on the issue at the time, saying what changed and why, so the issue stays an accurate record.

## Committing

- My git config requires signing, which you can't do (it needs an interactive GPG unlock). For commands that create commits, use `git -c commit.gpgsign=false …`, and never change git config to disable signing. Add a `Co-Authored-By:` trailer identifying yourself.

## Updating this file

- When a working solution reached through trial and error would help future sessions in this repo, add it to this file in the PR you're preparing and call it out in the PR description.

## Code style

- All files should end with a newline.
- Run `nix fmt` (alejandra) after changing Nix files.
