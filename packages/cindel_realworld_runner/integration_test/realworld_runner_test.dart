import 'package:cindel_realworld_runner/cindel_realworld_runner.dart';
import 'package:cindel_realworld_runner/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('runs the public Cindel real-world scenario', (tester) async {
    await tester.pumpWidget(const CindelRealworldRunnerApp());

    final report = await CindelRealworldRunner.runAll();

    expect(report.databaseDirectory, isNotEmpty);
    expect(
      report.steps,
      containsAll(<String>[
        'open',
        'seed',
        'crud_queries',
        'links',
        'watchers',
        'reopen',
        'persistence',
        'cleanup',
      ]),
    );
  });
}
