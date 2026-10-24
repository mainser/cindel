"""Validate Apple slices, module metadata and all Dart FFI exports on macOS."""

import argparse
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

from apple_symbols import ROOT, ffi_symbols
from verify_native import verify

LIBS = ROOT / "packages/cindel_flutter_libs"


def run(*args):
    return subprocess.check_output(args, text=True, timeout=180)


def check_symbols(binary, architecture):
    found = exported_symbols(binary, architecture)
    missing = set(ffi_symbols()) - found
    if missing:
        raise RuntimeError(f"{binary} ({architecture}) missing {sorted(missing)}")


def exported_symbols(binary, architecture):
    output = run("xcrun", "nm", "-gU", "-arch", architecture, str(binary))
    return set(re.findall(r"\b_(cindel_[a-z0-9_]+)\b", output))


def check_application_symbols(bundle):
    # CocoaPods may link the static Rust archive into its plugin framework;
    # SwiftPM may link it into Runner. Both are visible to DynamicLibrary.process.
    found = exported_symbols(bundle / "Runner", "arm64")
    for framework in (bundle / "Frameworks").glob("*.framework"):
        found.update(exported_symbols(framework / framework.stem, "arm64"))
    missing = set(ffi_symbols()) - found
    if missing:
        raise RuntimeError(f"Release app lost FFI exports: {sorted(missing)}")


def verify_bundle(path, expected):
    with (path / "Info.plist").open("rb") as file:
        info = plistlib.load(file)
    actual = set()
    binaries = []
    for library in info["AvailableLibraries"]:
        platform = library["SupportedPlatform"]
        variant = library.get("SupportedPlatformVariant", "")
        architectures = frozenset(library["SupportedArchitectures"])
        actual.add((platform, variant, architectures))
        slice_path = path / library["LibraryIdentifier"]
        library_path = slice_path / library["LibraryPath"]
        if library_path.suffix == ".framework":
            binary = library_path / "CindelNative"
            headers = library_path / "Headers"
            module = library_path / "Modules/module.modulemap"
            run("codesign", "--verify", "--strict", str(library_path))
            for architecture in architectures:
                identity = run("xcrun", "otool", "-arch", architecture, "-D", str(binary))
                if "@rpath/CindelNative.framework/Versions/A/CindelNative" not in identity:
                    raise RuntimeError(f"Invalid framework install name: {identity}")
        else:
            binary = library_path
            headers = slice_path / library["HeadersPath"]
            module = headers / "module.modulemap"
        if not (headers / "CindelNative.h").is_file() or "CindelNative" not in module.read_text():
            raise RuntimeError(f"Missing CindelNative module in {slice_path}")
        for architecture in architectures:
            check_symbols(binary, architecture)
        binaries.append(binary)
    if actual != expected:
        raise RuntimeError(f"Unexpected slices in {path}: {actual}")
    return binaries


def dump_manifest(package):
    # These checks change sibling files without changing Package.swift.
    # SwiftPM's manifest cache does not track those filesystem reads, so each
    # fixture state must be evaluated anew. This only affects this verifier.
    return json.loads(run("swift", "package", "--manifest-cache", "none",
                          "--package-path", str(package), "dump-package"))


def verify_manifests():
    for platform in ("ios", "macos"):
        package = LIBS / platform / "cindel_flutter_libs"
        manifest = dump_manifest(package)
        if manifest["products"][0]["name"] != "cindel-flutter-libs":
            raise RuntimeError(f"Incorrect Flutter product name in {package}")
        if not any(target["name"] == "CindelNative" and target["type"] == "binary"
                   for target in manifest["targets"]):
            raise RuntimeError(f"Missing binary dependency in {package}")
        # Evaluate both integration modes. Flutter 3.41 exposes its framework
        # through Xcode search paths; newer tooling can create this sibling.
        with tempfile.TemporaryDirectory(prefix="cindel-manifest-") as temp:
            root = Path(temp)
            copied = root / "cindel_flutter_libs"
            shutil.copytree(package, copied, symlinks=True,
                            ignore=shutil.ignore_patterns(".build", ".swiftpm"))
            without = dump_manifest(copied)
            if without["dependencies"]:
                raise RuntimeError("Legacy Flutter must not require a sibling FlutterFramework")
            flutter = root / "FlutterFramework"
            (flutter / "Sources/FlutterFramework").mkdir(parents=True)
            (flutter / "Sources/FlutterFramework/Empty.swift").write_text("// Manifest fixture\n")
            (flutter / "Package.swift").write_text(
                '// swift-tools-version: 5.9\nimport PackageDescription\n'
                'let package = Package(name: "FlutterFramework", '
                'products: [.library(name: "FlutterFramework", targets: ["FlutterFramework"])], '
                'targets: [.target(name: "FlutterFramework")])\n'
            )
            with_flutter = dump_manifest(copied)
            if len(with_flutter["dependencies"]) != 1 or "FlutterFramework" not in json.dumps(with_flutter["dependencies"]):
                raise RuntimeError("New Flutter integration must depend on FlutterFramework")


def main():
    verify_manifests()
    verify_bundle(LIBS / "ios/cindel_flutter_libs/cindel.xcframework", {
        ("ios", "", frozenset(["arm64"])),
        ("ios", "simulator", frozenset(["arm64", "x86_64"])),
    })
    binaries = verify_bundle(LIBS / "macos/cindel_flutter_libs/CindelNative.xcframework", {
        ("macos", "", frozenset(["arm64", "x86_64"])),
    })
    verify(binaries[0])
    verify(LIBS / "macos/libcindel_native.dylib")
    print("PASS Apple manifests, slices, headers, exports and host ABI/database opening")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-bundle", type=Path)
    args = parser.parse_args()
    if args.app_bundle:
        check_application_symbols(args.app_bundle)
        print("PASS iOS Release application retains every FFI symbol")
    else:
        main()
