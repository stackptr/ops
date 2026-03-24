# ops

Infrastructure-as-code repo using [Terranix](https://terranix.org/) to generate [OpenTofu](https://opentofu.org/) configurations from Nix.

## Stack

- **Nix Flakes** — reproducible dev environment and build pipeline
- **Terranix** — define infrastructure in Nix, compile to OpenTofu JSON
- **OpenTofu** — provision infrastructure
- **Just** — task runner for build/plan/apply workflows
- **Attic** — Nix binary cache at `cache.zx.dev`
- **GitHub Actions** — CI validates Terranix builds and pushes artifacts to cache

## Layout

```
infrastructure/   Terranix modules (Nix → Terraform JSON)
tofu/             Generated OpenTofu config (gitignored)
flake.nix         Flake definition, dev shell, and build outputs
Justfile          Build/plan/apply recipes
```

## Usage

Enter the dev shell (automatic with direnv, or `nix develop`), then:

```
just build       # generate OpenTofu JSON from Terranix
just init        # initialize OpenTofu
just plan        # preview changes
just apply       # apply changes
just validate    # validate config
just show-config # pretty-print generated JSON
just fmt         # format Nix files
```
