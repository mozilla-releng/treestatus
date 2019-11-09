{ releng_pkgs }:

let
  inherit (releng_pkgs.pkgs) writeScript stdenv makeWrapper;
in {

  pypi2nix = import ./pypi2nix.nix { inherit releng_pkgs; } // {
    update = releng_pkgs.lib.updateFromGitHub {
      owner = "garbas";
      repo = "pypi2nix";
      branch = "master";
      path = "nix/tools/pypi2nix.json";
    };
  };

  awscli = (import ./awscli.nix { inherit (releng_pkgs) pkgs; }).packages."awscli" // {
    update = writeScript "update-tools-awscli" ''
      pushd nix/tools
      ${releng_pkgs.tools.pypi2nix}/bin/pypi2nix --basename "awscli" -V "3.5" -e awscli -v
      popd
    '';
  };

  node2nix = import ./node2nix.nix { inherit releng_pkgs; } // {
    update = releng_pkgs.lib.updateFromGitHub {
      owner = "svanderburg";
      repo = "node2nix";
      branch = "master";
      path = "nix/tools/node2nix.json";
    };
  };

  mysql2pgsql = (import ./mysql2pgsql.nix { inherit (releng_pkgs) pkgs; }).packages."py-mysql2pgsql" // {
    update = writeScript "update-tools-mysql2pgsql" ''
      pushd nix/tools
      ${releng_pkgs.tools.pypi2nix}/bin/pypi2nix --basename "mysql2pgsql" -V "2.7" -e py-mysql2pgsql -E "postgresql mysql.connector-c" -v
      popd
    '';
  };

  mercurial = import ./mercurial.nix { inherit releng_pkgs; };

}
