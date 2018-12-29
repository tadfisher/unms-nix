{ pkgs ? import <nixpkgs> {} }:

with pkgs;

let
  yarn = nodePackages_10_x.yarn;

  yarn2nix = builtins.fetchGit {
    url = https://github.com/moretea/yarn2nix.git;
    name = "yarn2nix";
    rev = "780e33a07fd821e09ab5b05223ddb4ca15ac663f";
  };

in callPackage ./unms-server.nix {
  inherit yarn;

  yarn2nix = callPackage "${yarn2nix}/default.nix" {
    inherit pkgs yarn;
    nodejs = nodejs-10_x;
  };
}
