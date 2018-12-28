
{ stdenv, stdenvNoCC, fetchurl, fetchzip, dockerTools, buildah, skopeo, srcOnly, runCommand, writeTextFile
, nodejs, nodePackages, pkgconfig, vips
, yarn, yarn2nix
, vmTools, utillinux, e2fsprogs, jshon, rsync, jq, lib }:

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

  runWithOverlay = {
    name,
    fromImage ? null,
    fromImageName ? null,
    fromImageTag ? null,
    diskSize ? 1024,
    preMount ? "",
    postMount ? "",
    postUmount ? ""
  }:
    vmTools.runInLinuxVM (
      runCommand name {
        preVM = vmTools.createEmptyImage {
          size = diskSize;
          fullName = "docker-run-disk";
        };
        inherit fromImage fromImageName fromImageTag;

        buildInputs = [ utillinux e2fsprogs jshon rsync jq ];
      } ''
      rm -rf $out
      mkdir disk
      mkfs /dev/${vmTools.hd}
      mount /dev/${vmTools.hd} disk
      cd disk
      if [[ -n "$fromImage" ]]; then
        echo "Unpacking base image..."
        mkdir image
        tar -C image -xpf "$fromImage"
        # If the image name isn't set, read it from the image repository json.
        if [[ -z "$fromImageName" ]]; then
          fromImageName=$(jshon -k < image/repositories | head -n 1)
          echo "From-image name wasn't set. Read $fromImageName."
        fi
        # If the tag isn't set, use the name as an index into the json
        # and read the first key found.
        if [[ -z "$fromImageTag" ]]; then
          fromImageTag=$(jshon -e $fromImageName -k < image/repositories \
                         | head -n1)
          echo "From-image tag wasn't set. Read $fromImageTag."
        fi
        # Use the name and tag to get the parent ID field.
        parentID=$(jshon -e $fromImageName -e $fromImageTag -u \
                   < image/repositories)
        cat ./image/manifest.json  | jq -r '.[0].Layers | .[]' > layer-list
      else
        touch layer-list
      fi
      # Unpack all of the parent layers into the image.
      lowerdir=""
      extractionID=0
      for layerTar in $(cat layer-list); do
        echo "Unpacking layer $layerTar"
        extractionID=$((extractionID + 1))
        mkdir -p image/$extractionID/layer
        tar -C image/$extractionID/layer -xpf image/$layerTar
        rm image/$layerTar
        find image/$extractionID/layer -name ".wh.*" -exec bash -c 'name="$(basename {}|sed "s/^.wh.//")"; mknod "$(dirname {})/$name" c 0 0; rm {}' \;
        # Get the next lower directory and continue the loop.
        lowerdir=$lowerdir''${lowerdir:+:}image/$extractionID/layer
      done
      mkdir work
      mkdir layer
      mkdir mnt
      ${lib.optionalString (preMount != "") ''
        # Execute pre-mount steps
        echo "Executing pre-mount steps..."
        ${preMount}
      ''}
      if [ -n "$lowerdir" ]; then
        mount -t overlay overlay -olowerdir=$lowerdir,workdir=work,upperdir=layer mnt
      else
        mount --bind layer mnt
      fi
      ${lib.optionalString (postMount != "") ''
        # Execute post-mount steps
        echo "Executing post-mount steps..."
        ${postMount}
      ''}
      umount mnt
      (
        cd layer
        cmd='name="$(basename {})"; touch "$(dirname {})/.wh.$name"; rm "{}"'
        find . -type c -exec bash -c "$cmd" \;
      )
      ${postUmount}
    '');

  unmsServerSrc = runWithOverlay {
    name = "unms-app-${version}-src";
    fromImage = unmsImage;
    postMount = ''
      mkdir -p $out
      shopt -s extglob
      cp -rL mnt/home/app/unms/!(node_modules) $out
      cat $out/package.json \
        | jq --argjson ws '{ "workspaces": [ "packages/*" ] }' '. + $ws' \
        | jq --argjson bin '{ "bin": { "unms": "index.js" } }' '. + $bin' \
        | jq '.dependencies = (.dependencies | to_entries | [.[] | select(.value | startswith("file:") | not)] | from_entries)' \
        | tee $out/package-ws.json
      sed '/file:\.\/packages\/.*/d' mnt/home/app/unms/package.json > $out/package.json
    '';
  };

  unms-server = yarn2nix.mkYarnPackage rec {
    name = "unms-server-${version}";
    src = unmsServerSrc;
    packageJSON = "${unmsServerSrc}/package-ws.json";
    yarnFlags = yarn2nix.defaultYarnFlags ++ [ "--production" ];
    workspaceDependencies = lib.attrValues (yarn2nix.mkYarnWorkspace {
      name = "unms-server-ws-deps-${version}";
      src = unmsServerSrc;
      packageJSON = "${unmsServerSrc}/package-ws.json";
      yarnFlags = yarn2nix.defaultYarnFlags ++ [ "--production" ];
    });
  };

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

in unms-server
