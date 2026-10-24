"""Regression checks for transporting the versioned macOS framework through Pub."""

import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from apple_symbols import ROOT
from run_apple_smoke import round_trip_plugin_archive
from verify_apple import check_macos_archive


MACOS_PACKAGE = Path("macos/cindel_flutter_libs")
FRAMEWORK = "CindelNative.xcframework/macos-arm64_x86_64/CindelNative.framework"
LINKS = {"Versions/Current": "A"}
LINKS.update({name: f"Versions/Current/{name}"
              for name in ("CindelNative", "Headers", "Modules", "Resources")})


def write_framework_zip(archive, broken_link=None):
    """Small transport fixture; the binary is not intended to execute."""
    info = {"AvailableLibraries": [{
        "LibraryIdentifier": "macos-arm64_x86_64",
        "LibraryPath": "CindelNative.framework",
        "SupportedPlatform": "macos",
        "SupportedArchitectures": ["arm64", "x86_64"],
    }]}
    files = {
        "CindelNative.xcframework/Info.plist": plistlib.dumps(info),
        f"{FRAMEWORK}/Versions/A/CindelNative": b"fixture-native",
        f"{FRAMEWORK}/Versions/A/Headers/CindelNative.h": b"header",
        f"{FRAMEWORK}/Versions/A/Modules/module.modulemap": b"framework module CindelNative {}",
        f"{FRAMEWORK}/Versions/A/Resources/Info.plist": plistlib.dumps({"CFBundleExecutable": "CindelNative"}),
    }
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as package:
        for name, data in files.items():
            package.writestr(name, data)
        for name, target in LINKS.items():
            entry = zipfile.ZipInfo(f"{FRAMEWORK}/{name}")
            entry.create_system = 3
            entry.external_attr = ((stat.S_IFREG if name == broken_link else stat.S_IFLNK) | 0o777) << 16
            package.writestr(entry, target)


def prepare_fixture(destination):
    package = destination / "packages/cindel_flutter_libs"
    (package / MACOS_PACKAGE).mkdir(parents=True)
    (package / "pubspec.yaml").write_text(
        "name: cindel_flutter_libs\nversion: 1.1.3\nenvironment:\n  sdk: '>=3.11.0 <4.0.0'\n")
    for relative in (".pubignore", "macos/prepare_framework.sh", "macos/cindel_flutter_libs/Package.swift"):
        shutil.copyfile(ROOT / "packages/cindel_flutter_libs" / relative, package / relative)
    for relative in ("ios/cindel_flutter_libs/Package.swift",
                     "ios/cindel_flutter_libs/cindel.xcframework/Info.plist",
                     "ios/cindel_flutter_libs/Sources/cindel_flutter_libs/CindelNativeRetention.c"):
        path = package / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("fixture")
    archive = package / MACOS_PACKAGE / "CindelNative.xcframework.zip"
    write_framework_zip(archive)
    # Build outputs coexist with the ZIP locally but must not leak into Pub.
    loose = package / MACOS_PACKAGE / "CindelNative.xcframework/Info.plist"
    loose.parent.mkdir()
    loose.write_text("not for publication")
    (package / "macos/libcindel_native.dylib").write_bytes(b"not for publication")
    (destination / "app").mkdir()
    (destination / "app/pubspec.yaml").write_text("path: ../packages/cindel_flutter_libs\n")
    return package, archive


class AppleArchiveTests(unittest.TestCase):
    def test_archive_rejects_dereferenced_framework_links(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "CindelNative.xcframework.zip"
            write_framework_zip(archive)
            check_macos_archive(archive)
            for name in LINKS:
                with self.subTest(link=name):
                    write_framework_zip(archive, broken_link=name)
                    with self.assertRaisesRegex(RuntimeError, "must preserve symbolic link"):
                        check_macos_archive(archive)

    @unittest.skipUnless(shutil.which("dart"), "Dart is required for the real Pub archive regression")
    def test_pub_round_trip_preserves_zip_and_excludes_loose_framework(self):
        with tempfile.TemporaryDirectory(prefix="cindel pub archive ") as temp:
            destination = Path(temp)
            package, archive = prepare_fixture(destination)
            expected = archive.read_bytes()

            def run_local_pub(*args, cwd=None):
                # Resolve through PATH, including dart.bat on Windows. This
                # command writes a local archive only and never uploads it.
                self.assertEqual(args[:3], ("dart", "pub", "publish"))
                self.assertTrue(any(arg.startswith("--to-archive=") for arg in args))
                result = subprocess.run([shutil.which("dart"), *args[1:]], cwd=cwd,
                                        text=True, capture_output=True, timeout=120)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

            # Native signature/ABI checks need a real Mach-O and run separately
            # on macOS; here validate the links inside the real Pub payload.
            with patch("run_apple_smoke.run", side_effect=run_local_pub), \
                    patch("run_apple_smoke.verify_macos_archive", side_effect=check_macos_archive) as verify:
                round_trip_plugin_archive(destination)
            published = destination / "published_libs"
            actual = published / MACOS_PACKAGE / archive.name
            self.assertEqual(actual.read_bytes(), expected)
            verify.assert_called_once_with(actual)
            self.assertFalse((published / MACOS_PACKAGE / "CindelNative.xcframework").exists())
            self.assertFalse((published / "macos/libcindel_native.dylib").exists())
            self.assertIn("path: ../published_libs", (destination / "app/pubspec.yaml").read_text())
            self.assertEqual(archive.read_bytes(), expected)

    @unittest.skipUnless(os.name != "nt" and shutil.which("bash") and shutil.which("unzip"),
                         "POSIX Bash and unzip are required for CocoaPods extraction")
    def test_cocoapods_extracts_local_zip_with_links_and_rejects_broken_archive(self):
        with tempfile.TemporaryDirectory(prefix="cindel pod archive ") as temp:
            package, archive = prepare_fixture(Path(temp))
            script = package / "macos/prepare_framework.sh"
            framework = package / "macos/build" / FRAMEWORK
            for _ in range(2):
                subprocess.run(["bash", str(script)], check=True, capture_output=True, timeout=30)
                for name, target in LINKS.items():
                    self.assertTrue((framework / name).is_symlink())
                    self.assertEqual(os.readlink(framework / name), target)
                self.assertEqual((framework / "CindelNative").read_bytes(), b"fixture-native")
                self.assertEqual(list((package / "macos/build").glob("cindel-framework.*")), [])
            for name in LINKS:
                with self.subTest(link=name):
                    write_framework_zip(archive, broken_link=name)
                    result = subprocess.run(["bash", str(script)], capture_output=True, timeout=30)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertTrue((framework / "Versions/Current").is_symlink())
                    self.assertEqual(list((package / "macos/build").glob("cindel-framework.*")), [])


if __name__ == "__main__":
    unittest.main()
