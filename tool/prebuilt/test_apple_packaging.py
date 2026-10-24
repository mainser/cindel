"""Regression checks for the Apple packaging gates (no Xcode required)."""

import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from apple_symbols import OUTPUT, ROOT, ffi_symbols, retention_source
from prepare_apple_smoke import prepare
from run_apple_smoke import check_success
from verify_apple import check_application_symbols, check_symbols, verify_bundle, verify_manifests


class ApplePackagingTests(unittest.TestCase):
    def copy_manifests(self, root):
        for platform in ("ios", "macos"):
            relative = Path(platform) / "cindel_flutter_libs/Package.swift"
            destination = root / relative
            destination.parent.mkdir(parents=True)
            shutil.copyfile(ROOT / "packages/cindel_flutter_libs" / relative, destination)

    def test_manifest_gate_reevaluates_after_flutter_framework_is_created(self):
        cache = {}
        observations = []

        def dump_package(*args):
            package = Path(args[args.index("--package-path") + 1])
            has_flutter = (package.parent / "FlutterFramework/Package.swift").is_file()
            # Model SwiftPM's evaluated-manifest cache: changing a sibling file
            # does not change the package location or manifest contents.
            key = (package, (package / "Package.swift").read_bytes())
            uncached = "--manifest-cache" in args and args[args.index("--manifest-cache") + 1] == "none"
            if uncached or key not in cache:
                cache[key] = json.dumps({
                    "products": [{"name": "cindel-flutter-libs"}],
                    "targets": [{"name": "CindelNative", "type": "binary"}],
                    "dependencies": [{"name": "FlutterFramework"}] if has_flutter else [],
                })
            observations.append(has_flutter)
            return cache[key]

        with tempfile.TemporaryDirectory() as temp:
            libs = Path(temp)
            self.copy_manifests(libs)
            with patch("verify_apple.LIBS", libs), patch("verify_apple.run", side_effect=dump_package):
                verify_manifests()
        self.assertEqual(observations, [False, False, True, False, False, True])

    def test_manifest_gate_still_rejects_missing_flutter_dependency(self):
        manifest = json.dumps({
            "products": [{"name": "cindel-flutter-libs"}],
            "targets": [{"name": "CindelNative", "type": "binary"}],
            "dependencies": [],
        })
        with tempfile.TemporaryDirectory() as temp:
            libs = Path(temp)
            self.copy_manifests(libs)
            with patch("verify_apple.LIBS", libs), patch("verify_apple.run", return_value=manifest):
                with self.assertRaisesRegex(RuntimeError, "must depend on FlutterFramework"):
                    verify_manifests()

    @unittest.skipUnless(shutil.which("swift"), "Swift is required to evaluate the real manifests")
    def test_real_manifests_with_and_without_flutter_framework(self):
        # dump-package evaluates the real manifests without compiling native
        # targets, so this also runs before XCFrameworks are built on macOS.
        with tempfile.TemporaryDirectory() as temp:
            libs = Path(temp)
            self.copy_manifests(libs)
            with patch("verify_apple.LIBS", libs):
                verify_manifests()

    @unittest.skipUnless(shutil.which("clang"), "Clang is required for the optimized link-root check")
    def test_optimized_retention_object_references_every_ffi_symbol(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "retention.o"
            subprocess.run(["clang", "-O3", "-c", str(OUTPUT), "-o", str(output)],
                           check=True, timeout=60)
            undefined = subprocess.check_output(["nm", "-u", str(output)], text=True, timeout=30)
            found = set(re.findall(r"\b_?(cindel_[a-z0-9_]+)\b", undefined))
            self.assertEqual(found, set(ffi_symbols()))

    def test_link_roots_match_every_current_dart_lookup(self):
        self.assertEqual(OUTPUT.read_text(), retention_source())
        rust = "\n".join(path.read_text(encoding="utf-8")
                         for path in (ROOT / "packages/cindel/native/src").rglob("*.rs"))
        for symbol in ffi_symbols():
            self.assertIn(f"fn {symbol}(", rust)

    def test_export_check_rejects_missing_entrypoint_even_with_valid_abi(self):
        exports = "\n".join("000000 T _" + symbol for symbol in ffi_symbols())
        with patch("verify_apple.run", return_value=exports):
            check_symbols(Path("fixture"), "arm64")
        exports = exports.replace("_cindel_close", "_removed_close")
        with patch("verify_apple.run", return_value=exports):
            with self.assertRaisesRegex(RuntimeError, "cindel_close"):
                check_symbols(Path("fixture"), "arm64")

    def test_release_symbols_can_live_in_runner_or_cocoapods_framework(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp)
            (app / "Frameworks/cindel_flutter_libs.framework").mkdir(parents=True)
            for symbols_by_image in ((set(ffi_symbols()), set()), (set(), set(ffi_symbols()))):
                with patch("verify_apple.exported_symbols", side_effect=symbols_by_image):
                    check_application_symbols(app)
            with patch("verify_apple.exported_symbols", return_value={"cindel_abi_version"}):
                with self.assertRaisesRegex(RuntimeError, "lost FFI exports"):
                    check_application_symbols(app)

    def test_xcframework_gate_rejects_missing_simulator_architecture(self):
        with tempfile.TemporaryDirectory() as temp:
            bundle = Path(temp)
            headers = bundle / "sim/Headers"
            headers.mkdir(parents=True)
            (headers / "CindelNative.h").write_text("header")
            (headers / "module.modulemap").write_text("module CindelNative {}")
            (bundle / "Info.plist").write_bytes(plistlib.dumps({
                "AvailableLibraries": [{
                    "LibraryIdentifier": "sim", "LibraryPath": "libcindel_native.a",
                    "HeadersPath": "Headers", "SupportedPlatform": "ios",
                    "SupportedPlatformVariant": "simulator", "SupportedArchitectures": ["arm64"],
                }],
            }))
            with patch("verify_apple.check_symbols"):
                with self.assertRaisesRegex(RuntimeError, "Unexpected slices"):
                    verify_bundle(bundle, {("ios", "simulator", frozenset(["arm64", "x86_64"]))})

    def test_consumer_gate_requires_completion_not_just_process_success(self):
        check_success("CINDEL_APPLE_PASS ABI=39")
        for output in ("", "Launched application", "CINDEL_APPLE_PASS ABI=39\nCINDEL_APPLE_FAIL"):
            with self.assertRaises(RuntimeError):
                check_success(output)

    def test_consumer_keeps_runtime_dependencies_without_workspace_dev_constraints(self):
        with tempfile.TemporaryDirectory() as source_temp, tempfile.TemporaryDirectory() as destination_temp:
            source, destination = Path(source_temp), Path(destination_temp)
            for name in ("cindel", "cindel_annotations", "cindel_flutter_libs"):
                package = source / "packages" / name
                (package / "lib").mkdir(parents=True)
                (package / "pubspec.yaml").write_text(
                    f"name: {name}\nresolution: workspace\n"
                    "dependencies:\n  ffi: ^2.2.0\n"
                    "dev_dependencies:\n  test: ^1.31.1\n"
                    "flutter:\n  plugin: {}\n"
                )
            fixture = source / "tool/prebuilt/apple/smoke.dart"
            fixture.parent.mkdir(parents=True)
            fixture.write_text("void main() {}")
            (destination / "app/lib").mkdir(parents=True)
            with patch("prepare_apple_smoke.ROOT", source):
                prepare(destination)
            for name in ("cindel", "cindel_annotations", "cindel_flutter_libs"):
                pubspec = (destination / "packages" / name / "pubspec.yaml").read_text()
                self.assertIn("ffi: ^2.2.0", pubspec)
                self.assertIn("flutter:\n  plugin: {}", pubspec)
                self.assertNotIn("resolution:", pubspec)
                self.assertNotIn("dev_dependencies:", pubspec)
            self.assertIn("build_native_assets: false", (destination / "app/pubspec.yaml").read_text())


if __name__ == "__main__":
    unittest.main()
