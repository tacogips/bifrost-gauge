{
  description = "bifrost-gauge local Bifrost budget manager";

  inputs = {
    ccusage.url = "github:ryoppippi/ccusage";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      ccusage,
      nixpkgs,
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      mkPkgs = system: import nixpkgs { inherit system; };
      ccusagePackage = system: ccusage.packages.${system}.default;
      xcodeSwiftVersion = "6.3.2";
      bifrostHttpVersion = "v1.5.13";
      bifrostHttpHashes = {
        aarch64-darwin = "sha256-SIO1DwXa0gMFzuHrBkerb2TyrTXXm9Kac6UZrCML1A4=";
        x86_64-darwin = "sha256-FdAFc3awr1UNuT16UmrtnZSX2PWaCf4rqMTrYfAWoUc=";
      };
      bifrostHttpPlatform =
        system:
        let
          parts = nixpkgs.lib.splitString "-" system;
          cpu = builtins.elemAt parts 0;
          os = builtins.elemAt parts 1;
          arch =
            if cpu == "aarch64" then
              "arm64"
            else if cpu == "x86_64" then
              "amd64"
            else
              throw "Unsupported Bifrost CPU: ${cpu}";
          platform =
            if os == "darwin" then
              "darwin"
            else
              throw "Unsupported Bifrost OS: ${os}";
        in
        {
          inherit platform arch;
        };
      bifrostHttpPackage =
        system:
        let
          pkgs = mkPkgs system;
          platformInfo = bifrostHttpPlatform system;
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "bifrost-http";
          version = nixpkgs.lib.removePrefix "v" bifrostHttpVersion;

          src = pkgs.fetchurl {
            url = "https://downloads.getmaxim.ai/bifrost/${bifrostHttpVersion}/${platformInfo.platform}/${platformInfo.arch}/bifrost-http";
            hash = bifrostHttpHashes.${system};
          };

          dontUnpack = true;

          installPhase = ''
            runHook preInstall
            install -Dm755 "$src" "$out/bin/bifrost-http"
            runHook postInstall
          '';

          meta = {
            description = "Bifrost HTTP transport binary";
            homepage = "https://github.com/maximhq/bifrost";
            mainProgram = "bifrost-http";
          };
        };
    in
    {
      packages = forAllSystems (system: {
        bifrost-http = bifrostHttpPackage system;
        default = bifrostHttpPackage system;
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          bifrostHttp = bifrostHttpPackage system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.bash
              pkgs.coreutils
              pkgs.gitMinimal
              pkgs.go-task
              pkgs.jq
              bifrostHttp
              (ccusagePackage system)
            ];

            shellHook = ''
              export BIFROST_GAUGE_DEVELOPER_DIR="''${BIFROST_GAUGE_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
              export BIFROST_GAUGE_SDKROOT="''${BIFROST_GAUGE_SDKROOT:-$BIFROST_GAUGE_DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
              export DEVELOPER_DIR="$BIFROST_GAUGE_DEVELOPER_DIR"
              export SDKROOT="$BIFROST_GAUGE_SDKROOT"
              export BIFROST_GAUGE_XCODE_TOOLCHAIN_DIR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
              export BIFROST_GAUGE_XCODE_SWIFT="$BIFROST_GAUGE_XCODE_TOOLCHAIN_DIR/swift"

              if [ ! -x "$BIFROST_GAUGE_XCODE_SWIFT" ]; then
                echo "error: Xcode Swift ${xcodeSwiftVersion} not found at $BIFROST_GAUGE_XCODE_SWIFT" >&2
                echo "Install/select Xcode 26.5, or set BIFROST_GAUGE_DEVELOPER_DIR." >&2
                return 1
              fi

              export PATH="$BIFROST_GAUGE_XCODE_TOOLCHAIN_DIR:$PATH"
              xcode_swift_version="$("$BIFROST_GAUGE_XCODE_SWIFT" --version 2>/dev/null | head -n 1 || true)"
              case "$xcode_swift_version" in
                *"Apple Swift version ${xcodeSwiftVersion}"*|*"Swift version ${xcodeSwiftVersion}"*) ;;
                *)
                  echo "error: expected Xcode Swift ${xcodeSwiftVersion}, got: ''${xcode_swift_version:-not available}" >&2
                  return 1
                  ;;
              esac

              echo "Bifrost local tools are available."
              echo "Swift version: $xcode_swift_version"
              echo "Swift toolchain: $BIFROST_GAUGE_XCODE_TOOLCHAIN_DIR"
              echo "Run: nix run .#bifrost-host"
              echo "Check config: nix run .#bifrost-check"
              echo "Usage reports: task ccusage:daily"
            '';
          };
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          ccusageBin = ccusagePackage system;
          bifrostHttp = bifrostHttpPackage system;
          bifrostHost = pkgs.writeShellApplication {
            name = "bifrost-host";
            runtimeInputs = with pkgs; [
              bash
              coreutils
              gitMinimal
            ];
            text = ''
              set -euo pipefail

              repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              set -a
              if [ -f "$repo_root/.env" ]; then
                # shellcheck source=/dev/null
                . "$repo_root/.env"
              fi
              set +a

              cd "$repo_root/bifrost"
              exec "${bifrostHttp}/bin/bifrost-http" \
                -host "''${BIFROST_BIND_HOST:-127.0.0.1}" \
                -port "''${BIFROST_PORT:-18080}" \
                -log-level "''${BIFROST_LOG_LEVEL:-info}" \
                -log-style "''${BIFROST_LOG_STYLE:-pretty}" \
                -app-dir "$repo_root/bifrost" \
                "$@"
            '';
          };
          bifrostCheck = pkgs.writeShellApplication {
            name = "bifrost-check";
            runtimeInputs = with pkgs; [
              bash
              coreutils
              gitMinimal
            ];
            text = ''
              set -euo pipefail

              repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              runtime_dir="''${BIFROST_CHECK_RUNTIME_DIR:-$repo_root/.run-bifrost-check}"
              rm -rf "$runtime_dir"
              mkdir -p "$runtime_dir"
              cp "$repo_root/bifrost-check/config.json" "$runtime_dir/config.json"

              set -a
              if [ -f "$repo_root/.env" ]; then
                # shellcheck source=/dev/null
                . "$repo_root/.env"
              fi
              set +a

              export BIFROST_ENCRYPTION_KEY="''${BIFROST_ENCRYPTION_KEY:-local-check-encryption-key}"
              case "''${BIFROST_VK_PERSONAL:-}" in
                sk-bf-*) ;;
                *) export BIFROST_VK_PERSONAL="sk-bf-local-check-vk" ;;
              esac

              cd "$runtime_dir"
              exec "${bifrostHttp}/bin/bifrost-http" \
                -host "''${BIFROST_CHECK_BIND_HOST:-127.0.0.1}" \
                -port "''${BIFROST_CHECK_PORT:-18082}" \
                -log-level "''${BIFROST_LOG_LEVEL:-info}" \
                -log-style "''${BIFROST_LOG_STYLE:-pretty}" \
                -app-dir "$runtime_dir" \
                "$@"
            '';
          };
        in
        {
          default = {
            type = "app";
            program = "${bifrostHost}/bin/bifrost-host";
          };
          bifrost = {
            type = "app";
            program = "${bifrostHost}/bin/bifrost-host";
          };
          bifrost-host = {
            type = "app";
            program = "${bifrostHost}/bin/bifrost-host";
          };
          bifrost-check = {
            type = "app";
            program = "${bifrostCheck}/bin/bifrost-check";
          };
          ccusage = {
            type = "app";
            program = "${ccusageBin}/bin/ccusage";
          };
        }
      );
    };
}
