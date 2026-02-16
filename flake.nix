{
  description = "KasmVNC build/install flake (adapted from a-h/KasmVNC)";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Upstream KasmVNC source tree used for actual build inputs.
    kasmvncSrc = {
      url = "github:a-h/KasmVNC";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs, 
    flake-utils,
    kasmvncSrc,
  }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # X.Org server dependencies
        xorgDeps = with pkgs.xorg; [
          xorgproto
          libX11
          libXau
          libXdmcp
          libXext
          libXfixes
          libXfont2
          libXi
          libXrender
          libXrandr
          libXcursor
          libxcb
          libxkbfile
          libxshmfence
          libXtst
          xkbcomp
          xtrans
          fontutil
          makedepend
        ];

        # Build dependencies
        buildDeps = with pkgs; [
          cmake
          ninja
          nasm
          pkg-config
          autoconf
          automake
          libtool
          quilt
          git
          wget
          util-macros
        ];

        # Required libraries
        libraries = with pkgs; [
          gnutls
          libpng
          libtiff
          giflib
          ffmpeg
          openssl
          libva
          zlib
          bzip2
          pixman
          mesa
          libdrm
          libepoxy
          nettle
          libjpeg_turbo
          libwebp
          tbb
          fmt
          libxcrypt
          libxcvt
          mesa-gl-headers
          libgbm
          fontconfig
          freetype
          libfontenc
          dbus
          xkeyboard-config
          docbook_xsl
          docbook_xml_dtd_45
        ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isx86 [ libcpuid ];

        # Development tools
        devTools = with pkgs; [
          gcc14
          gnumake
          which
          file
          patchelf
          perl
          perlPackages.Switch
          openssh
          nodejs
        ];

        perlWithKasmVncDeps = pkgs.perl.withPackages (
          p: [
            p.Switch
            p.ListMoreUtils
            p.TryTiny
            p.DateTime
            p.DateTimeTimeZone
            p.YAMLTiny
            p.HashMergeSimple
          ]
        );

        xorgVersion = "21.1.7";

        xorgServerTarball = pkgs.fetchurl {
          url = "https://www.x.org/archive/individual/xserver/xorg-server-${xorgVersion}.tar.gz";
          sha256 = "1gygpqancbcw9dd3wc168hna6a4n8cj16n3pm52kda3ygks0b40s";
        };

        kasmvncWebLock = "${kasmvncSrc}/package-lock.json";

        # Build web assets (noVNC) as a separate derivation
        kasmvncWeb = pkgs.buildNpmPackage {
          pname = "kasmvnc-www";
          version = "1.3.1";

          src = pkgs.fetchFromGitHub {
            owner = "kasmtech";
            repo = "noVNC";
            rev = "release/1.3.1";
            sha256 = "sha256-lbNPJ1yRUQp/ppsdQQGlo6ceYa2l0tzsDnDrTZZ1zkM=";
          };

          npmDepsHash = "sha256-RWcdYHsENALjGpOl7x1zjpvonW8QGXZ9U880Q8ymfwQ=";
          npmFlags = [
            "--include=dev"
            "--legacy-peer-deps"
            "--ignore-scripts"
          ];
          npmBuild = "npm run build";
          NODE_OPTIONS = "--openssl-legacy-provider";

          postPatch = ''
            cp ${kasmvncWebLock} package-lock.json
          '';

          installPhase = ''
            mkdir -p $out
            cp -r . $out/
            [ -d dist ] && cp -r dist/* $out/
          '';

          meta = with pkgs.lib; {
            description = "KasmVNC web client assets";
            homepage = "https://github.com/kasmtech/noVNC";
            license = licenses.mpl20;
            platforms = platforms.linux;
          };
        };

        kasmvncDerivation = pkgs.stdenv.mkDerivation {
          pname = "kasmvnc";
          version = "1.3.4";

          src = pkgs.lib.cleanSource kasmvncSrc;
          patches = pkgs.lib.optionals (!pkgs.stdenv.hostPlatform.isx86) [
            ./patches/kasmvnc-no-libcpuid-on-nonx86.patch
          ];
          stdenv = pkgs.gcc14Stdenv;

          nativeBuildInputs = buildDeps ++ devTools ++ [ pkgs.makeWrapper ];
          buildInputs = xorgDeps ++ libraries;

          XORG_VER = xorgVersion;
          KASMVNC_BUILD_OS = "nixos";
          KASMVNC_BUILD_OS_CODENAME = "nixos";
          XORG_TARBALL_PATH = xorgServerTarball;
          MESA_DRI_DRIVERS = "${pkgs.mesa}/lib/dri";
          KASMVNC_WEB_DIST = kasmvncWeb;

          dontConfigure = true;

          preBuild = ''
            echo "Copying web assets from ${kasmvncWeb}..."
            mkdir -p kasmweb/dist builder/www
            cp -r --no-preserve=mode,ownership ${kasmvncWeb}/* kasmweb/dist/
            cp -r --no-preserve=mode,ownership ${kasmvncWeb}/* builder/www/
            chmod -R u+rwX kasmweb/dist builder/www

            # Reduce peak disk usage during package creation:
            # use a build-local temp dir and move final tarball instead of copying it.
            substituteInPlace release/maketarball.in \
              --replace 'TMPDIR=`mktemp -d /tmp/$PACKAGE_NAME-build.XXXXXX`' 'TMPDIR=`mktemp -d ./$PACKAGE_NAME-build.XXXXXX`' \
              --replace 'cp $TMPDIR/$PACKAGE_FILE .' 'mv $TMPDIR/$PACKAGE_FILE .'
          '';

          buildPhase = ''
            runHook preBuild
            bash ./build.sh
            runHook postBuild
          '';

          installPhase = ''
            mkdir -p "$out"
            tarball=$(ls -1 kasmvnc-*.tar.gz | head -n1)
            if [ -z "$tarball" ]; then
              echo "No kasmvnc tarball produced" >&2
              exit 1
            fi

            tar -xzf "$tarball" -C "$out"
            if [ -d "$out/usr/local" ]; then
              mv "$out/usr/local"/* "$out"/
              rmdir "$out/usr/local" || true
              rmdir "$out/usr" || true
            fi

            if [ -x "$out/bin/Xvnc" ]; then
              mv "$out/bin/Xvnc" "$out/bin/Xvnc.real"
              makeWrapper "$out/bin/Xvnc.real" "$out/bin/Xvnc" \
                --set XKB_COMP "${pkgs.xorg.xkbcomp}/bin/xkbcomp" \
                --set XKB_CONFIG_ROOT "${pkgs.xkeyboard-config}/share/X11/xkb"
            fi

            if [ -x "$out/bin/vncserver" ]; then
              sed -i '1s|^#!.*perl.*|#!${perlWithKasmVncDeps}/bin/perl|' "$out/bin/vncserver"
              sed -i "s|/usr/share/kasmvnc|$out/share/kasmvnc|g" "$out/bin/vncserver"
              sed -i "s|\\\$vncSystemConfigDir = \"/etc/kasmvnc\";|\\\$vncSystemConfigDir = \"$out/etc/kasmvnc\";|g" "$out/bin/vncserver"

              if [ -f "$out/share/kasmvnc/kasmvnc_defaults.yaml" ]; then
                sed -i "s|/usr/share/kasmvnc/www|$out/share/kasmvnc/www|g" "$out/share/kasmvnc/kasmvnc_defaults.yaml"
              fi

              mv "$out/bin/vncserver" "$out/bin/vncserver.real"
              makeWrapper "$out/bin/vncserver.real" "$out/bin/vncserver" \
                --set PERL5LIB "$out/bin" \
                --prefix PATH : "${pkgs.lib.makeBinPath [
                  pkgs.xorg.xauth
                  pkgs.xorg.xdpyinfo
                  pkgs.xorg.xinit
                  pkgs.nettools
                  pkgs.coreutils
                  pkgs.gnugrep
                ]}"
            fi
          '';

          meta = with pkgs.lib; {
            description = "KasmVNC server and web client";
            homepage = "https://github.com/kasmtech/KasmVNC";
            license = licenses.gpl2Plus;
            platforms = platforms.linux;
          };
        };
      in
      {
        packages.kasmvnc-www = kasmvncWeb;
        packages.kasmvnc = kasmvncDerivation;
        packages.default = kasmvncDerivation;

        devShells.default = pkgs.mkShell {
          stdenv = pkgs.gcc14Stdenv;
          buildInputs = xorgDeps ++ buildDeps ++ libraries ++ devTools;

          shellHook = ''
            echo "KasmVNC development environment"
            echo "================================"
            echo ""
            echo "Build package: nix build .#kasmvnc"
            echo ""

            export XORG_VER="21.1.7"
            export MAKEFLAGS="-j$(nproc)"
            export KASMVNC_BUILD_OS="nixos"
            export KASMVNC_BUILD_OS_CODENAME="nixos"

            export CC="${pkgs.gcc14}/bin/gcc"
            export CXX="${pkgs.gcc14}/bin/g++"

            export PKG_CONFIG_PATH="${pkgs.lib.makeSearchPath "lib/pkgconfig" (libraries ++ xorgDeps)}:$PKG_CONFIG_PATH"
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (libraries ++ xorgDeps)}:$LD_LIBRARY_PATH"
            export LDFLAGS="-L${pkgs.lib.makeLibraryPath (libraries ++ xorgDeps)} $LDFLAGS"
            export CFLAGS="-I${pkgs.lib.makeSearchPath "include" (libraries ++ xorgDeps)} -Wno-format-security $CFLAGS"
            export CXXFLAGS="-I${pkgs.lib.makeSearchPath "include" (libraries ++ xorgDeps)} -Wno-format-security $CXXFLAGS"

            export GIT_SSH="${pkgs.openssh}/bin/ssh"
            export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh"
            export CMAKE_POLICY_DEFAULT_CMP0022=NEW
            export CMAKE_POLICY_DEFAULT_CMP0048=NEW
          '';
        };
      }
    );
}
