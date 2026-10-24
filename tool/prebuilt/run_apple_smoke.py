"""Build and run an isolated Flutter consumer, using SwiftPM or CocoaPods."""

import argparse
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import tarfile
import tempfile

from prepare_apple_smoke import prepare
from verify_apple import check_application_symbols


def run(*args, cwd=None, timeout=900, capture=False):
    print("+ " + " ".join(str(arg) for arg in args), flush=True)
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, check=False,
                            text=True, timeout=timeout,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.STDOUT if capture else None)
    if capture:
        print(result.stdout, flush=True)
    result.check_returncode()
    return result.stdout


def check_success(output):
    if "CINDEL_APPLE_PASS ABI=39" not in output or "CINDEL_APPLE_FAIL" in output:
        raise RuntimeError("Consumer did not complete the ABI/database smoke test")


def round_trip_plugin_archive(destination):
    # Exercise pub's actual file selection and symlink transport, not merely a
    # directory copy. This writes a local archive only; it never uploads to pub.
    archive = destination / "cindel_flutter_libs.tar.gz"
    run("dart", "pub", "publish", f"--to-archive={archive}", "--skip-validation",
        cwd=destination / "packages/cindel_flutter_libs")
    published = destination / "published_libs"
    with tarfile.open(archive) as package:
        names = set(package.getnames())
        required = {
            "ios/cindel_flutter_libs/Package.swift",
            "macos/cindel_flutter_libs/Package.swift",
            "ios/cindel_flutter_libs/cindel.xcframework/Info.plist",
            "macos/cindel_flutter_libs/CindelNative.xcframework/Info.plist",
            "ios/cindel_flutter_libs/Sources/cindel_flutter_libs/CindelNativeRetention.c",
        }
        if not required.issubset(names) or "macos/libcindel_native.dylib" in names:
            raise RuntimeError(f"Invalid published Apple layout: missing {required - names}")
        package.extractall(published, filter="data")
    framework = next((published / "macos").rglob("CindelNative.framework"))
    if not (framework / "CindelNative").is_file() or not (framework / "Versions/Current").is_symlink():
        raise RuntimeError("pub archive did not preserve the versioned macOS framework")
    app_pubspec = destination / "app/pubspec.yaml"
    app_pubspec.write_text(app_pubspec.read_text().replace(
        "path: ../packages/cindel_flutter_libs", "path: ../published_libs"), encoding="utf-8")


def verify_manager(app, manager, target):
    if manager == "cocoapods":
        lock = (app / target / "Podfile.lock").read_text()
        pubspec = (app.parent / "published_libs/pubspec.yaml").read_text()
        version = re.search(r"(?m)^version: (\S+)", pubspec).group(1)
        if f"cindel_flutter_libs ({version})" not in lock:
            raise RuntimeError("Cindel was not integrated by CocoaPods")
    else:
        # Reject an unnoticed CocoaPods fallback for this plugin.
        for lock in (app / target).rglob("Podfile.lock"):
            if "cindel_flutter_libs" in lock.read_text():
                raise RuntimeError("SwiftPM test fell back to CocoaPods for Cindel")
        manifests = list((app / target).rglob("FlutterGeneratedPluginSwiftPackage/Package.swift"))
        if not any("cindel-flutter-libs" in path.read_text() for path in manifests):
            raise RuntimeError("Flutter did not link the Cindel Swift package")


def run_macos(app, manager):
    for mode in ("debug", "release"):
        run("flutter", "build", "macos", f"--{mode}", cwd=app)
        verify_manager(app, manager, "macos")
        bundle = next((app / "build/macos/Build/Products" / mode.capitalize()).glob("*.app"))
        frameworks = list((bundle / "Contents/Frameworks").glob("CindelNative.framework"))
        if len(frameworks) != 1 or list(bundle.rglob("libcindel_native.dylib")):
            raise RuntimeError("Expected exactly one embedded Cindel framework")
        binary = bundle / "Contents/MacOS/cindel_apple_smoke"
        # Launch outside both the checkout and the package directory. This
        # would fail with the old cwd-relative loader even if a local dylib exists.
        with tempfile.TemporaryDirectory(prefix="cindel-launch-") as launch:
            check_success(run(binary, cwd=launch, timeout=120, capture=True))
        print(f"PASS macOS {manager} {mode}; bundle bytes="
              f"{sum(p.stat().st_size for p in bundle.rglob('*') if p.is_file() and not p.is_symlink())}")


def run_ios(app, manager):
    run("flutter", "build", "ios", "--release", "--no-codesign", cwd=app)
    verify_manager(app, manager, "ios")
    check_application_symbols(app / "build/ios/iphoneos/Runner.app")
    run("flutter", "build", "ios", "--simulator", "--debug", "--no-codesign", cwd=app)
    verify_manager(app, manager, "ios")
    data = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json", capture=True))
    devices = [device for runtime, entries in data["devices"].items() if "iOS" in runtime
               for device in entries if device["name"].startswith("iPhone")]
    if not devices:
        raise RuntimeError("Install an iOS Simulator runtime on this Xcode runner")
    device = devices[0]
    udid = device["udid"]
    started = device["state"] != "Booted"
    try:
        if started:
            run("xcrun", "simctl", "boot", udid)
        run("xcrun", "simctl", "bootstatus", udid, "-b", timeout=300)
        bundle = app / "build/ios/iphonesimulator/Runner.app"
        identifier = run("/usr/libexec/PlistBuddy", "-c", "Print CFBundleIdentifier", bundle / "Info.plist", capture=True).strip()
        run("xcrun", "simctl", "install", udid, bundle)
        check_success(run("xcrun", "simctl", "launch", "--console", "--terminate-running-process",
                          udid, identifier, timeout=180, capture=True))
        run("xcrun", "simctl", "uninstall", udid, identifier)
    finally:
        if started:
            run("xcrun", "simctl", "shutdown", udid)
    print(f"PASS iOS {manager}: device Release link/exports and simulator runtime")


def main(manager):
    if platform.system() != "Darwin":
        raise SystemExit("Apple integration checks require macOS with Xcode")
    os.environ.pop("CINDEL_NATIVE_LIBRARY", None)
    with tempfile.TemporaryDirectory(prefix="cindel-apple-consumer-") as temp:
        destination = Path(temp)
        app = destination / "app"
        app.mkdir()
        # Set the project-level flag before template creation too. This avoids
        # changing the runner's (or a maintainer's) global Flutter preferences.
        (app / "pubspec.yaml").write_text(
            "name: cindel_apple_smoke\nenvironment:\n  sdk: '>=3.11.0 <4.0.0'\n"
            "flutter:\n  config:\n"
            f"    enable-swift-package-manager: {str(manager == 'swiftpm').lower()}\n",
            encoding="utf-8",
        )
        run("flutter", "create", "--no-pub", "--platforms=ios,macos",
            "--org=dev.cindel", "--project-name=cindel_apple_smoke", ".", cwd=app)
        prepare(destination, manager)
        round_trip_plugin_archive(destination)
        run("flutter", "pub", "get", cwd=app)
        run("flutter", "analyze", "lib", cwd=app)
        run_macos(app, manager)
        run_ios(app, manager)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manager", choices=("swiftpm", "cocoapods"), required=True)
    main(parser.parse_args().manager)
