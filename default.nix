{ pkgs ? import <nixpkgs> {} }:

with pkgs;

let
  yarn2nix = builtins.fetchGit {
    url = https://github.com/moretea/yarn2nix.git;
    name = "yarn2nix";
    rev = "780e33a07fd821e09ab5b05223ddb4ca15ac663f";
  };

in callPackage ./unms-server.nix {
  nodejs = nodejs-10_x;
  nodePackages = nodePackages_10_x;

  yarn2nix = callPackage "${yarn2nix}/default.nix" {
    inherit pkgs;
    nodejs = nodejs-10_x;
    yarn = nodePackages_10_x.yarn;
  };
}
