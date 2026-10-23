{
  description = "Harmony Music stable releases and Linux development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      inherit (pkgs) lib;
      release = lib.importJSON ./nix/release.json;
      python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
      flutter = pkgs.flutter329.override {
        supportedTargetFlutterPlatforms = [
          "universal"
          "linux"
        ];
      };

      stableSource = pkgs.fetchFromGitHub {
        owner = "NPP-exe";
        repo = "Harmony-Music";
        inherit (release) rev hash;
      };

      developmentSource = lib.cleanSourceWith {
        src = ./.;
        filter =
          path: type:
          let
            relative = lib.removePrefix "${toString ./.}/" (toString path);
            paths = [
              "assets"
              "lib"
              "linux"
              "packages/youtube_explode_dart/lib"
              "packages/youtube_explode_dart/pubspec.yaml"
              "pubspec.yaml"
              "pubspec.lock"
              "LICENSE"
              ".metadata"
            ];
          in
          lib.cleanSourceFilter path type
          && !(lib.hasPrefix "linux/flutter/ephemeral" relative)
          && !(lib.hasPrefix "linux/flutter/generated_" relative)
          && lib.any (
            prefix:
            relative == prefix
            || lib.hasPrefix "${prefix}/" relative
            || (type == "directory" && lib.hasPrefix "${relative}/" prefix)
          ) paths;
      };

      mkPackage = args: pkgs.callPackage ./nix/package.nix args;
      stable = mkPackage {
        src = stableSource;
        inherit (release) version;
        lockfile = ./nix/release/pubspec.lock.json;
        gitHashesFile = ./nix/release/git-hashes.json;
      };
      development = mkPackage {
        src = developmentSource;
        version = "unstable";
        lockfile = ./nix/pubspec.lock.json;
        gitHashesFile = ./nix/git-hashes.json;
      };

      updateLockfile = pkgs.writeShellApplication {
        name = "harmony-update-lockfile";
        runtimeInputs = [
          python
          pkgs.nix
          pkgs.nix-prefetch-git
        ];
        text = ''
          exec python ${./nix/update-lockfile.py} "$@"
        '';
      };

      updateRelease = pkgs.writeShellApplication {
        name = "harmony-update-release";
        runtimeInputs = [
          python
          pkgs.nix
          flutter
          updateLockfile
        ];
        text = ''
          exec python ${./nix/update-release.py} "$@"
        '';
      };

      resolveLockfile = pkgs.writeShellApplication {
        name = "harmony-resolve-lockfile";
        runtimeInputs = [
          flutter
          updateLockfile
        ];
        text = ''
          exec harmony-update-lockfile --resolve "$@"
        '';
      };

      configureDevelopment = pkgs.writeShellApplication {
        name = "harmony-configure";
        runtimeInputs = [ python ];
        text = ''
          exec python ${./nix/configure-development.py} ${development.packageConfig} ${./nix/pubspec.lock.json} "$@"
        '';
      };
    in
    {
      packages.${system} = {
        default = stable;
        harmonymusic = stable;
        inherit development;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = lib.getExe stable;
          meta.description = "Run the pinned stable release";
        };
        development = {
          type = "app";
          program = lib.getExe development;
          meta.description = "Run the local checkout";
        };
        update-lockfile = {
          type = "app";
          program = lib.getExe updateLockfile;
          meta.description = "Export the resolved Pub lockfile and Git source hashes";
        };
        update-release = {
          type = "app";
          program = lib.getExe updateRelease;
          meta.description = "Pin a published stable release and resolve its dependencies";
        };
        resolve-lockfile = {
          type = "app";
          program = lib.getExe resolveLockfile;
          meta.description = "Resolve the checkout's Pub dependencies and update the Nix locks";
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        inputsFrom = [ development ];
        packages = [
          flutter
          pkgs.jdk17
          pkgs.cmake
          pkgs.ninja
          pkgs.clang
          pkgs.pkg-config
          pkgs.nixfmt
          python
          updateLockfile
          resolveLockfile
          updateRelease
          configureDevelopment
        ];
        JAVA_HOME = pkgs.jdk17.home;
        LIBMPV_LIBRARY_PATH = "${lib.getLib pkgs.mpv-unwrapped}/lib/libmpv.so";
        shellHook = ''
          if [ -f pubspec.yaml ] && [ -d packages/youtube_explode_dart ]; then
            harmony-configure
          fi
        '';
      };

      checks.${system} = {
        inherit stable development;
        maintenance =
          pkgs.runCommand "harmony-maintenance-tests"
            {
              nativeBuildInputs = [ python ];
            }
            ''
              python ${./nix}/test-maintenance.py
              touch "$out"
            '';
        workflows =
          pkgs.runCommand "harmony-nix-workflows"
            {
              nativeBuildInputs = [
                pkgs.actionlint
                pkgs.shellcheck
              ];
            }
            ''
              actionlint -shellcheck=shellcheck \
                ${./.github/workflows/nix.yml} \
                ${./.github/workflows/nix-maintenance.yml}
              touch "$out"
            '';
        formatting =
          pkgs.runCommand "harmony-nix-formatting"
            {
              nativeBuildInputs = [ pkgs.nixfmt ];
            }
            ''
              nixfmt --check ${./flake.nix} ${./nix/package.nix} ${./nix/audiotags.nix}
              touch "$out"
            '';
        lockfile =
          pkgs.runCommand "harmony-lockfile-check"
            {
              nativeBuildInputs = [ python ];
            }
            ''
              cd ${self}
              python ${./nix/update-lockfile.py} --check
              touch "$out"
            '';
      };

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
