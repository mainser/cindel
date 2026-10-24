"""Prepare an isolated Flutter consumer of the actual package sources/binaries."""

import argparse
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[2]


def prepare(destination: Path, manager="swiftpm"):
    # Caller creates this disposable directory; never rewrite the checkout's
    # workspace constraints or import its generator/test-only dependencies.
    packages = destination / "packages"
    for name in ("cindel", "cindel_annotations", "cindel_flutter_libs"):
        source = ROOT / "packages" / name
        target = packages / name
        target.mkdir(parents=True, exist_ok=False)
        directories = ("lib", "hook", "ios", "macos", "web")
        for directory in directories:
            if (source / directory).is_dir():
                shutil.copytree(source / directory, target / directory, symlinks=True,
                                ignore=shutil.ignore_patterns("build", ".build", ".swiftpm"))
        for name_to_copy in (".pubignore", ".gitignore", "README.md", "CHANGELOG.md", "LICENSE"):
            if (source / name_to_copy).is_file():
                shutil.copyfile(source / name_to_copy, target / name_to_copy)
        pubspec = (source / "pubspec.yaml").read_text()
        pubspec = re.sub(r"(?m)^resolution: workspace\r?\n", "", pubspec)
        pubspec = re.sub(r"(?ms)^dev_dependencies:\n.*?(?=^\S|\Z)", "", pubspec)
        (target / "pubspec.yaml").write_text(pubspec, encoding="utf-8")
    app = destination / "app"
    (app / "pubspec.yaml").write_text("""name: cindel_apple_smoke
publish_to: none
environment:
  sdk: '>=3.11.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  cindel:
    path: ../packages/cindel
  cindel_flutter_libs:
    path: ../packages/cindel_flutter_libs
dependency_overrides:
  cindel_annotations:
    path: ../packages/cindel_annotations
hooks:
  user_defines:
    cindel:
      build_native_assets: false
flutter:
  uses-material-design: true
""".replace("  uses-material-design: true", "  uses-material-design: true\n"
            "  config:\n"
            f"    enable-swift-package-manager: {str(manager == 'swiftpm').lower()}"), encoding="utf-8")
    shutil.copyfile(ROOT / "tool/prebuilt/apple/smoke.dart", app / "lib/main.dart")
    (app / "analysis_options.yaml").unlink(missing_ok=True)
    # The generated template test refers to the default counter app.
    shutil.rmtree(app / "test", ignore_errors=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    prepare(parser.parse_args().destination.resolve())
