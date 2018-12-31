
{ pkgs ? import <nixpkgs> {} }:

with pkgs;

let
  nodejs = nodejs-10_x;

  nodePackages = nodePackages_10_x;

  yarn = nodePackages_10_x.yarn;

  yarn2nix = builtins.fetchGit {
    url = https://github.com/moretea/yarn2nix.git;
    name = "yarn2nix";
    rev = "780e33a07fd821e09ab5b05223ddb4ca15ac663f";
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
