{
  lib,
  pkgs,
  bifrostGaugeFlake,
  ...
}:

# Usage from your nix-darwin flake:
#
# inputs.bifrost-gauge.url = "github:tacogips/bifrost-gauge";
#
# darwinConfigurations.<host> = darwin.lib.darwinSystem {
#   specialArgs = {
#     bifrostGaugeFlake = inputs.bifrost-gauge;
#   };
#   modules = [
#     ./nix-darwin-bifrost-gauge.nix
#   ];
# };

let
  user = "your-user";
  home = "/Users/${user}";
  stateDir = "${home}/.local/state/bifrost-gauge/bifrost";
  configDir = "${home}/.config/bifrost-gauge";
  envFile = "${configDir}/bifrost.env";
  logDir = "${home}/Library/Logs/bifrost-gauge";
  bifrostHttp = bifrostGaugeFlake.packages.${pkgs.system}.bifrost-http;

  bifrostConfig = pkgs.writeText "bifrost-config.json" (
    builtins.toJSON {
      "$schema" = "https://www.getbifrost.ai/schema";
      encryption_key = "env.BIFROST_ENCRYPTION_KEY";
      client = {
        drop_excess_requests = false;
        enforce_auth_on_inference = true;
      };
      providers = {
        openai.keys = [
          {
            name = "openai-primary";
            value = "env.OPENAI_API_KEY";
            models = [ "*" ];
            weight = 1.0;
          }
        ];
        anthropic.keys = [
          {
            name = "anthropic-primary";
            value = "env.ANTHROPIC_API_KEY";
            models = [ "*" ];
            weight = 1.0;
          }
        ];
      };
      governance = {
        budgets = [
          {
            id = "budget-personal-default";
            virtual_key_id = "vk-personal";
            max_limit = 10.0;
            reset_duration = "1d";
            calendar_aligned = true;
          }
        ];
        rate_limits = [
          {
            id = "rl-personal-hourly";
            request_max_limit = 1000;
            request_reset_duration = "1h";
            token_max_limit = 1000000;
            token_reset_duration = "1h";
          }
        ];
        virtual_keys = [
          {
            id = "vk-personal";
            name = "default-budget";
            description = "Local personal key with a default hard budget backstop.";
            value = "env.BIFROST_VK_PERSONAL";
            is_active = true;
            rate_limit_id = "rl-personal-hourly";
            provider_configs = [
              {
                id = 1;
                provider = "openai";
                allowed_models = [ "*" ];
                key_ids = [ "*" ];
                weight = 1.0;
              }
              {
                id = 2;
                provider = "anthropic";
                allowed_models = [ "*" ];
                key_ids = [ "*" ];
                weight = 1.0;
              }
            ];
          }
        ];
      };
      config_store = {
        enabled = true;
        type = "sqlite";
        config.path = "./config.db";
      };
    }
  );

  bifrostHost = pkgs.writeShellApplication {
    name = "bifrost-gauge-bifrost-host";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
    ];
    text = lib.concatStringsSep "\n" [
      "set -euo pipefail"
      ""
      "install -d -m 0755 ${lib.escapeShellArg stateDir}"
      "install -d -m 0755 ${lib.escapeShellArg configDir}"
      "install -m 0644 ${bifrostConfig} ${lib.escapeShellArg stateDir}/config.json"
      ""
      "if [ ! -f ${lib.escapeShellArg envFile} ]; then"
      "  printf '%s\\n' \\"
      "    \"error: Bifrost env file is missing.\" \\"
      "    \"\" \\"
      "    \"Create this file:\" \\"
      "    \"  ${envFile}\" \\"
      "    \"\" \\"
      "    \"Example:\" \\"
      "    \"  BIFROST_ENCRYPTION_KEY=<generate with: openssl rand -base64 32>\" \\"
      "    \"  BIFROST_VK_PERSONAL=<local virtual key>\" \\"
      "    \"  OPENAI_API_KEY=\" \\"
      "    \"  ANTHROPIC_API_KEY=\" >&2"
      "  exit 1"
      "fi"
      ""
      "set -a"
      "# shellcheck source=/dev/null"
      ". ${lib.escapeShellArg envFile}"
      "set +a"
      ""
      ": \"\${BIFROST_BIND_HOST:=127.0.0.1}\""
      ": \"\${BIFROST_PORT:=18080}\""
      ": \"\${BIFROST_LOG_LEVEL:=info}\""
      ": \"\${BIFROST_LOG_STYLE:=pretty}\""
      "export BIFROST_BIND_HOST BIFROST_PORT BIFROST_LOG_LEVEL BIFROST_LOG_STYLE"
      ""
      "cd ${lib.escapeShellArg stateDir}"
      "exec ${bifrostHttp}/bin/bifrost-http -host \"$BIFROST_BIND_HOST\" -port \"$BIFROST_PORT\" -log-level \"$BIFROST_LOG_LEVEL\" -log-style \"$BIFROST_LOG_STYLE\" -app-dir ${lib.escapeShellArg stateDir}"
    ];
  };
in
{
  # Install the menu bar app declaratively with nix-darwin's Homebrew module.
  homebrew = {
    enable = true;
    taps = [ "tacogips/tap" ];
    casks = [ "tacogips/tap/bifrost-gauge" ];
  };

  system.activationScripts.bifrostGaugeRuntimeDirs.text = ''
    install -d -m 0755 -o ${user} -g staff ${lib.escapeShellArg configDir}
    install -d -m 0755 -o ${user} -g staff ${lib.escapeShellArg stateDir}
    install -d -m 0755 -o ${user} -g staff ${lib.escapeShellArg logDir}
  '';

  launchd.user.agents.bifrost-gauge-bifrost = {
    serviceConfig = {
      Label = "com.local.bifrost-gauge.bifrost";
      ProgramArguments = [
        "${bifrostHost}/bin/bifrost-gauge-bifrost-host"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      WorkingDirectory = stateDir;
      StandardOutPath = "${logDir}/bifrost-host-launchd.out.log";
      StandardErrorPath = "${logDir}/bifrost-host-launchd.err.log";
    };
  };

  launchd.user.agents.bifrost-gauge-menubar = {
    serviceConfig = {
      Label = "com.local.bifrost-gauge.menubar";
      ProgramArguments = [
        "/Applications/bifrost-gauge.app/Contents/MacOS/bifrost-gauge"
        "--base-url"
        "http://127.0.0.1:18080"
        "--vk-id"
        "vk-personal"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${logDir}/bifrost-gauge-launchd.out.log";
      StandardErrorPath = "${logDir}/bifrost-gauge-launchd.err.log";
    };
  };
}
