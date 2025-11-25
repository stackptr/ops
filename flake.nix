{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} (top @ {
      config,
      withSystem,
      moduleWithSystem,
      ...
    }: {
      flake = {
        nixConfig = {
          experimental-features = ["nix-command" "flakes"];
          extra-substituters = [
            "https://stackptr.cachix.org"
          ];
          extra-trusted-public-keys = [
            "stackptr.cachix.org-1:5e2q7OxdRdAtvRmHTeogpgJKzQhbvFqNMmCMw71opZA="
          ];
        };
      };
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {pkgs, ...}: {
        devShells.default = pkgs.mkShell {packages = [pkgs.just];};
        formatter = pkgs.alejandra;
      };
    });
}
