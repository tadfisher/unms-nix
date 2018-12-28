{ stdenvNoCC, fetchzip, version, cfg }:


let

  unmsSrc = fetchzip {
    url = "https://github.com/Ubiquiti-App/UNMS/archive/v${version}.tar.gz";
    sha256 = "155halcx75xbsq70z3jkyi81nb5k06h8bxx1209h42rv3khd46y3";
  };

  nginxConf = stdenvNoCC.mkDerivation rec {
    name = "unms-nginx-conf-${version}";
    src = unmsSrc;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out
      cd src/nginx
      for f in *.conf.template; do
        cp "$f" "$out/''${f%.template}"
      done
    '';

    postFixup = let esc = var: "'\${${var}}'"; in ''
      for conf in $out/*.conf; do
        substituteInPlace "$conf" \
          --replace ${esc "HTTP_PORT"}          ${toString cfg.httpPort} \
          --replace ${esc "HTTPS_PORT"}         ${toString cfg.httpsPort} \
          --replace ${esc "LOCAL_NETWORK"}      ${cfg.localNetwork} \
          --replace ${esc "PUBLIC_HTTPS_PORT"}  ${toString cfg.publicHttpPort} \
          --replace ${esc "SECURE_LINK_SECRET"} ${cfg.secureLinkSecret} \
          --replace ${esc "UNMS_HTTP_PORT"}     ${toString cfg.unmsHttpPort} \
          --replace ${esc "UNMS_HOST"}          ${toString cfg.unmsHost} \
          --replace ${esc "UNMS_WS_API_PORT"}   ${toString cfg.unmsWsApiPort} \
          --replace ${esc "UNMS_WS_PORT"}       ${toString cfg.unmsWsPort} \
          --replace ${esc "UNMS_WS_SHELL_PORT"} ${toString cfg.wsPort} \
          --replace ${esc "WORKER_PROCESSES"}   ${toString cfg.workerProcesses}
      done
    '';
  };

in nginxConf
