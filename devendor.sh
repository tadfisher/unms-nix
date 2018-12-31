#! /usr/bin/env nix-shell
#! nix-shell -i bash -p nix nodePackages_10_x.yarn

set -e

nix build -f default.nix unmsServerSrc
mkdir -p build
cp -RL result/* build/
chmod -R +w build
(
  cd build
  for f in packages/*; do
    pkg=$(basename $f)
    yarn --offline --ignore-engines --ignore-scripts --ignore-platform remove $pkg
    yarn --ignore-engines --ignore-scripts --ignore-platform add $pkg
  done
  cp package.json ..
  cp yarn.lock ..
)

rm -r build
