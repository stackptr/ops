# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

Infrastructure as code for my personal GitHub and cloud services. Terranix modules in Nix compile to OpenTofu JSON, which OpenTofu applies.

- `infrastructure/`: Terranix modules; `default.nix` is the root and imports the rest
- `infrastructure/state.nix`: R2 state backend and client-side state encryption
- `tofu/`: OpenTofu working directory; `config.tf.json` is generated (gitignored)
- `.github/workflows/infrastructure.yml`: credential-free checks and a rendered-config diff on PRs; plan, then approved apply, on main; daily drift check
- `.github/workflows/ci.yml`: builds the config and pushes it to the Attic cache

## Common Commands

```bash
just build            # Terranix -> tofu/config.tf.json
just init             # build, then tofu init
just plan             # build, then tofu plan; extra args pass through (just plan -lock=false)
just show-config      # pretty-print the generated JSON
just diff [rev]       # diff the generated JSON against another revision's (default origin/main); needs no credentials
just fmt              # alejandra
```

Anything that touches state needs `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (an R2 token for the `ops-state` bucket), `TF_VAR_state_endpoint`, and `TF_VAR_state_passphrase`.

## Guardrails

- Merging to main plans against live infrastructure, and the `apply` job applies that saved plan once I approve it in the `production` environment. Don't merge a PR, or approve a deployment, unless asked.
- Don't run `just apply` or `just destroy` locally; CI applies. Local apply is break-glass only, and only when asked.
- The repo is public, so plan output in PR comments and Actions logs is public. Mark anything secret as `sensitive` so tofu redacts it.

## State and credentials

- State is in R2, locked with `use_lockfile`, and encrypted with OpenTofu state encryption (pbkdf2 + AES-GCM, enforced for state and plans). Losing the passphrase means losing the state.
- Branch and PR CI gets no credentials: `tofu plan` runs provider code and Nix evaluation of whatever it's given. PRs get `nix fmt --check`, `nix flake check`, and `just diff` against the base branch as their preview. Never add a repository-level secret, and never reference an environment from a job that runs on branches.
- Two environments, both limited to main, hold the same secret names: `plan` (read-only R2 token, no reviewer) and `production` (read-write token, me as required reviewer). Plans use `-lock=false`, since the read-only token can't take the lock, and save the plan as an artifact; it's encrypted, because plan encryption is enforced. `apply` applies exactly that plan, and tofu rejects it as stale if state changed in between.
- Backend credentials have to come from `AWS_*` env vars: OpenTofu rejects sensitive values in backend config. A provider that reads `AWS_*` (the AWS provider) must take its credentials in its provider block so it doesn't pick up the R2 token.

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

## Committing

- My git config requires signing, which you can't do (it needs an interactive GPG unlock). For commands that create commits, use `git -c commit.gpgsign=false …`, and never change git config to disable signing. Add a `Co-Authored-By:` trailer identifying yourself.

## Updating this file

- When a working solution reached through trial and error would help future sessions in this repo, add it to this file in the PR you're preparing and call it out in the PR description.

## Code style

- All files should end with a newline.
- Run `nix fmt` (alejandra) after changing Nix files.
