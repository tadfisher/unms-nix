{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.unms;
  unms = pkgs.callPackage ./default.nix {};

in {
  options = {
    services.unms = {
      enable = mkEnableOption "Ubiquiti Network Management System";

      package = mkOption {
        default = unms.unms-server;
        type = types.package;
        description = ''
          UNMS server package to use.
        '';
      };

      reporting = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Enable analytics reporting.
        '';
      };

      httpPort = mkOption {
        default = 80;
        type = types.int;
        description = "
          HTTP port on which to listen.
        ";
      };

      httpsPort = mkOption {
        default = 443;
        type = types.int;
        description = "
          HTTPS port on which to listen.
        ";
      };

      wsPort = mkOption {
        default = 443;
        type = types.int;
        description = "
          Websocket port on which to listen for API requests.
        ";
      };

      publicHttpPort = mkOption {
        default = 80;
        type = types.int;
        description = "
          HTTP port to expose, e.g. if running behind a reverse proxy.
        ";
      };

      publicHttpsPort = mkOption {
        default = 443;
        type = types.int;
        description = "
          HTTPS port to expose, e.g. if running behind a reverse proxy.
        ";
      };

      publicWsPort = mkOption {
        default = 443;
        type = types.int;
        description = "
          Websocket API port to expose, e.g. if running behind a reverse proxy.
        ";
      };

      netflowPort = mkOption {
        default = 2205;
        type = types.int;
        description = "
          Netflow port on which to listen.
        ";
      };

      secureLinkSecret = mkOption {
        default = "enigma";
        type = types.str;
        description = "
          Unique secret used to authenticate API requests.
        ";
      };

      redis = {
        host = mkOption {
          default = "localhost";
          type = types.str;
          description = "
            Hostname or IP of the Redis server.
          ";
        };

        port = mkOption {
          default = 6379;
          type = types.int;
          description = "
            Redis server port.
          ";
        };

        db = mkOption {
          default = 0;
          type = types.int;
          description = "
            Redis database ID.
          ";
        };
      };

      fluentd = {
        host = mkOption {
          default = "localhost";
          type = types.str;
          description = "
            Hostname or IP of the Fluentd server.
          ";
        };

        port = mkOption {
          default = 24224;
          type = types.int;
          description = "
            Fluentd server port.
          ";
        };
      };

      postgres = {
        host = mkOption {
          default = "localhost";
          type = types.str;
          description = "
            Hostname or IP of the PostgreSQL server.
          ";
        };

        port = mkOption {
          default = 5432;
          type = types.int;
          description = "
            PostgreSQL server port.
          ";
        };

        db = mkOption {
          default = "unms";
          type = types.str;
          description = "
            PostgreSQL database in which to store UNMS data.
          ";
        };

        user = mkOption {
          default = "postgres";
          type = types.str;
          description = "
            PostgreSQL server user.
          ";
        };

        password = mkOption {
          default = "";
          type = types.str;
          description = ''
            PostgreSQL server password.

            Warning: this is stored in cleartext in the Nix store!
            Use <option>postgres.passwordFile</option> instead.
          '';
        };

        passwordFile = mkOption {
          default = null;
          type = types.nullOr types.path;
          description = "
            File containing the PostgreSQL server password.
         ";
        };

        schema = mkOption {
          default = "public";
          type = types.str;
          description = "
            PostgreSQL database schema.
          ";
        };
      };

      rabbitmq = {
        host = mkOption {
          default = "localhost";
          type = types.str;
          description = "
            Hostname or IP of the RabbitMQ server.
          ";
        };

        port = mkOption {
          default = 5672;
          type = types.int;
          description = "
            RabbitMQ server port.
          ";
        };
      };
    };
  };

  config = mkIf cfg.enable {

    systemd.services.unms = rec {
      description = "Ubiquiti Network Management System";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = mkMerge [
        {
          HOME = "%t/unms";
          HTTP_PORT = toString cfg.httpPort;
          HTTPS_PORT = toString cfg.httpsPort;
          WS_PORT = toString cfg.wsPort;
          PUBLIC_HTTP_PORT = toString cfg.publicHttpPort;
          PUBLIC_HTTPS_PORT = toString cfg.publicHttpsPort;
          PUBLIC_WS_PORT = toString cfg.publicWsPort;
          NETFLOW_PORT = toString cfg.netflowPort;
          UNMS_NETFLOW_PORT = toString cfg.netflowPort;
          UNMS_REDISDB_HOST = cfg.redis.host;
          UNMS_REDISDB_PORT = toString cfg.redis.port;
          UNMS_REDISDB_DB = toString cfg.redis.db;
          UNMS_FLUENTD_HOST = cfg.fluentd.host;
          UNMS_FLUENTD_PORT = toString cfg.fluentd.port;
          UNMS_PG_HOST = cfg.postgres.host;
          UNMS_PG_PORT = toString cfg.postgres.port;
          UNMS_PG_USER = cfg.postgres.user;
          UNMS_PG_PASSWORD = cfg.postgres.password; # TODO
          UNMS_PG_SCHEMA = cfg.postgres.schema;
          UNMS_RABBITMQ_HOST = cfg.rabbitmq.host;
          UNMS_RABBITMQ_PORT = toString cfg.rabbitmq.port;
          SECURE_LINK_SECRET = cfg.secureLinkSecret;
          NODE_ENV = "production";
        }

        (mkIf (!cfg.reporting) { SUPPRESS_REPORTING = "1"; })
      ];

      preStart =
        let
          dataDir = "/var/lib/${serviceConfig.StateDirectory}";
          publicDir = "/run/${serviceConfig.RuntimeDirectory}/public";

          dirs = [
            "${dataDir}/supportinfo"
            "${dataDir}/cert"
            "${dataDir}/images"
            "${dataDir}/firmwares"
            "${dataDir}/logs"
            "${dataDir}/config-backups"
            "${dataDir}/unms-backups"
            "${dataDir}/import"
            "${dataDir}/update"
          ];

          links = [
            { from = dataDir; to = "/run/${serviceConfig.RuntimeDirectory}/data"; }
            { from = "${dataDir}/images"; to = "${publicDir}/site-images"; }
            { from = "${dataDir}/firmwares"; to = "${publicDir}/firmwares"; }
          ];

          createDir = dir: ''
            if [ ! -L "${dir}" ] || [ ! -d "${dir}" ]; then
              echo "Creating ${dir}"
              mkdir -p "${dir}"
            fi
          '';

          linkDir = { from, to }: ''
            if [ -L "${to}" ] || [ -d "${to}" ]; then rm -rf "${to}"; fi
            echo "Linking ${from} -> ${to}"
            ln -s "${from}" "${to}"
          '';

          waitForHost = { host, port, ... }: name: ''
            echo "Waiting for ${name} host"
            while ! ${pkgs.netcat}/bin/nc -z "${host}" "${toString port}"; do sleep 1; done
          '';

        in ''
          env | sort

          echo "Populating app runtime"
          ${pkgs.xorg.lndir}/bin/lndir -silent "${cfg.package}/libexec/unms-server/deps/unms-server"

          ${concatMapStringsSep "\n" createDir dirs}
          ${concatMapStringsSep "\n" linkDir links}

          ${waitForHost cfg.postgres "PostgreSQL"}
          ${waitForHost cfg.rabbitmq "RabbitMQ"}
          ${waitForHost cfg.redis "Redis"}

          # trigger rewrite of Redis AOF file (see https://groups.google.com/forum/#!topic/redis-db/4p9ZvwS0NjQ)
          ${pkgs.redis}/bin/redis-cli -h '${cfg.redis.host}' -p '${toString cfg.redis.port}' BGREWRITEAOF
        '';

      script = ''
        PATH="/run/${serviceConfig.RuntimeDirectory}/node_modules/.bin:$PATH" ${cfg.package}/bin/unms
      '';

      serviceConfig = rec {
        AmbientCapabilities = "CAP_NET_BIND_SERVICE CAP_NET_RAW";
        DynamicUser = true;
        RuntimeDirectory = StateDirectory;
        RuntimeDirectoryPreserve = true;
        StateDirectory = "unms";
        WorkingDirectory = "%t/unms";
      };

      unitConfig = {
        AssertCapability = "CAP_NET_RAW";
      };
    };
  };
}
