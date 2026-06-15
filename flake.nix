{
  description = "Local Bifrost configuration for personal AI budget management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              bash
              coreutils
              docker-client
              docker-compose
              gitMinimal
              jq
            ];

            shellHook = ''
              echo "Bifrost local tools are available."
              echo "Run: scripts/bifrost-compose.sh up"
              echo "Or:  nix run .#bifrost -- up"
            '';
          };
        });

      apps = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          bifrost = pkgs.writeShellApplication {
            name = "bifrost";
            runtimeInputs = with pkgs; [
              bash
              coreutils
              docker-client
              docker-compose
              gitMinimal
            ];
            text = ''
              set -euo pipefail

              repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              exec "$repo_root/scripts/bifrost-compose.sh" "$@"
            '';
          };
        in
        {
          default = {
            type = "app";
            program = "${bifrost}/bin/bifrost";
          };
          bifrost = {
            type = "app";
            program = "${bifrost}/bin/bifrost";
          };
        });
    };
}
