
{ pkgs ? import <nixpkgs> {} }:

with pkgs;

let
  nodejs = nodejs-10_x;

  nodePackages = nodePackages_10_x;

  yarn2nix = builtins.fetchGit {
    url = https://github.com/moretea/yarn2nix.git;
    name = "yarn2nix";
    rev = "3cc020e384ce2a439813adb7a0cc772a034d90bb";
  };

  server = callPackage ./unms-server.nix {
    inherit nodejs nodePackages yarn;

    yarn2nix = callPackage "${yarn2nix}/default.nix" {
      inherit pkgs yarn nodejs;
    };
  };

in {
  inherit (server) unmsServerSrc unms-server;
}
