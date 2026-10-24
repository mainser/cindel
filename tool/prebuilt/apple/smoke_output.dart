import 'dart:io';

// Flutter on iOS sends print() to syslog; simctl --console captures stdio.
Future<void> writeSmokeOutput(String message, {bool failure = false}) async {
  final output = failure ? stderr : stdout;
  output.writeln(message);
  await output.flush();
}
