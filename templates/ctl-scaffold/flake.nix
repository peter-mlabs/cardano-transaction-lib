{
  description = "ctl-scaffold";

  inputs = {
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    ctl = {
      type = "github";
      owner = "Plutonomicon";
      repo = "cardano-transaction-lib";
      rev = "dd79ed2cabed08d8f82925c2cfddb288f7228f6d";
    };
    nixpkgs.follows = "ctl/nixpkgs";
  };

  outputs = { self, nixpkgs, ctl, ... }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      perSystem = nixpkgs.lib.genAttrs supportedSystems;
      nixpkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [
          ctl.overlays.purescript
          ctl.overlays.runtime
        ];
      };
      psProjectFor = system:
        let
          projectName = "ctl-scaffold";
          pkgs = nixpkgsFor system;
          packageJson = ./package.json;
          packageLock = ./package-lock.json;
          src = builtins.path {
            path = ./.;
            name = "${projectName}-src";
            # Adjust the `filter` as necessary
            filter = path: ftype: !(pkgs.lib.hasSuffix ".md" path);
          };
          shell = {
            packageLockOnly = true;
            packages = with pkgs; [
              nodePackages.eslint
              nodePackages.prettier
            ];
          };
        in
        pkgs.purescriptProject {
          inherit pkgs src projectName;
        };
    in
    {
      packages = perSystem (system: {
        default = self.packages.${system}.ctl-scaffold-bundle-web;
        ctl-scaffold-bundle-web = (psProjectFor system).bundlePursProject {
          main = "Scaffold.Main";
          entrypoint = "index.js";
        };
        ctl-scaffold-runtime = (nixpkgsFor system).buildCtlRuntime { };
      });

      apps = perSystem (system: {
        default = self.apps.${system}.ctl-scaffold-runtime;
        ctl-scaffold-runtime = (nixpkgsFor system).launchCtlRuntime { };
        docs = (psProjectFor system).launchSearchablePursDocs { };
      });

      checks = perSystem (system:
        let
          pkgs = nixpkgsFor system;
        in
        {
          ctl-scaffold-plutip-test = (psProjectFor system).runPlutipTest {
            testMain = "Scaffold.Test.Main";
          };

          formatting-check = pkgs.runCommand "formatting-check"
            {
              nativeBuildInputs = with pkgs; [
                fd
                easy-ps.purs-tidy
                nixpkgs-fmt
                nodePackages.prettier
              ];
            }
            ''
              cd ${self}
              purs-tidy check $(fd -epurs)
              nixpkgs-fmt --check $(fd -enix --exclude='spago*')
              prettier -c $(fd -ejs)
              touch $out
            '';

          js-lint-check = pkgs.runCommand "js-lint-check"
            {
              nativeBuildInputs = [ pkgs.nodePackages.eslint pkgs.fd ];
            }
            ''
              cd ${self}
              eslint $(fd -ejs)
              touch $out
            '';
        });

      devShells = perSystem (system: {
        default = (psProjectFor system).devShell;
      });
    };
}
