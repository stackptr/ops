{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    terranix = {
      url = "github:terranix/terranix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    attic = {
      url = "github:zhaofengli/attic";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      flake = {
        nixConfig = {
          experimental-features = ["nix-command" "flakes"];
          extra-substituters = [
            "https://cache.zx.dev/main"
            "https://cache.zx.dev/ops"
          ];
          extra-trusted-public-keys = [
            "main:mu0jkxdJTGWC3djDSEQb3rvZgqlhA8WVMulcTo5IW6c="
          ];
        };
      };
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {
        pkgs,
        self',
        system,
        ...
      }: {
        packages.terraformConfiguration = inputs.terranix.lib.terranixConfiguration {
          inherit system;
          modules = [./infrastructure];
        };

        # The GitHub baseline's invariants, over the rendered config
        checks.baseline =
          pkgs.runCommand "baseline" {
            nativeBuildInputs = [pkgs.jq];
            apps = builtins.toJSON (import ./infrastructure/github/apps.nix);
            repos = builtins.toJSON (builtins.attrNames (import ./infrastructure/github/repos.nix));
          } ''
            jq -r -f ${./checks/baseline.jq} --argjson apps "$apps" --argjson repos "$repos" \
              ${self'.packages.terraformConfiguration}
            touch $out
          '';

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.jq
            pkgs.just
            # `just seal`
            (pkgs.python3.withPackages (ps: [ps.pynacl]))
            # Providers come from nixpkgs, so flake.lock pins them and
            # `tofu init` never downloads one from the registry
            (pkgs.opentofu.withPlugins (p: [p.integrations_github]))
          ];
        };

        formatter = pkgs.alejandra;
      };
    };
}
