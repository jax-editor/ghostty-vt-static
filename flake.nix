{
  description = "Build environment for libghostty-vt static archives";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in {
      devShells = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.mkShell {
            packages = [
              pkgs.zig_0_15    # ghostty's minimum_zig_version = "0.15.2"
              pkgs.cmake
              pkgs.ninja
              pkgs.git
            ];
          };
        });
    };
}
