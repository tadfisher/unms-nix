{ stdenv, stdenvNoCC, fetchurl, dockerTools, nodejs, nodePackages, python, yarn, yarn2nix, writeTextFile, pkgconfig, vips }:

let
  # nix run nixpkgs.skopeo -c skopeo --override-os linux --override-arch x86_64 inspect docker://docker.io/ubnt/unms:1.0.0-dev.15 | jq -r '.Digest'
  version = "0.13.3";
  tag = "0.13.3";

  unmsImage = dockerTools.pullImage {
    imageName = "ubnt/unms";
    imageDigest = "sha256:37b6362f2a7b8d0b9907098211a8d9344d4a698fc651cf641c048a638882cb74";
    sha256 = "1kh5zsll57115v2605dz06sx28bdkp16yrhww1f4wxffzq2qcph3";
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

  nodeHeaders = fetchurl {
    url = "https://nodejs.org/download/release/v${nodejs.version}/node-v${nodejs.version}-headers.tar.gz";
    sha256 = "0bjnkf6xmpzwzd02x8y56165flnigriazi455azvydi80xlyx5wy";
  };

  unms-server = yarn2nix.mkYarnPackage rec {
    src = unmsServerSrc;
    packageJSON = ./package.json;
    yarnLock = ./yarn.lock;
    yarnFlags = yarn2nix.defaultYarnFlags ++ [ "--production" ];

    pkgConfig = {
      bcrypt = {
        buildInputs = [ python nodePackages.node-gyp nodePackages.node-pre-gyp ];
        postInstall = ''
          node-pre-gyp configure build --build-from-source --tarball="${nodeHeaders}"
        '';
      };

      dtrace-provider = {
        buildInputs = [ python nodePackages.node-gyp ];
        postInstall = ''
          node-gyp rebuild --tarball="${nodeHeaders}"
        '';
      };

      heapdump = {
        buildInputs = [ python nodePackages.node-gyp ];
        postInstall = ''
          node-gyp rebuild --tarball="${nodeHeaders}"
        '';
      };

      raw-socket = {
        buildInputs = [ python nodePackages.node-gyp ];
        postInstall = ''
          node-gyp rebuild --tarball="${nodeHeaders}";
        '';
      };

      sharp = {
        buildInputs = [ pkgconfig vips python nodePackages.node-gyp ] ++ vips.buildInputs;
        postInstall = ''
          node-gyp rebuild --tarball="${nodeHeaders}"
          node install/dll-copy
        '';
      };
    };

    postInstall = ''
      ln -s ${startScript} $out/bin/unms
    '';
  };

in {
  inherit unmsServerSrc unms-server;
}
