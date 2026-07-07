# cindel_realworld_runner

Private headless integration runner for Cindel.

This package is not a demo app and is not published to pub.dev. GitHub Actions
uses it to run the same real-world Cindel scenario on every supported Flutter
platform through the public API only.

The Flutter shell is intentionally blank. The integration value lives in the
scenario runner under `lib/src/runner` and the generated Cindel models under
`lib/src/models`.

## Local runs

Run from this package directory:

```powershell
flutter test integration_test/realworld_runner_test.dart -d windows
```

Web integration tests must use `flutter drive` and require ChromeDriver in
`PATH`:

Start ChromeDriver in one terminal:

```powershell
chromedriver --port=4444
```

Then run the scenario in another terminal:

```powershell
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/realworld_runner_test.dart -d chrome
```
