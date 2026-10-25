"""Assemble current-run artifacts and verify the bytes that Pub will distribute."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import tarfile
import tempfile


PATHS = {
    "android": [f"android/src/main/jniLibs/{abi}/libcindel_native.so"
                for abi in ("arm64-v8a", "armeabi-v7a", "x86_64")],
    "linux": ["linux/libcindel_native.so"],
    "windows": ["windows/cindel_native.dll"],
    "web": ["web/cindel_worker.js", *[f"web/pkg/{name}" for name in (
        "cindel_native.js", "cindel_native.d.ts", "cindel_native_bg.wasm",
        "cindel_native_bg.wasm.d.ts")]],
    "apple": ["ios/cindel_flutter_libs/cindel.xcframework",
              "macos/cindel_flutter_libs/CindelNative.xcframework",
              "macos/cindel_flutter_libs/CindelNative.xcframework.zip",
              "macos/libcindel_native.dylib"],
}
MACOS_LOOSE = "macos/cindel_flutter_libs/CindelNative.xcframework/"
RUNTIME_DIRECTORIES = (
    "android/src/main/jniLibs/", "web/pkg/",
    "ios/cindel_flutter_libs/cindel.xcframework/", MACOS_LOOSE,
)


def in_pub(name):
    # These two outputs are deliberately excluded by the plugin's .pubignore.
    # macOS reaches Pub through the ZIP that preserves framework symlinks.
    return name != "macos/libcindel_native.dylib" and not name.startswith(MACOS_LOOSE)


def digest(stream):
    return hashlib.file_digest(stream, "sha256").hexdigest()


def file_record(path, root):
    if path.is_symlink():
        path.resolve(strict=True).relative_to(root.resolve())
        return {"link": path.readlink().as_posix()}
    with path.open("rb") as stream:
        return {"sha256": digest(stream), "size": path.stat().st_size}


def inventory(root, paths):
    result = {}
    for relative in paths:
        path = root / relative
        if not path.exists():
            raise RuntimeError(f"Missing built artifact: {path}")
        files = sorted(path.rglob("*")) if path.is_dir() else [path]
        previous_count = len(result)
        for item in files:
            if item.is_symlink() or item.is_file():
                result[item.relative_to(root).as_posix()] = file_record(item, root)
        if len(result) == previous_count:
            raise RuntimeError(f"Empty built artifact: {path}")
    return result


def assemble(artifacts, destination, manifest):
    # download-artifact must retain each artifact's name. Never choose between
    # two partial roots or fall back to binaries already in the Git checkout.
    with tempfile.TemporaryDirectory(prefix="cindel-release-apple-") as temporary:
        apple = Path(temporary)
        archive = artifacts / "cindel-prebuilt-apple/cindel-apple-packages.tar.gz"
        with tarfile.open(archive, "r:gz") as package:
            package.extractall(apple, filter="data")
        sources = {platform: artifacts / f"cindel-prebuilt-{platform}/cindel_flutter_libs"
                   for platform in PATHS}
        sources["apple"] = apple / "packages/cindel_flutter_libs"
        # Validate every platform before touching the destination. A missing
        # download must fail even when the checkout contains an old binary.
        records = {platform: inventory(sources[platform], paths)
                   for platform, paths in PATHS.items()}
        expected = {}
        for platform, files in records.items():
            for name, record in files.items():
                if name in expected:
                    raise RuntimeError(f"Duplicate artifact path: {name}")
                expected[name] = record
                source, target = sources[platform] / name, destination / name
                target.parent.mkdir(parents=True, exist_ok=True)
                if "link" in record:
                    if target.is_symlink() or target.is_file():
                        target.unlink()
                    target.symlink_to(record["link"], target_is_directory=source.is_dir())
                else:
                    if target.is_symlink():
                        target.unlink()
                    shutil.copy2(source, target)
        verify_tree(destination, expected)
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(json.dumps({"files": expected}, indent=2) + "\n", encoding="utf-8")
        print(f"PASS: assembled and hashed {len(expected)} files from all five build artifacts")


def verify_tree(directory, expected):
    for name, record in expected.items():
        path = directory / name
        if not path.exists() or file_record(path, directory) != record:
            raise RuntimeError(f"Built artifact differs in package: {name}")


def verify_package(archive, manifest, version):
    expected = json.loads(manifest.read_text(encoding="utf-8"))["files"]
    required = {name: record for name, record in expected.items() if in_pub(name)}
    seen = set()
    with tarfile.open(archive, "r:gz") as package:
        for member in package:
            name = member.name.removeprefix("./")
            if member.isdir():
                continue
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts or name in seen:
                raise RuntimeError(f"Invalid or duplicate package entry: {name}")
            seen.add(name)
            if name in required:
                record = required[name]
                if "link" in record:
                    if not member.issym() or member.linkname != record["link"]:
                        raise RuntimeError(f"Changed package link: {name}")
                elif (not member.isfile() or member.size != record["size"]
                      or digest(package.extractfile(member)) != record["sha256"]):
                    raise RuntimeError(f"Package does not contain the freshly built file: {name}")
            elif (name in expected or name.startswith(RUNTIME_DIRECTORIES)
                  or name.endswith((".so", ".dll", ".dylib", ".a", ".wasm", ".xcframework.zip"))):
                raise RuntimeError(f"Unexpected native artifact in package: {name}")
            if name == "pubspec.yaml":
                pubspec = package.extractfile(member).read().decode("utf-8")
                if (not re.search(r"^name:\s*cindel_flutter_libs\s*$", pubspec, re.M)
                        or not re.search(rf"^version:\s*{re.escape(version)}\s*$", pubspec, re.M)):
                    raise RuntimeError("Unexpected package name or release version")
    missing = (set(required) | {"pubspec.yaml"}) - seen
    if missing:
        raise RuntimeError(f"Missing built files in Pub archive: {sorted(missing)}")
    print(f"PASS: Pub archive {version} contains all {len(required)} expected runtime files unchanged")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("assemble")
    build.add_argument("--artifacts", type=Path, required=True)
    build.add_argument("--destination", type=Path, required=True)
    build.add_argument("--manifest", type=Path, required=True)
    check = commands.add_parser("verify-package")
    check.add_argument("--archive", type=Path, required=True)
    check.add_argument("--manifest", type=Path, required=True)
    check.add_argument("--version", required=True)
    arguments = parser.parse_args()
    if arguments.command == "assemble":
        assemble(arguments.artifacts, arguments.destination, arguments.manifest)
    else:
        verify_package(arguments.archive, arguments.manifest, arguments.version)


if __name__ == "__main__":
    main()
