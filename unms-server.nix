{ stdenv, stdenvNoCC, fetchurl, dockerTools, nodejs, nodePackages, python, yarn, yarn2nix, writeTextFile, pkgconfig, vips }:

let
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
    sha256 = "1hicv4yx93v56ajqk1d7al7k7kvd16206l5zq2y0faf8506hlgch";
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
