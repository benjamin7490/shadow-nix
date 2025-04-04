{ stdenv, lib, pkgs, runCommand, yq, jq, fetchurl, makeWrapper, autoPatchelfHook
, wrapGAppsHook, zlib, runtimeShell

, xorg, alsa-lib, libbsd, libopus, openssl, libva, pango, cairo, libuuid, nspr
, nss, cups, expat, atk, at-spi2-atk, gtk3, gdk-pixbuf, libsecret, systemd
, pulseaudio, libGL, dbus, libnghttp2, libidn2, libpsl, libkrb5, openldap
, rtmpdump, libinput, mesa, libpulseaudio, libvdpau, curl

, enableDiagnostics ? false, extraClientParameters ? []
, shadowChannel ? "prod", desktopLauncher ? true }:

with lib;

let
  # Import tools
  utilities = (import ./utilities { inherit lib pkgs; });

  # Latest release information
  info = utilities.shadowApi.getLatestInfo shadowChannel;
in stdenv.mkDerivation rec {
  pname = "shadow-${shadowChannel}";
  version = info.version;
  src = fetchurl (utilities.shadowApi.getDownloadInfo info);
  binaryName = "shadow-launcher";
  channel = shadowChannel;

  # Add all hooks
  nativeBuildInputs = [ autoPatchelfHook wrapGAppsHook makeWrapper appimage-run];

  # Useful libraries to build the package
  buildInputs = [
    stdenv.cc.cc.lib

    xorg.libX11
    xorg.libxcb
    xorg.libXrandr
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXScrnSaver
    xorg.libXcursor
    xorg.libXfixes
    xorg.libXi
    xorg.libXtst
    xorg.xcbutilimage
    xorg.xcbutilrenderutil
    xorg.libxshmfence

    cairo
    pango
    alsa-lib
    libbsd
    libopus
    libinput
    openssl
    libva
    zlib
    libuuid
    nspr
    nss
    cups
    expat
    atk
    at-spi2-atk
    gtk3
    gdk-pixbuf
    libnghttp2
    libidn2
    libpsl
    libkrb5
    openldap
    rtmpdump
    mesa
    libpulseaudio
    libvdpau
    curl
  ];

  # Mandatory libraries for the runtime
  runtimeDependencies = [
    stdenv.cc.cc.lib
    systemd
    libinput
    pulseaudio
    libGL
    dbus
    libsecret
    xorg.libXinerama
    libva
  ];

 unpackPhase = ''
  # Copier l'AppImage dans le répertoire local
  cp $src ./Shadow.AppImage

  # Renommer l'AppImage en .7z
  mv ./Shadow.AppImage ./Shadow.7z

  # Extraire le contenu du fichier .7z
  7z x ./Shadow.7z -o./extracted

  # Nettoyer
  rm ./Shadow.7z
  '';


  # Create the package
  installPhase =
  ''
    mkdir -p $out/opt
    mkdir -p $out/lib

    mv ./squashfs-root/usr/share $out/
    mkdir -p $out/share/applications

    ln -s ${lib.getLib systemd}/lib/libudev.so.1 $out/lib/libudev.so.1
    rm -r ./squashfs-root/usr/lib
    rm ./squashfs-root/AppRun
    mv ./squashfs-root $out/opt/shadow-${shadowChannel}
  '' +

  # Add debug wrapper
  optionalString enableDiagnostics (utilities.debug.wrapRenderer shadowChannel) +

  # Wrap renderer
  ''
    wrapProgram $out/opt/shadow-${shadowChannel}/resources/app.asar.unpacked/release/native/ShadowPCDisplay \
      --run "cd $out/opt/shadow-${shadowChannel}/resources/app.asar.unpacked/release/native/" \
      --prefix LD_LIBRARY_PATH : "$out/opt/shadow-${shadowChannel}" \
      --prefix LD_LIBRARY_PATH : "$out/lib" \
      --prefix LD_LIBRARY_PATH : ${makeLibraryPath runtimeDependencies} \
      --add-flags "--no-usb" \
      --add-flags "--agent \"Linux;x64;Chrome 80.0.3987.165;latest\"" \
      ${concatMapStrings (x: " --add-flags '" + x + "'") extraClientParameters}
  ''

  # Wrap Renderer into binary
  + ''
    makeWrapper \
      $out/opt/shadow-${shadowChannel}/resources/app.asar.unpacked/release/native/ShadowPCDisplay \
      $out/bin/shadow-${shadowChannel}-renderer \
      --prefix LD_LIBRARY_PATH : ${makeLibraryPath runtimeDependencies}
  ''

  # Wrap launcher
  + ''
    makeWrapper $out/opt/shadow-${shadowChannel}/${binaryName} $out/bin/shadow-${shadowChannel} \
      --prefix LD_LIBRARY_PATH : ${makeLibraryPath runtimeDependencies}
  ''

  # Add Desktop entry
  + optionalString desktopLauncher ''
    substitute $out/opt/shadow-${shadowChannel}/${binaryName}.desktop \
      $out/share/applications/${binaryName}.desktop \
      --replace "Exec=AppRun" "Exec=$out/bin/shadow-${shadowChannel}" \
      --replace "Icon=${binaryName}" "Icon=$out/opt/${binaryName}/resources/app.asar.unpacked/release/main/assets/icons/shadow-${shadowChannel}.png"
  '';

  meta = with lib; {
    description = "Client for the Shadow Cloud Gaming Computer";
    homepage = "https://shadow.tech";
    license = [ licenses.unfree ];
    platforms = platforms.linux;
  };
}
