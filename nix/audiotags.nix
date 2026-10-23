{
  lib,
  stdenv,
  rustPlatform,
  python3,
}:

{ version, src, ... }:
assert lib.assertMsg (
  version == "1.4.2"
) "Update nix/audiotags/Cargo.lock for audiotags ${version}";
let
  # The pub.dev archive contains the Rust source used by this exact plugin.
  nativeLibrary = rustPlatform.buildRustPackage {
    pname = "libaudiotags";
    inherit version;
    src = src + "/${src.passthru.packageRoot}/rust";
    cargoLock.lockFile = ./audiotags/Cargo.lock;
    postPatch = ''
      cp ${./audiotags/Cargo.lock} Cargo.lock
    '';
    # The pub.dev archive omits the samples used by the upstream Rust tests.
    doCheck = false;
    meta.platforms = [ "x86_64-linux" ];
  };
in
stdenv.mkDerivation {
  pname = "audiotags";
  inherit version src;
  inherit (src) passthru;
  nativeBuildInputs = [ python3 ];
  dontBuild = true;

  postPatch = ''
    python - <<'PY'
    from pathlib import Path

    path = Path("${src.passthru.packageRoot}/linux/CMakeLists.txt")
    text = path.read_text()
    start = text.index("# Download the binary from GitHub.")
    end = text.index("# List of absolute paths to libraries", start)
    text = text[:start] + text[end:]
    original = "$" + "{CMAKE_CURRENT_SOURCE_DIR}/libaudiotags.so"
    assert original in text, "audiotags library path changed"
    text = text.replace(original, "${nativeLibrary}/lib/libaudiotags.so")
    path.write_text(text)

    # Dart FFI does not consistently search the application's ELF RUNPATH.
    path = Path("${src.passthru.packageRoot}/lib/src/ffi.dart")
    text = path.read_text()
    original = "DynamicLibrary.open(_dylib)"
    assert original in text, "audiotags FFI loader changed"
    text = text.replace(
        original,
        "DynamicLibrary.open(io.Platform.isLinux ? '${nativeLibrary}/lib/libaudiotags.so' : _dylib)",
    )
    path.write_text(text)
    PY
  '';

  installPhase = ''
    runHook preInstall
    cp -r . "$out"
    runHook postInstall
  '';
}
