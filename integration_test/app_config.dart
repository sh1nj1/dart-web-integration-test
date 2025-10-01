// App-specific configuration for test_target app
import 'package:flutter_test/flutter_test.dart';
import 'package:test_target/main.dart' as app;

/// Initialize and start the test_target app for testing
Future<void> startApp(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle();
}
