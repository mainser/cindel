# cindel_realworld_runner

Private headless integration runner for Cindel.

This package is not a demo app and is not published to pub.dev. GitHub Actions
uses it to run the same real-world Cindel scenario on every supported Flutter
platform through the public API only.

The Flutter shell is intentionally blank. The integration value lives in the
scenario runner under `lib/src/runner` and the generated Cindel models under
`lib/src/models`.
