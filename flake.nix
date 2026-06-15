{
  description = "Local Bifrost configuration for personal AI budget management";

  inputs = {
    ccusage.url = "github:ryoppippi/ccusage";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, ccusage, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      mkPkgs = system: import nixpkgs { inherit system; };
      ccusagePackage = system: ccusage.packages.${system}.default;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = mkPkgs system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.bash
              pkgs.coreutils
              pkgs.docker-client
              pkgs.docker-compose
              pkgs.gitMinimal
              pkgs.go-task
              pkgs.jq
              (ccusagePackage system)
            ];

            shellHook = ''
              echo "Bifrost local tools are available."
              echo "Run: task bifrost:up"
              echo "Or:  nix run .#bifrost -- up"
              echo "Usage reports: task ccusage:daily"
            '';
          };
        });

      apps = forAllSystems (system:
        let
          pkgs = mkPkgs system;
          ccusageBin = ccusagePackage system;
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
          ccusage = {
            type = "app";
            program = "${ccusageBin}/bin/ccusage";
          };
        });
    };
}
