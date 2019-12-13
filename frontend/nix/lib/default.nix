{ releng_pkgs }:

let

  inherit (releng_pkgs.pkgs)
    busybox
    cacert
    coreutils
    curl
    dockerTools
    glibcLocales
    gnugrep
    gnused
    jq
    makeWrapper
    nix
    stdenv
    writeScript
    writeText;

  inherit (releng_pkgs.pkgs.lib)
    fileContents
    flatten
    inNixShell
    optional
    optionalAttrs
    optionals
    removeSuffix
    replaceStrings
    splitString
    unique;

  inherit (releng_pkgs.tools)
    pypi2nix
    node2nix;

  pkgs_for_elm =
    let
      nixpkgs-json = builtins.fromJSON (builtins.readFile ./nixpkgs_for_elm.json);
      src-nixpkgs = releng_pkgs.pkgs.fetchFromGitHub { inherit (nixpkgs-json) owner repo rev sha256; };
    in
      import src-nixpkgs {
        overlays = [
          (import ./../overlay/default.nix)
        ];
      };

  elm2nix = import ./elm2nix.nix { pkgs = pkgs_for_elm; };

  inherit (pkgs_for_elm) elmPackages;

  ignoreRequirementsLines = specs:
    builtins.filter
      (x: x != "" &&                         # ignore all empty lines
          builtins.substring 0 1 x != "-" && # ignore all -r/-e
          builtins.substring 0 1 x != "#"    # ignore all comments
      )
      specs;

  cleanRequirementsSpecification = specs:
    let
      separators = [ "==" "<=" ">=" ">" "<" ];
      removeVersion = spec:
        let
          possible_specs =
            unique
              (builtins.filter
                (x: x != null)
                (map
                  (separator:
                    let
                      spec' = splitString separator spec;
                    in
                      if builtins.length spec' != 1
                      then builtins.head spec'
                      else null
                  )
                  separators
                )
              );
        in
          if builtins.length possible_specs == 1
          then builtins.head possible_specs
          else spec;
    in
      map removeVersion specs;

  migrate = import ./migrate.nix { inherit releng_pkgs; };

in rec {

  inherit (migrate) mysql2postgresql;

  packagesWith = attrName: pkgs':
    builtins.filter
      ({ name, pkg }:
          let
            pkg = builtins.getAttr name pkgs';
        in
            builtins.hasAttr "name" pkg && builtins.hasAttr attrName pkg
      )
      (builtins.map
        (name: { inherit name; pkg = builtins.getAttr name pkgs'; })
        (builtins.attrNames pkgs')
      );

  mkDocker =
    { name
    , version
    , fromImage ? null
    , config ? {}
    , contents ? []
    , runAsRoot ? null
    , diskSize ? 2048
    }:
    dockerTools.buildImage {
      name = name;
      tag = version;
      inherit contents config runAsRoot diskSize fromImage;
    };

  mkDockerflow =
    { name
    , version
    , fromImage
    , User ? "app"
    , UserId ? 10001
    , Group ? "app"
    , GroupId ? 10001
    , Cmd ? []
    , src
    , githubCommit ? builtins.getEnv "GITHUB_COMMIT"
    , taskId ? builtins.getEnv "TASK_ID"
    , taskGroupId ? builtins.getEnv "TASK_GROUP_ID"
    , defaultConfig ? {}
    }:
    let
      version_json = {
        inherit  version;
        source = "https://github.com/mozilla-releng/treestatus";
        commit = githubCommit;
        build =
          if taskGroupId != "" && taskId != ""
            then "https://tools.taskcluster.net/groups/${taskGroupId}/tasks/${taskId}"
            else "unknown";
      };
    in mkDocker {
      inherit name version fromImage;
      config = defaultConfig // {
        inherit User Cmd;
      };
      runAsRoot = (if User == null then "" else ''
        #!${stdenv.shell}
        ${dockerTools.shadowSetup}
        groupadd --gid ${toString GroupId} ${Group}
        useradd --gid ${Group} --uid ${toString UserId} --home-dir /app ${User}
        # gunicorn requires /tmp, /var/tmp, or /usr/tmp
        mkdir -p --mode=1777 /tmp
        mkdir -p /app
        cp -a ${src}/. /app/
      '') + ''
        cp -a ${src}/* /app
        cat > /app/version.json  <<EOF
        ${builtins.toJSON version_json}
        EOF
        echo "/app/version.json content:"
        cat /app/version.json
      '';
    };

  mkTaskclusterMergeEnv =
    { env
    }:
    {
      "$merge" = [
        env
        {
          "$if" = "firedBy == 'triggerHook'";
          "then" = { "$eval" = "payload"; };
          "else" = {};
        }
      ];
    };

  mkTaskclusterTaskMetadata =
    { name
    , description ? ""
    , owner
    , source ? "https://github.com/mozilla-releng/treestatus"
    }:
    { inherit name description owner source; };

  mkTaskclusterTaskPayload =
    { image
    , command
    , maxRunTime ? 3600
    , features ? { taskclusterProxy = true; }
    , capabilities ? { privileged = true; }
    , artifacts ? {}
    , env ? {}
    , cache ? {}
    }:
    { inherit env image features capabilities maxRunTime command artifacts cache; };

  mkTaskclusterTask =
    { extra ? {}
    , created ? "0 seconds"
    , expires ? "1 month"
    , deadline ? "1 hour"
    , metadata ? {}
    , payload ? {}
    , priority ? "normal"
    , provisionerId ? "aws-provisioner-v1"
    , retries ? 5
    , routes ? []
    , schedulerId ? "-"
    , scopes ? []
    , tags ? {}
    , workerType ? "releng-svc"
    }:
    { inherit extra priority provisionerId retries routes schedulerId scopes
         tags workerType;
      payload = mkTaskclusterTaskPayload payload;
      metadata = mkTaskclusterTaskMetadata metadata;
      created = { "$fromNow" = created; };
      deadline = { "$fromNow" = deadline; };
      expires = { "$fromNow" = expires; };
    };

  mkTaskclusterHook =
    { name
    , description ? ""
    , owner
    , emailOnError ? true
    , schedule ? []
    , created ? "0 seconds"
    , expires ? "1 month"
    , deadline ? "1 hour"
    , taskExtra ? {}
    , taskImage
    , taskCommand
    , taskArtifacts ? {}
    , taskEnv ? {}
    , taskCapabilities ? { privileged = true; }
    , taskRoutes ? []
    , scopes ? []
    , cache ? {}
    , bindings ? []
    , maxRunTime ? 3600
    , workerType ? "releng-svc"
    }:
    { inherit schedule bindings;
      metadata = { inherit name description owner emailOnError; };
      task = mkTaskclusterTask ({
        created = created;
        deadline = deadline;
        expires = expires;
        metadata = { inherit name description owner; };
        payload = mkTaskclusterTaskPayload {
          image = taskImage;
          command = taskCommand;
          maxRunTime = maxRunTime;
          artifacts = taskArtifacts;
          env = taskEnv;
          cache = cache;
          capabilities = taskCapabilities;
        };
        routes = taskRoutes;
        scopes = scopes;
        workerType = workerType;
        extra = taskExtra;
      });
      triggerSchema = {
        type = "object";
        additionalProperties = true;
      };
    };

  fromRequirementsFile = file: custom_pkgs:
    let
      removeLines =
        builtins.filter
          (line: ! startsWith line "-r" && line != "" && ! startsWith line "#");

      removeAfter =
        delim: line:
          let
            split = splitString delim line;
          in
            if builtins.length split > 1
              then builtins.head split
              else line;

      removeSpaces =
        builtins.map (builtins.replaceStrings [" "]  [""]);

      removeExtras =
        builtins.map (removeAfter "[");

      removeComment =
        builtins.map (removeAfter "#");

      removeSpecs =
        builtins.map
          (line:
            (removeAfter "<" (
              (removeAfter ">" (
                (removeAfter ">=" (
                  (removeAfter "<=" (
                    (removeAfter "==" line))
                  ))
                ))
              ))
            ));

      extractEggName =
        map
          (line:
            let
              split = splitString "egg=" line;
            in
              if builtins.length split == 2
                then builtins.elemAt split 1
                else line
          );

      readLines = file_:
        (splitString "\n"
          (removeSuffix "\n"
            (builtins.readFile file_)
          )
        );
    in
      map
        (pkg_name: builtins.getAttr pkg_name custom_pkgs)
        (removeSpaces
          (removeComment
            (removeExtras
              (removeSpecs
                (removeLines
                  (extractEggName
                    (readLines file)))))));




  makeElmStuff = deps:
    let
        inherit (releng_pkgs.pkgs) lib fetchurl;
        json = builtins.toJSON (lib.mapAttrs (name: info: info.version) deps);
        cmds = lib.mapAttrsToList (name: info: let
                 pkg = stdenv.mkDerivation {

                   name = lib.replaceChars ["/"] ["-"] name + "-${info.version}";

                   src = fetchurl {
                     url = "https://github.com/${name}/archive/${info.version}.tar.gz";
                     meta.homepage = "https://github.com/${name}/";
                     inherit (info) sha256;
                   };

                   phases = [ "unpackPhase" "installPhase" ];

                   installPhase = ''
                     mkdir -p $out
                     cp -r * $out
                   '';

                 };
               in ''
                 mkdir -p elm-stuff/packages/${name}
                 ln -s ${pkg} elm-stuff/packages/${name}/${info.version}
               '') deps;
    in ''
      home_old=$HOME
      HOME=/tmp
      mkdir elm-stuff
      cat > elm-stuff/exact-dependencies.json <<EOF
      ${json}
      EOF
    '' + lib.concatStrings cmds + ''
      HOME=$home_old
    '';

  startsWith = s: x:
    builtins.substring 0 (builtins.stringLength x) s == x;

  filterSource = src:
    { name ? null
    , include ? [ "/" ]
    , exclude ? []
    }:
      assert name == null -> include != null;
      assert name == null -> exclude != null;
      let
        _include= if include == null then [
          "/VERSION"
          "/${name}"
          "/tests"
          "/MANIFEST.in"
          "/settings.py"
          "/setup.py"
        ] else include;
        _exclude = if exclude == null then [
          "/${name}.egg-info"
          "/build"
          "/cache"
        ] else exclude;
        relativePath = path:
          builtins.substring (builtins.stringLength (builtins.toString src))
                             (builtins.stringLength path)
                             path;
      in
        builtins.filterSource (path: type:
          if builtins.any (x: x) (builtins.map (startsWith (relativePath path)) _exclude) then false
          else if builtins.any (x: x) (builtins.map (startsWith (relativePath path)) _include) then true
          else false
        ) src;

  mkYarnFrontend =
    { project_name
    , version
    , src
    , csp ? "default-src 'none'; img-src 'self' data:; script-src 'self'; style-src 'self'; font-src 'self';"
    , extraBuildInputs ? []
    , patchPhase ? ""
    , postInstall ? ""
    , shellHook ? ""
    , inTesting ? true
    , inStaging ? true
    , inProduction ? false
    }:
    let

      module_name = mkProjectModuleName project_name;

      self = mkProject {
        # yarn2nix knows how to extract the name/version from package.json
        inherit src project_name version;

        mkDerivation = releng_pkgs.pkgs.yarn2nix.mkYarnPackage;

        doCheck = true;

        extraBuildInputs = extraBuildInputs;

        preConfigure = ''
          export HOME=$TMPDIR/${module_name}-$RANDOM
          mkdir $HOME
        '';

        checkPhase = ''
          yarn lint
          yarn test
        '';

        postInstall = ''
          export PATH=$PWD/node_modules/.bin:$PATH
          export NODE_PATH=$PWD/node_modules:$NODE_PATH
          ${releng_pkgs.pkgs.yarn}/bin/yarn build
          rm -rf $out
          mkdir -p $out
          cp -r build/. $out/
          if [ -e $out/index.html ]; then
            sed -i -e "s|<head>|<head>\n  <meta http-equiv=\"Content-Security-Policy\" content=\"${csp}\">|" $out/index.html
          fi
        '' + postInstall;


        shellHook = ''
          cd ${self.src_path}
          rm -rf node_modules
          ln -s ${self.node_modules} ./node_modules
          export PATH=$PWD/node_modules/.bin:$PATH
          export NODE_PATH=$PWD/node_modules:$NODE_PATH
        '' + shellHook;

        passthru = {
          inherit (self) src_path;

          deploy = {
            testing = self;
            staging = self;
            production = self;
          };

          update = writeScript "update-${self.package.name}" ''
            set -e
            export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
            pushd "$SERVICES_ROOT"${self.src_path} >> /dev/null
            rm -rf ./node_modules
            ${releng_pkgs.pkgs.yarn}/bin/yarn install
            ${releng_pkgs.pkgs.yarn}/bin/yarn upgrade
            popd
          '';
        };
      };
    in self;

  mkProjectModuleName = builtins.replaceStrings ["/" "_"] ["-" "-"];
  mkProjectDirName = builtins.replaceStrings ["/" ] ["_"];
  mkProjectSrcPath = project_name: "src/" + project_name;
  mkProjectFullName = project_name: version: "mozilla-${mkProjectModuleName project_name}-${version}";
  withDefault = item: default: if item != null then item else default;

  mkProject =
    args @
    { project_name
    , version
    , name ? null
    , dirname ? null
    , module_name ? null
    , src_path ? null
    , shellHook ? ""
    , mkDerivation ? stdenv.mkDerivation
    , passthru ? {}
    , ...
    }:
    let
      argsToSkip = [
        "project_name"
        "version"
        "name"
        "dirname"
        "module_name"
        "src_path"
        "mkDerivation"
      ];
      args' = releng_pkgs.pkgs.lib.filterAttrs (n: v: ! builtins.elem n argsToSkip) args;
      self = mkDerivation (args' // {
        name = withDefault name (mkProjectFullName project_name version);
        shellHook = shellHook + ''
          PS1="\n\[\033[1;32m\][${self.project_name}:\w]\$\[\033[0m\] "
        '';
        passthru = passthru // {
          inherit version project_name;
          dirname = withDefault dirname (mkProjectDirName project_name);
          module_name = withDefault module_name (mkProjectModuleName project_name);
          src_path = withDefault src_path (mkProjectSrcPath project_name);
          updateHook =
            builtins.listToAttrs (builtins.map
              (channel:
                 let
                   branch = if channel == "production"
                            then "update-${self.module_name}"
                            else "update-${channel}-${self.module_name}";
                   hook_name = "${self.module_name}-update-${channel}";
                   version = fileContents ./../../VERSION;
                   github_commit = builtins.getEnv "GITHUB_COMMIT";
                   hook = schedule:
                     mkTaskclusterHook
                       { name = hook_name;
                         description = "Autogenerated by release-services project.";
                         owner = "rgarbas@mozilla.com";  # TODO: we need to configure this owner
                         deadline = "2 hours";
                         maxRunTime = 4 * 60 * 60;  # 4 hours
                         inherit schedule;
                         scopes =
                           [ "secrets:get:repo:github.com/mozilla-releng/services:branch:${channel}"
                             "queue:create-task:aws-provisioner-v1/releng-svc"
                             "docker-worker:capability:privileged"
                             "queue:route:notify.irc-channel.#release-services"
                           ];
                         taskRoutes =
                           [ "notify.irc-channel.#release-services.on-failed"
                             "notify.irc-channel.#release-services.on-exception"
                           ];
                         taskExtra = {
                           notify = {
                             ircChannelMessage = "Update hook for project ${project_name} on ${channel} channel FAILED.";
                           };
                         };
                         taskImage = "mozillareleng/services:base-${version}";
                         taskCapabilities = { privileged = true; };
                         taskCommand = [
                           "/bin/bash"
                           "-c"
                           (builtins.concatStringsSep " && " [
                             "source /etc/nix/profile.sh"
                             "nix-env -f /etc/nix/nixpkgs -iA git"
                             "mkdir -p /tmp/app"
                             "cd /tmp/app"
                             "wget --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 5 https://github.com/mozilla/release-services/archive/${github_commit}.tar.gz"
                             "tar zxf ${github_commit}.tar.gz"
                             "cd release-services-${github_commit}"
                             "./please -vv tools update-dependencies ${project_name} --branch-to-push=${branch} --taskcluster-secret='repo:github.com/mozilla-releng/services:branch:${channel}' --no-interactive"
                           ])
                         ];
                         workerType = "releng-svc";
                       };
                  mkHook = schedule: writeText "taskcluster-hook-${hook_name}.json" (builtins.toJSON (hook schedule));
                in { name = channel;
                     value = { scheduled = mkHook [ "0 0 * * *" ];
                               notScheduled = mkHook [];
                             };
                   })
              [ "testing"
                "staging"
                "production"
              ]);

        };
      });
    in self;

  mkFrontend =
    { project_name
    , version
    , src
    , src_path ? null
    , nodejs
    , node_modules
    , elm_packages
    , patchPhase ? ""
    , postInstall ? ""
    , shellHook ? ""
    , inTesting ? true
    , inStaging ? true
    , inProduction ? false
    }:
    let
      scss_common = ./../frontend_common/scss;
      frontend_common = ./../frontend_common;
      self = mkProject {
        inherit project_name version src_path;

        src = builtins.filterSource
          (path: type: baseNameOf path != "elm-stuff"
                    && baseNameOf path != "node_modules"
                    )
          src;

        buildInputs = [ nodejs elmPackages.elm ] ++ (builtins.attrValues node_modules);

        patchPhase = ''
          if [ -e src/scss ]; then
            rm \
              src/scss/fira \
              src/scss/font-awesome \
              src/scss/fonts.scss
            ln -s ${scss_common}/fira         ./src/scss/
            ln -s ${scss_common}/font-awesome ./src/scss/
            ln -s ${scss_common}/fonts.scss   ./src/scss/
          fi

          for item in ./*; do
            if [ -h $item ]; then
              rm -f $item
              cp ${frontend_common}/`basename $item` ./
            fi
          done

          if [ -d src ]; then
            for item in ./src/*; do
              if [ -h $item ]; then
                rm -f $item
                cp ${frontend_common}/`basename $item` ./src/
              fi
            done
          fi
        '' + patchPhase;

        configurePhase = ''
          rm -rf node_modules
          rm -rf elm-stuff
        '' + (makeElmStuff elm_packages) + ''
          mkdir node_modules
          for item in ${builtins.concatStringsSep " " (builtins.attrValues node_modules)}; do
            ln -s $item/lib/node_modules/* ./node_modules
          done
          export NODE_PATH=$PWD/node_modules:$NODE_PATH
        '';

        buildPhase = ''
          webpack
        '';

        doCheck = true;

        checkPhase = ''
          if [ -d src/ ]; then
            echo "----------------------------------------------------------"
            echo "---  Running ... elm-format-0.18 src/ --validate  --------"
            echo "----------------------------------------------------------"
            elm-format-0.18 src/ --validate
          fi
          if [ -e Main.elm ]; then
            echo "----------------------------------------------------------"
            echo "---  Running ... elm-format-0.18 ./*.elm --validate  -----"
            echo "----------------------------------------------------------"
            elm-format-0.18 ./*.elm --validate
          fi
          echo "Everything OK!"
          echo "----------------------------------------------------------"
        '';

        installPhase = ''
          mkdir $out
          cp build/* $out/ -R
          runHook postInstall
        '';

        inherit postInstall;

        shellHook = ''
          cd ${self.src_path}
        '' + self.configurePhase + shellHook;

        passthru = {

          deploy = {
            testing = self;
            staging = self;
            production = self;
          };

          update = writeScript "update-${self.name}" ''
            export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
            pushd "$SERVICES_ROOT"${self.src_path} >> /dev/null

            ${node2nix}/bin/node2nix \
              --composition node-modules.nix \
              --input node-modules.json \
              --output node-modules-generated.nix \
              --node-env node-env.nix \
              --flatten \
              --pkg-name nodejs-6_x

            # TODO: move this into default.nix
            ${gnused}/bin/sed -i -e "s| sources.\"elm-0.18| #sources.\"elm-0.18|" node-modules-generated.nix
            ${gnused}/bin/sed -i -e "s| name = \"elm-webpack-loader\";| dontNpmInstall = true;name = \"elm-webpack-loader\";|" node-modules-generated.nix

            rm -rf elm-stuff
            n=0
            until [ $n -ge 5 ]
            do
              ${elmPackages.elm}/bin/elm-package install -y
              n=$[$n+1]
              sleep 5
            done
            ${elm2nix}/bin/elm2nix elm-packages.nix

            popd
          '';
        };
      };
    in self;

  mkBackend =
    args @
    { buildInputs ? []
    , python
    , postInstall ? ""
    , checkPhase ? null
    , shellHook ? ""
    , dockerContents ? []
    , gunicornWorkers ? 3
    , dockerCmd ? null
    , passthru_config ? {}
    , ...
    }:
    let
      self = mkPython (args // {

        buildInputs = [ releng_pkgs.postgresql.package ] ++ buildInputs;

        postInstall = ''
          mkdir -p $out/bin
          ln -s ${python.packages."Flask"}/bin/flask $out/bin
          ln -s ${python.packages."gunicorn"}/bin/gunicorn $out/bin
          for i in $out/bin/*; do
            wrapProgram $i --set PYTHONPATH $PYTHONPATH
          done
          if [ -e ./settings.py ]; then
            mkdir -p $out/etc
            cp ./settings.py $out/etc
          fi
          if [ -d ./migrations ]; then
            mv ./migrations $out/${python.__old.python.sitePackages}
          fi
        '' + postInstall;

        checkPhase = withDefault checkPhase ''
          export LANG=en_US.UTF-8
          export LOCALE_ARCHIVE=${glibcLocales}/lib/locale/locale-archive
          export APP_TESTING=${self.name}

          echo "################################################################"
          echo "## openapi spec ################################################"
          echo "################################################################"
          python -m openapi_spec_validator ${self.dirname}/api.yml --schema 2.0
          echo "################################################################"

          echo "################################################################"
          echo "## flake8 ######################################################"
          echo "################################################################"
          flake8 -v --mypy-config=setup.cfg setup.py tests/ ${self.dirname}/
          echo "################################################################"

          echo "################################################################"
          echo "## pytest ######################################################"
          echo "################################################################"
          pytest tests/ -vvv
          echo "################################################################"
        '';

        shellHook = ''
          export CACHE_DEFAULT_TIMEOUT=3600
          export CACHE_TYPE=filesystem
          export CACHE_DIR=$PWD/cache
          export LANG=en_US.UTF-8
          export DEBUG=1
          export APP_TESTING=${self.name}
          export FLASK_APP=${self.dirname}.flask:app
        '' + shellHook;

        inherit dockerContents;

        dockerEnv = [
          "APP_SETTINGS=${self}/etc/settings.py"
          "FLASK_APP=${self.dirname}.flask:app"
          "WEB_CONCURRENCY=${builtins.toString gunicornWorkers}"
        ];

        dockerCmd = withDefault dockerCmd [ "gunicorn"
                                            "${self.dirname}.flask:app"
                                            "--log-file"
                                            "-"
                                          ];

        passthru_config = { inherit buildInputs
                                    python
                                    postInstall
                                    checkPhase
                                    shellHook
                                    dockerContents
                                    gunicornWorkers
                                    dockerCmd;
                          } // passthru_config;
      });
    in self;

  mkPython =
    args @
    { version
    , python
    , src
    , buildInputs ? []
    , propagatedBuildInputs ? []
    , prePatch ? ""
    , postPatch ? ""
    , doCheck ? true
    , checkPhase ? null
    , postInstall ? ""
    , shellHook ? ""
    , inTesting ? true
    , inStaging ? true
    , inProduction ? false
    , dockerContents ? []
    , dockerEnv ? []
    , dockerCmd ? []
    , dockerUser ? "app"
    , dockerUserId ? 10001
    , dockerGroup ? "app"
    , dockerGroupId ? 10001
    , passthru ? {}
    , passthru_config ? {}
    , ...
    }:
    let

      argsToSkip = [
        "python"
        "prePatch"
        "postPatch"
        "inTesting"
        "inStaging"
        "inProduction"
        "dockerContents"
        "dockerEnv"
        "dockerCmd"
        "dockerUser"
        "dockerUserId"
        "dockerGroup"
        "dockerGroupId"
        "passthru_config"
      ];
      args' = releng_pkgs.pkgs.lib.filterAttrs (n: v: ! builtins.elem n argsToSkip) args;
      self = mkProject (args' // {
        mkDerivation = python.mkDerivation;

        namePrefix = "";

        inherit src;

        checkInputs =
          [ makeWrapper
            glibcLocales
          ] ++ buildInputs ++ propagatedBuildInputs;

        buildInputs =
          [ makeWrapper
            glibcLocales
          ] ++ buildInputs ++ propagatedBuildInputs;

        nativeBuildInputs =
          [ makeWrapper
            glibcLocales
          ] ++ buildInputs ++ propagatedBuildInputs;

        propagatedBuildInputs =
          [ releng_pkgs.pkgs.cacert
          ] ++ propagatedBuildInputs;

        nativePropagatedBuildInputs =
          [ releng_pkgs.pkgs.cacert
          ] ++ propagatedBuildInputs;

        preConfigure = ''
          rm -rf build *.egg-info
        '';

        patchPhase = prePatch + ''
          # replace synlink with real file
          rm -f setup.cfg
          ln -s ${../setup.cfg} setup.cfg

          # generate MANIFEST.in to make sure every file is included
          rm -f MANIFEST.in
          cat > MANIFEST.in <<EOF
          recursive-include ${self.dirname}/*

          include VERSION
          include ${self.dirname}/VERSION
          include ${self.dirname}/*.ini
          include ${self.dirname}/*.json
          include ${self.dirname}/*.mako
          include ${self.dirname}/*.yml
          include ${self.dirname}/*.download

          recursive-exclude * __pycache__
          recursive-exclude * *.py[co]
          EOF
        '' + postPatch;

        inherit doCheck;

        checkPhase = withDefault checkPhase ''
          export LANG=en_US.UTF-8
          export LOCALE_ARCHIVE=${glibcLocales}/lib/locale/locale-archive

          echo "################################################################"
          echo "## flake8 ######################################################"
          echo "################################################################"
          flake8 -v --mypy-config=setup.cfg setup.py tests/ ${self.dirname}/
          echo "################################################################"

          echo "################################################################"
          echo "## pytest ######################################################"
          echo "################################################################"
          pytest tests/ -vvv -s
          echo "################################################################"
        '';

        postInstall = ''
          mkdir -p $out/bin
          ln -s ${python.__old.python.interpreter} $out/bin
          ln -s ${python.__old.python.interpreter} $out/bin/python
          for i in $out/bin/*; do
            wrapProgram $i \
              --set PYTHONPATH $PYTHONPATH \
              --set LANG "en_US.UTF-8" \
              --set LOCALE_ARCHIVE "${glibcLocales}/lib/locale/locale-archive"
          done
          find $out -type d -name "__pycache__" -exec 'rm -r "{}"' \;
          find $out -type d -name "*.py" -exec '${python.__old.python.executable} -m compileall -f "{}"' \;

          mkdir -p $out/etc
          echo "${self.name}-${self.version}" > $out/etc/mozilla-releng-services
        '' + postInstall;

        shellHook = ''
          export APP_SETTINGS="$PWD/${self.src_path}/settings.py"
          export SECRET_KEY_BASE64=`dd if=/dev/urandom bs=24 count=1 | base64`
          export APP_NAME="${self.name}-${self.version}"
          export LANG=en_US.UTF-8
          export LOCALE_ARCHIVE=${glibcLocales}/lib/locale/locale-archive

          pushd "$SERVICES_ROOT"${self.src_path} >> /dev/null
          tmp_path=$(mktemp -d)
          export PATH="$tmp_path/bin:$PATH"
          export PYTHONPATH="$tmp_path/${python.__old.python.sitePackages}:$PYTHONPATH"
          mkdir -p $tmp_path/${python.__old.python.sitePackages}
          ${python.__old.bootstrapped-pip}/bin/pip install -q -e . --prefix $tmp_path
          popd >> /dev/null

          cd ${self.src_path}
        '' + shellHook;

        passthru = {
          inherit python;

          docker = mkDocker {
            inherit version;
            inherit (self) name;
            contents = [ busybox self ] ++ dockerContents;
            config = self.docker_default_config;
          };

          dockerflow = mkDockerflow {
            inherit version src;
            inherit (self) name;
            fromImage = self.docker;
            User = dockerUser;
            UserId = dockerUserId;
            Group = dockerGroup;
            GroupId = dockerGroupId;
            Cmd = dockerCmd;
            defaultConfig = self.docker_default_config;
          };

          docker_default_config =
            { Env = [
                "APP_NAME=${self.name}-${self.version}"
                "PATH=/bin"
                "LANG=en_US.UTF-8"
                "LOCALE_ARCHIVE=${releng_pkgs.pkgs.glibcLocales}/lib/locale/locale-archive"
                "SSL_CERT_FILE=${releng_pkgs.pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              ] ++ dockerEnv;
              Cmd = dockerCmd;
              WorkingDir = "/";
            };

          config = { inherit version
                             python
                             src
                             buildInputs
                             propagatedBuildInputs
                             prePatch
                             postPatch
                             doCheck
                             checkPhase
                             postInstall
                             shellHook
                             inTesting
                             inStaging
                             inProduction
                             dockerContents
                             dockerEnv
                             dockerCmd
                             dockerUser
                             dockerUserId
                             dockerGroup
                             dockerGroupId;
                   } // passthru_config;
        } // passthru;
      });
    in self;

  updateFromGitHub = { owner, repo, path, branch }:
    writeScript "update-from-github-${owner}-${repo}-${branch}" ''
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt

      github_rev() {
        ${curl.bin}/bin/curl -sSf "https://api.github.com/repos/$1/$2/branches/$3" | \
          ${jq}/bin/jq '.commit.sha' | \
          ${gnused}/bin/sed 's/"//g'
      }

      github_sha256() {
        ${nix}/bin/nix-prefetch-url \
           --unpack \
           "https://github.com/$1/$2/archive/$3.tar.gz" 2>&1 | \
               ${coreutils}/bin/tail -1
      }

      echo "=== ${owner}/${repo}@${branch} ==="

      echo "Looking up latest revision ... "
      rev=$(github_rev "${owner}" "${repo}" "${branch}");
      echo R"evision found: \`$rev\`."

      echo "Looking up sha256 ... "
      sha256=$(github_sha256 "${owner}" "${repo}" "$rev");
      echo "sha256 found: \`$sha256\`."

      if [ "$sha256" == "" ]; then
        echo "sha256 is not valid!"
        exit 2
      fi
      source_file=$HOME/${path}
      echo "Content of source file (``$source_file``) written."
      cat <<REPO | ${coreutils}/bin/tee "$source_file"
      {
        "owner": "${owner}",
        "repo": "${repo}",
        "rev": "$rev",
        "sha256": "$sha256"
      }
      REPO
      echo
    '';

  mkRustPlatform = (import ./rust.nix) releng_pkgs.pkgs;

}
