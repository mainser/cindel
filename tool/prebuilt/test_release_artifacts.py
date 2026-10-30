"""Regressions for complete release assembly and the actual Pub payload."""

import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from release_artifacts import PATHS, assemble, in_pub, verify_package
from verify_android import abi_from_disassembly, verify as verify_android


ROOT = Path(__file__).resolve().parents[2]


class ReleaseArtifactsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="cindel-release-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.artifacts = self.root / "downloads"
        self.destination = self.root / "package"
        self.manifest = self.root / "manifest.json"
        self.archive = self.root / "package.tar.gz"
        self.files = {}
        for platform, paths in PATHS.items():
            source = (self.root / "apple/packages/cindel_flutter_libs" if platform == "apple"
                      else self.artifacts / f"cindel-prebuilt-{platform}/cindel_flutter_libs")
            for relative in paths:
                if relative.endswith(".xcframework"):
                    relative += "/Info.plist"
                payload = f"fresh {platform}: {relative}".encode()
                path = source / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(payload)
                self.files[relative] = payload
        self.pack_apple()
        self.destination.mkdir()
        (self.destination / "pubspec.yaml").write_text(
            "name: cindel_flutter_libs\nversion: 1.1.4\nenvironment:\n  sdk: ^3.11.0\n")

    def pack_apple(self):
        archive = self.artifacts / "cindel-prebuilt-apple/cindel-apple-packages.tar.gz"
        archive.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive, "w:gz") as package:
            package.add(self.root / "apple/packages", arcname="packages")

    def assemble(self):
        assemble(self.artifacts, self.destination, self.manifest)

    def make_archive(self, changes=None, omit=()):
        files = {name: data for name, data in self.files.items() if in_pub(name)}
        files["pubspec.yaml"] = (self.destination / "pubspec.yaml").read_bytes()
        files.update(changes or {})
        with tarfile.open(self.archive, "w:gz") as package:
            for name, data in files.items():
                if name not in omit:
                    entry = tarfile.TarInfo(name)
                    entry.size = len(data)
                    package.addfile(entry, io.BytesIO(data))

    def test_separate_roots_replace_every_old_binary(self):
        """Apple's packages/ prefix must not hide the other four build artifacts."""
        for name in self.files:
            path = self.destination / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"old checkout binary")
        self.assemble()
        for name, payload in self.files.items():
            self.assertEqual((self.destination / name).read_bytes(), payload, name)
        self.assertEqual(set(json.loads(self.manifest.read_text())["files"]), set(self.files))

    def test_missing_download_cannot_fall_back_to_checkout(self):
        """A missing fresh file fails before assembly, despite a complete old package."""
        self.assemble()
        sentinel = self.destination / PATHS["windows"][0]
        sentinel.write_bytes(b"unchanged checkout")
        for platform in ("android", "linux", "windows", "web"):
            with self.subTest(platform=platform):
                source = self.artifacts / f"cindel-prebuilt-{platform}/cindel_flutter_libs" / PATHS[platform][0]
                data = source.read_bytes()
                source.unlink()
                with self.assertRaisesRegex(RuntimeError, "Missing built artifact"):
                    self.assemble()
                self.assertEqual(sentinel.read_bytes(), b"unchanged checkout")
                source.write_bytes(data)
        archive = self.artifacts / "cindel-prebuilt-apple/cindel-apple-packages.tar.gz"
        archive.unlink()
        with self.assertRaises(FileNotFoundError):
            self.assemble()

    def test_archive_checks_every_platform_and_version(self):
        """Pub must carry every fresh runtime, the macOS ZIP and the intended version."""
        self.assemble()
        self.make_archive()
        verify_package(self.archive, self.manifest, "1.1.4")
        for name in (name for name in self.files if in_pub(name)):
            with self.subTest(file=name, failure="old bytes"):
                self.make_archive({name: b"old ABI 39 binary"})
                with self.assertRaisesRegex(RuntimeError, "freshly built"):
                    verify_package(self.archive, self.manifest, "1.1.4")
            with self.subTest(file=name, failure="missing"):
                self.make_archive(omit=[name])
                with self.assertRaisesRegex(RuntimeError, "Missing built files"):
                    verify_package(self.archive, self.manifest, "1.1.4")
        self.make_archive()
        with self.assertRaisesRegex(RuntimeError, "release version"):
            verify_package(self.archive, self.manifest, "1.1.3")

    def test_archive_rejects_stale_extra_and_excluded_binaries(self):
        """Stale architectures and loose macOS build outputs cannot leak into Pub."""
        self.assemble()
        for name in ("android/src/main/jniLibs/unused/libcindel_native.so",
                     "ios/cindel_flutter_libs/cindel.xcframework/stale/CindelNative",
                     "web/pkg/stale.js",
                     "macos/libcindel_native.dylib",
                     "macos/cindel_flutter_libs/CindelNative.xcframework/Info.plist"):
            with self.subTest(file=name):
                self.make_archive({name: b"stale"})
                with self.assertRaisesRegex(RuntimeError, "Unexpected native artifact"):
                    verify_package(self.archive, self.manifest, "1.1.4")

    @unittest.skipIf(os.name == "nt", "Framework symlinks are assembled on Linux runners")
    def test_apple_framework_links_survive_assembly(self):
        """The shared assembler preserves versioned framework links and file mode."""
        framework = "macos/cindel_flutter_libs/CindelNative.xcframework/Test.framework"
        source = self.root / "apple/packages/cindel_flutter_libs" / framework
        binary = source / "Versions/A/CindelNative"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"native")
        binary.chmod(0o755)
        (source / "Versions/Current").symlink_to("A", target_is_directory=True)
        (source / "CindelNative").symlink_to("Versions/Current/CindelNative")
        self.pack_apple()
        self.assemble()
        target = self.destination / framework
        self.assertTrue((target / "Versions/Current").is_symlink())
        self.assertTrue((target / "CindelNative").is_symlink())
        self.assertEqual((target / "CindelNative").read_bytes(), b"native")
        self.assertEqual((target / "Versions/A/CindelNative").stat().st_mode & 0o777, 0o755)

    @unittest.skipUnless(shutil.which("dart"), "Dart is needed to generate a real Pub archive")
    def test_real_pub_archive_retains_the_complete_assembly(self):
        """Pub's real file selection keeps all fresh artifacts and excludes loose macOS outputs."""
        self.assemble()
        shutil.copyfile(ROOT / "packages/cindel_flutter_libs/.pubignore", self.destination / ".pubignore")
        subprocess.run([shutil.which("dart"), "pub", "publish",
                        f"--to-archive={self.archive}", "--skip-validation"],
                       cwd=self.destination, check=True, capture_output=True, text=True, timeout=120)
        verify_package(self.archive, self.manifest, "1.1.4")


class AndroidAbiTests(unittest.TestCase):
    def test_constants_for_all_architectures(self):
        """Read actual exported return values on ARM64, Thumb ARMv7 and x64."""
        for instruction, tail in (("mov w0, #0x27 // =39", "ret"),
                                  ("movs r0, #0x27", "bx lr"),
                                  ("movl $0x27, %eax", "retq")):
            with self.subTest(instruction=instruction):
                output = f"0000 <cindel_abi_version>:\n 0: {instruction}\n 4: {tail}\n 5: int3"
                self.assertEqual(abi_from_disassembly(output), 39)

    def test_old_or_unrecognized_abi_is_rejected(self):
        """ABI 34 and nonconstant/malformed exports must stop the Android build job."""
        with patch("verify_android.subprocess.check_output", return_value=
                   "0 <cindel_abi_version>:\n 0: mov w0, #34\n 4: ret"):
            with self.assertRaisesRegex(RuntimeError, "expected ABI 40, received 34"):
                verify_android(Path("fixture"), Path("objdump"))
        for body in ("", "0: mov w0, #39\n 4: nop", "0: bl helper\n 4: ret"):
            with self.subTest(body=body):
                with self.assertRaises(RuntimeError):
                    abi_from_disassembly("0 <cindel_abi_version>:\n" + body)


if __name__ == "__main__":
    unittest.main()
