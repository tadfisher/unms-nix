{ stdenv, stdenvNoCC, dockerTools, yarn, yarn2nix, writeTextFile }:

let
  cfg = rec {
    httpPort = 80;
    httpsPort = 443;
    localNetwork = "192.168.3.1";
    publicHttpPort = httpPort;
    secureLinkSecret = "g9W6N1auZVTNjsOdyoDxEvNV06GsXSO7JeZiRu4TXusWMxJNmhuu31aUSUhBnUQX9UeWh1x9NnXiTMYD3z9hmI7uqbREw8nh7Xes";
    unmsHttpPort = 8081;
    unmsHost = "unms";
    unmsWsApiPort = 8084;
    unmsWsPort = 8082;
    wsPort = 8444;
    workerProcesses = "auto";
  };

  version = "0.13.2-alpha-2";
  tag = "0.13.2-alpha.2";

  unmsImage = dockerTools.pullImage {
    imageName = "ubnt/unms";
    imageDigest = "sha256:da6767875750b35790b8eb25272a73d5133340de8a86b3e030d6dafc4c474c36";
    sha256 = "0lqj61annxlcm9qjaj1qf1ckapzfc0ss9p0706241ppcqy99a17w";
    finalImageTag = tag;
  };

  unmsServerSrc = dockerTools.runWithOverlay {
    name = "unms-app-${version}-src";
    fromImage = unmsImage;
    postMount = ''
      mkdir -p $out
      shopt -s extglob
      cp -rL mnt/home/app/unms/!(node_modules) $out
      shopt -u extglob
      cat $out/package.json \
        | jq --argjson ws '{ "workspaces": [ "packages/*" ] }' '. + $ws' \
        | jq --argjson bin '{ "bin": { "unms": "index.js" } }' '. + $bin' \
        | jq '.dependencies = (.dependencies | to_entries | [.[] | select(.value | startswith("file:") | not)] | from_entries)' \
        | tee $out/package-ws.json
    '';
  };

  startScript = writeTextFile {
    name = "unms-start";
    executable = true;
    text = ''
      #!${stdenv.shell}
      export PATH="${stdenv.shellPackage}/bin:$PATH"
      ${yarn}/bin/yarn start
    '';
  };

  unms-server = yarn2nix.mkYarnPackage rec {
    name = "unms-server-${version}";
    src = unmsServerSrc;
    packageJSON = "${unmsServerSrc}/package-ws.json";
    yarnFlags = yarn2nix.defaultYarnFlags ++ [ "--production" ];

    workspaceDependencies = stdenv.lib.attrValues (yarn2nix.mkYarnWorkspace {
      name = "unms-server-ws-deps-${version}";
      src = unmsServerSrc;
      packageJSON = "${unmsServerSrc}/package-ws.json";
      yarnFlags = yarn2nix.defaultYarnFlags ++ [ "--production" ];
    });

    postInstall = ''
      ln -s ${startScript} $out/bin/unms
    '';
  };

in unms-server
