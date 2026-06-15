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
      mkPkgs = system: import nixpkgs { inherit system; };
      mkCcusage = pkgs: pkgs.writeShellApplication {
        name = "ccusage";
        runtimeInputs = with pkgs; [
          nodejs
        ];
        text = ''
          set -euo pipefail

          exec npx --yes ccusage@latest "$@"
        '';
      };
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = mkPkgs system;
          ccusage = mkCcusage pkgs;
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
              pkgs.nodejs
              ccusage
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
          ccusage = mkCcusage pkgs;
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
            program = "${ccusage}/bin/ccusage";
          };
        });
    };
}
