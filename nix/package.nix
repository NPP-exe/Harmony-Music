{
  lib,
  flutter329,
  gtk3,
  libayatana-appindicator,
  mpv-unwrapped,
  jdk17,
  makeDesktopItem,
  copyDesktopItems,
  callPackage,
  src,
  version,
  lockfile,
  gitHashesFile,
}:
let
  pubspecLock = lib.importJSON lockfile;
  recordedHashes = lib.importJSON gitHashesFile;
  gitDependencies = lib.filterAttrs (_: package: package.source == "git") pubspecLock.packages;
  gitHashes = lib.mapAttrs (
    name: package:
    let
      recorded =
        recordedHashes.${name} or (throw "Missing hash for ${name}; run harmony-update-lockfile");
    in
    assert lib.assertMsg (
      recorded.url == package.description.url && recorded.rev == package.description.resolved-ref
    ) "Stale hash for ${name}; run harmony-update-lockfile";
    recorded.hash
  ) gitDependencies;
in
flutter329.buildFlutterApplication {
  pname = "harmonymusic";
  inherit
    version
    src
    pubspecLock
    gitHashes
    ;

  customSourceBuilders.audiotags = callPackage ./audiotags.nix { };

  nativeBuildInputs = [
    jdk17
    copyDesktopItems
  ];
  buildInputs = [
    gtk3
    libayatana-appindicator
  ];
  runtimeDependencies = [ mpv-unwrapped ];
  env.JAVA_HOME = jdk17.home;

  postPatch = ''
    substituteInPlace lib/utils/update_check_flag_file.dart \
      --replace-fail 'const updateCheckFlag = true;' 'const updateCheckFlag = false;'
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "harmonymusic";
      desktopName = "Harmony Music";
      genericName = "Music Player";
      comment = "Stream music from YouTube and YouTube Music";
      exec = "harmonymusic";
      icon = "harmonymusic";
      categories = [
        "AudioVideo"
        "Audio"
        "Music"
      ];
      terminal = false;
    })
  ];

  postInstall = ''
    install -Dm644 assets/icons/icon.png "$out/share/icons/hicolor/512x512/apps/harmonymusic.png"
    install -Dm644 LICENSE "$out/share/licenses/harmonymusic/LICENSE"
  '';

  meta = {
    description = "Cross-platform music streaming application";
    homepage = "https://github.com/NPP-exe/Harmony-Music";
    mainProgram = "harmonymusic";
    platforms = [ "x86_64-linux" ];
  };
}
