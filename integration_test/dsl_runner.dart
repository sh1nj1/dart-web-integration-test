import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

// Import generated test DSL data
import 'test_dsl_data.dart';

// Import app-specific configuration (optional)
// If app_config.dart exists, it will be used to start the app
// Otherwise, the app must be running before tests start
import 'app_config.dart' as config;
import 'dsl_log_protocol.dart';

// Custom print function with [DSL] prefix
void log(Object? message) => print('[DSL] $message');
void logData(String type, Map<String, dynamic> payload) =>
    print(DslLogProtocol.encode(type, payload));

final Map<String, Finder> _storedFinders = <String, Finder>{};

const bool _enableInteractiveSession =
    bool.fromEnvironment('DSL_INTERACTIVE', defaultValue: false);
const String _interactiveServerUrl =
    String.fromEnvironment('DSL_SERVER_URL', defaultValue: '');
const Duration _interactivePollInterval = Duration(seconds: 1);
const String _interactiveExitCommand =
    String.fromEnvironment('DSL_EXIT_COMMAND', defaultValue: 'exit');

class _SuiteResult {
  const _SuiteResult({
    required this.passed,
    required this.failed,
    required this.failedTests,
  });

  final int passed;
  final int failed;
  final List<String> failedTests;
}

/// Generic DSL test runner for Flutter integration tests
///
/// This runner does not depend on any specific app implementation.
/// To customize for your app:
/// 1. Create app_config.dart from app_config.dart.template
/// 2. Implement the startApp() function to launch your app
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Flutter Web Integration Test', () {
    late Map<String, dynamic> testSuite;

    setUpAll(() async {
      // Load test DSL from generated Dart code
      testSuite = jsonDecode(testDslJson);
      log('Loaded test suite: ${testSuite['name']}');
    });

    testWidgets('Run DSL tests', (WidgetTester tester) async {
      // Start the app using app-specific configuration
      await config.startApp(tester);

      final initialResult = await _runDslTestSuite(
        tester,
        testSuite,
        suiteLabel: testSuite['name'] as String?,
      );

      var totalFailed = initialResult.failed;
      final failedTests = <String>[...initialResult.failedTests];

      if (_enableInteractiveSession) {
        final interactiveResult = await _runInteractiveSessions(tester);
        totalFailed += interactiveResult.failed;
        failedTests.addAll(interactiveResult.failedTests);
      }

      if (totalFailed > 0) {
        final summaryNames = failedTests.toSet().toList();
        final joined =
            summaryNames.isEmpty ? '' : ': ${summaryNames.join(', ')}';
        fail('$totalFailed test case(s) failed$joined');
      }
    });
  });
}

/// Wait for a finder to find at least one widget
/// Returns the finder once it finds widgets, or throws after timeout
Future<Finder> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 3),
  Duration interval = const Duration(milliseconds: 100),
}) async {
  final DateTime endTime = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(endTime)) {
    await tester.pump(interval);
    if (finder.evaluate().isNotEmpty) {
      return finder;
    }
  }
  throw Exception('Timed out waiting for ${finder.description}');
}

Duration _parseWaitTimeMs(
  Map<String, dynamic> step, {
  int defaultMs = 3000,
}) {
  final dynamic waitTime = step['waitTime'];

  if (waitTime is int) {
    return Duration(milliseconds: waitTime);
  }

  if (waitTime is String) {
    final parsed = int.tryParse(waitTime);
    if (parsed != null) {
      return Duration(milliseconds: parsed);
    }
  }

  return Duration(milliseconds: defaultMs);
}

Future<Finder> _obtainFinder(
  WidgetTester tester,
  Map<String, dynamic> step, {
  Finder? fallback,
}) async {
  final selector = step['selector'] as String?;
  final alias = (step['alias'] as String?)?.trim();

  Finder? finder;

  if (selector != null && selector.isNotEmpty) {
    finder = _parseFinder(tester, selector);
  } else if (alias != null && alias.isNotEmpty) {
    finder = _storedFinders[alias];
    if (finder == null && fallback != null) {
      finder = fallback;
    }
  } else if (fallback != null) {
    finder = fallback;
  }

  if (finder == null) {
    if (alias != null && alias.isNotEmpty) {
      throw Exception('Finder alias "$alias" has not been registered yet.');
    }
    throw Exception('Step must provide a selector or registered alias.');
  }

  try {
    final waitDuration = _parseWaitTimeMs(step);
    await _waitForFinder(
      tester,
      finder,
      timeout: waitDuration,
    );
  } catch (e) {
    log("wait for finder failed: ${selector}");
    rethrow;
  }
  final indexMatch = RegExp(r'\[(\d+)\]$').firstMatch(selector!);
  if (indexMatch != null) {
    int index = int.parse(indexMatch.group(1)!);
    finder = finder.at(index);
  }
  if (alias != null && alias.isNotEmpty) {
    _storedFinders[alias] = finder;
  }
  return finder;
}

Future<void> _executeStep(
    WidgetTester tester, Map<String, dynamic> step) async {
  final action = step['action'] as String;

  switch (action.toLowerCase()) {
    case 'wait':
      final waitDuration = _parseWaitTimeMs(step, defaultMs: 1000);
      await Future.delayed(waitDuration);
      await tester.pumpAndSettle();
      break;

    case 'click':
      await _clickElement(tester, step);
      await tester.pumpAndSettle();
      break;

    case 'type':
    case 'input':
      await _typeText(tester, step);
      await tester.pumpAndSettle();
      break;

    case 'assert_text':
    case 'verify_text':
      await _assertText(tester, step);
      break;

    case 'assert_visible':
    case 'verify_visible':
      await _assertVisible(tester, step);
      break;

    default:
      print('  Warning: Unknown action "$action"');
  }
}

Future<void> _clickElement(
    WidgetTester tester, Map<String, dynamic> step) async {
  final finder = await _obtainFinder(tester, step);
  await tester.tap(finder.first, warnIfMissed: false);
}

Future<void> _typeText(WidgetTester tester, Map<String, dynamic> step) async {
  final value = step['value'] as String;
  final selector = step['selector'] as String?;
  final fallback =
      selector == null || selector.isEmpty ? find.byType(TextFormField) : null;

  final finder = await _obtainFinder(tester, step, fallback: fallback);
  await tester.enterText(finder.first, value);
}

Future<void> _assertText(WidgetTester tester, Map<String, dynamic> step) async {
  final expected = step['expected'] as String;
  final selector = step['selector'] as String?;

  final fallback =
      selector == null || selector.isEmpty ? find.text(expected) : null;

  final finder = await _obtainFinder(tester, step, fallback: fallback);

  // Verify text content if a specific element was selected
  final hasSpecificTarget = (selector != null && selector.isNotEmpty) ||
      ((step['alias'] as String?)?.isNotEmpty ?? false);

  if (hasSpecificTarget) {
    final element = finder.evaluate().first;
    final text = _extractText(element);
    expect(text, contains(expected));
  }
}

Future<void> _assertVisible(
    WidgetTester tester, Map<String, dynamic> step) async {
  final finder = await _obtainFinder(tester, step);
}

Future<_SuiteResult> _runDslTestSuite(
  WidgetTester tester,
  Map<String, dynamic> testSuite, {
  String? suiteLabel,
  String? defaultSourceFile,
}) async {
  final suiteName =
      suiteLabel ?? testSuite['name'] as String? ?? 'Dynamic Suite';
  final rawTestCases = (testSuite['testCases'] as List?) ?? const [];
  int passed = 0;
  int failed = 0;
  final failedTests = <String>[];
  String? currentFile;
  final fallbackSource =
      defaultSourceFile ?? testSuite['_source'] as String? ?? suiteName;

  for (int index = 0; index < rawTestCases.length; index++) {
    final rawCase = rawTestCases[index];
    if (rawCase is! Map) {
      final label = 'Test case #${index + 1}';
      log('❌ $label is not a map. Skipping.');
      failed++;
      failedTests.add(label);
      continue;
    }

    final testCase =
        Map<String, dynamic>.from(rawCase as Map<Object?, Object?>);
    final sourceFile =
        (testCase['_sourceFile'] as String?) ?? fallbackSource ?? suiteName;
    if (sourceFile != null && sourceFile != currentFile) {
      currentFile = sourceFile;
      log('\n${'=' * 60}');
      log('Running tests from: $sourceFile');
      log('=' * 60);
      logData(DslLogEventType.sourceFile, {
        'path': sourceFile,
      });
    }

    final description =
        (testCase['description'] as String?) ?? 'Test case ${index + 1}';
    log('Running test case: $description');
    logData(DslLogEventType.testCaseStart, {
      'description': description,
      if (currentFile != null) 'sourceFile': currentFile,
    });

    try {
      final rawSteps = (testCase['steps'] as List?) ?? const [];
      for (int stepIndex = 0; stepIndex < rawSteps.length; stepIndex++) {
        final rawStep = rawSteps[stepIndex];
        if (rawStep is! Map) {
          log('  ⚠️ Step ${stepIndex + 1} has unexpected format (${rawStep.runtimeType}). Skipping.');
          continue;
        }

        final step =
            Map<String, dynamic>.from(rawStep as Map<Object?, Object?>);
        log('  Step ${stepIndex + 1}/${rawSteps.length}: ${step['action']}');

        try {
          await _executeStep(tester, step);
        } catch (e) {
          log('  ✗ Step failed: $e');
          rethrow;
        }
      }

      log('✅ Test case "$description" passed');
      logData(DslLogEventType.testCaseResult, {
        'description': description,
        'status': 'passed',
        if (currentFile != null) 'sourceFile': currentFile,
      });
      passed++;
    } catch (e, stackTrace) {
      log('❌ Test case "$description" failed');
      if (kDebugMode) {
        log('  Debug: $e');
        log('  Stack trace: $stackTrace');
      }
      failed++;
      failedTests.add(description);
      logData(DslLogEventType.testCaseResult, {
        'description': description,
        'status': 'failed',
        'reason': e.toString(),
        if (currentFile != null) 'sourceFile': currentFile,
      });
    }
  }

  log('=' * 60);
  log('TEST SUMMARY ($suiteName)');
  log('=' * 60);
  log('Total: ${passed + failed}');
  log('Passed: $passed');
  log('Failed: $failed');
  if (failedTests.isNotEmpty) {
    log('');
    log('Failed tests:');
    for (final test in failedTests) {
      log('  - $test');
    }
  }
  log('=' * 60);

  logData(DslLogEventType.summary, {
    'passed': passed,
    'failed': failed,
    if (failedTests.isNotEmpty) 'failedTests': failedTests,
  });

  return _SuiteResult(
    passed: passed,
    failed: failed,
    failedTests: failedTests,
  );
}

Future<_SuiteResult> _runInteractiveSessions(WidgetTester tester) async {
  if (_interactiveServerUrl.isEmpty) {
    log('Interactive session enabled but DSL_SERVER_URL is not set. Skipping dynamic test listener.');
    return const _SuiteResult(
      passed: 0,
      failed: 0,
      failedTests: <String>[],
    );
  }

  log('\n${'=' * 60}');
  log('Interactive DSL session enabled. Waiting for dynamic test suites...');
  log('Server endpoint: $_interactiveServerUrl');
  log('Send "$_interactiveExitCommand" to terminate the session.');
  log('=' * 60);

  final client = http.Client();
  int suiteIndex = 1;
  int passed = 0;
  int failed = 0;
  final failedTests = <String>[];

  try {
    while (true) {
      final payload = await _fetchDynamicSuite(client);
      if (payload == null) {
        await Future.delayed(_interactivePollInterval);
        continue;
      }

      if (payload.shouldExit) {
        log('Received exit command. Ending interactive session.');
        break;
      }

      Map<String, dynamic> suite;
      try {
        suite = _prepareDynamicSuite(payload.suite!, suiteIndex);
      } catch (e) {
        log('Failed to prepare dynamic suite #$suiteIndex: $e');
        continue;
      }
      log('\n${'=' * 60}');
      log('Running dynamic suite #$suiteIndex: ${suite['name']}');
      log('=' * 60);

      _storedFinders.clear();
      final result = await _runDslTestSuite(
        tester,
        suite,
        suiteLabel: suite['name'] as String?,
        defaultSourceFile: suite['_source'] as String?,
      );
      passed += result.passed;
      failed += result.failed;
      failedTests.addAll(result.failedTests);

      suiteIndex++;
      await tester.pumpAndSettle();
    }
  } finally {
    client.close();
    _storedFinders.clear();
  }

  log('\nInteractive session summary: passed $passed, failed $failed');

  return _SuiteResult(
    passed: passed,
    failed: failed,
    failedTests: failedTests,
  );
}

Future<_DynamicSuitePayload?> _fetchDynamicSuite(http.Client client) async {
  try {
    final uri = Uri.parse(_interactiveServerUrl);
    final response = await client.get(uri);

    if (response.statusCode == 204) {
      return null;
    }

    if (response.statusCode != 200) {
      log('Dynamic DSL server responded with status ${response.statusCode}. Retrying...');
      return null;
    }

    final payload = response.body.trim();
    if (payload.isEmpty) {
      return null;
    }

    if (payload.toLowerCase() == _interactiveExitCommand.toLowerCase()) {
      return const _DynamicSuitePayload.exit();
    }

    final suite = _decodeDslPayload(payload);
    return _DynamicSuitePayload.data(suite);
  } catch (e, stackTrace) {
    log('Failed to fetch dynamic test suite: $e');
    if (kDebugMode) {
      log('  Stack trace: $stackTrace');
    }
    return null;
  }
}

Map<String, dynamic> _prepareDynamicSuite(
    Map<String, dynamic> suite, int suiteIndex) {
  final prepared = Map<String, dynamic>.from(suite);
  prepared['name'] ??= 'Dynamic Suite $suiteIndex';
  prepared['_source'] ??= 'dynamic_suite_$suiteIndex';

  final rawCases = (prepared['testCases'] as List?) ?? const [];
  final normalizedCases = <Map<String, dynamic>>[];
  for (int index = 0; index < rawCases.length; index++) {
    final rawCase = rawCases[index];
    if (rawCase is! Map) {
      throw FormatException(
          'Dynamic suite test case at index $index is not a map (${rawCase.runtimeType}).');
    }
    final caseMap = Map<String, dynamic>.from(rawCase as Map<Object?, Object?>);
    caseMap['_sourceFile'] ??= prepared['_source'];
    normalizedCases.add(caseMap);
  }

  prepared['testCases'] = normalizedCases;
  return prepared;
}

Map<String, dynamic> _decodeDslPayload(String payload) {
  final trimmed = payload.trim();
  dynamic decoded;

  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    decoded = jsonDecode(trimmed);
  } else {
    decoded = loadYaml(trimmed);
  }

  if (decoded is YamlMap || decoded is YamlList) {
    decoded = jsonDecode(jsonEncode(decoded));
  }

  if (decoded is List) {
    return {
      'name': 'Dynamic Suite',
      'testCases': decoded,
    };
  }

  if (decoded is Map) {
    final map = Map<String, dynamic>.from(decoded as Map<Object?, Object?>);
    map['name'] ??= 'Dynamic Suite';

    if (!map.containsKey('testCases')) {
      if (map.containsKey('steps')) {
        final suiteName = map['name'] as String? ?? 'Dynamic Suite';
        final testCase =
            Map<String, dynamic>.from(map as Map<Object?, Object?>);
        testCase.remove('testCases');
        testCase.remove('_source');
        testCase.remove('name');
        return {
          'name': suiteName,
          'testCases': [testCase],
        };
      }
      throw FormatException('Dynamic suite is missing "testCases".');
    }

    final rawCases = map['testCases'];
    if (rawCases is! List) {
      throw FormatException('Dynamic suite "testCases" must be a list.');
    }

    map['testCases'] = rawCases
        .map<Map<String, dynamic>>(
            (caseData) => Map<String, dynamic>.from(caseData as Map))
        .toList();

    return map;
  }

  throw FormatException(
      'Unsupported dynamic suite payload type: ${decoded.runtimeType}');
}

class _DynamicSuitePayload {
  const _DynamicSuitePayload.data(this.suite) : shouldExit = false;
  const _DynamicSuitePayload.exit()
      : suite = null,
        shouldExit = true;

  final Map<String, dynamic>? suite;
  final bool shouldExit;
}

/// Parse a selector string and return a Finder
///
/// Supported selector formats:
/// - Button Text - find by exact text (no prefix needed)
/// - contains:partial - find by partial text
/// - key:my-key - find by key
/// - type:ElevatedButton - find by widget type
Finder _parseFinder(WidgetTester tester, String selector) {
  // Extract index if present (e.g., "Button[0]" -> index: 0, selector: "Button")
  int? index;
  String cleanSelector = selector;

  final indexMatch = RegExp(r'\[(\d+)\]$').firstMatch(selector);
  if (indexMatch != null) {
    cleanSelector = selector.substring(0, indexMatch.start);
  }

  Finder finder;

  if (cleanSelector.contains(':')) {
    final parts = cleanSelector.split(':');
    final selectorType = parts[0];
    final selectorValue = parts.sublist(1).join(':'); // Handle colons in value

    switch (selectorType) {
      case 'contains':
        finder = find.textContaining(selectorValue);
        break;
      case 'label':
        finder = find.bySemanticsLabel(selectorValue);
        break;
      case 'key':
        finder = find.byKey(Key(selectorValue));
        break;
      case 'type':
        finder = _findByTypeName(selectorValue);
        break;
      case 'alias':
        final cachedFinder = _storedFinders[selectorValue];
        if (cachedFinder == null) {
          throw Exception(
              'Finder alias "$selectorValue" has not been registered yet.');
        }
        finder = cachedFinder;
        break;
      default:
        print('  Warning: Unknown selector type "$selectorType"');
        finder = find.text(cleanSelector); // Fallback to text search
    }
  } else {
    // No colon found - treat as plain text selector
    finder = find.text(cleanSelector);
  }

  return finder;
}

Finder _findByTypeName(String typeName) {
  // Map common widget type names to actual types
  switch (typeName) {
    case 'ElevatedButton':
      return find.byType(ElevatedButton);
    case 'TextButton':
      return find.byType(TextButton);
    case 'OutlinedButton':
      return find.byType(OutlinedButton);
    case 'IconButton':
      return find.byType(IconButton);
    case 'TextField':
      return find.byType(TextField);
    case 'TextFormField':
      return find.byType(TextFormField);
    case 'Checkbox':
      return find.byType(Checkbox);
    case 'Radio':
      return find.byType(Radio);
    case 'Switch':
      return find.byType(Switch);
    default:
      // Return a finder that won't match anything
      return find.byType(Widget);
  }
}

String _extractText(Element element) {
  final widget = element.widget;
  if (widget is Text) {
    if (widget.data != null) {
      return widget.data!;
    }
    final textSpan = widget.textSpan;
    if (textSpan != null) {
      return textSpan.toPlainText();
    }
    return '';
  } else if (widget is RichText) {
    return widget.text.toPlainText();
  }
  // Try to find text in children
  String nestedText = '';
  element.visitChildren((child) {
    if (nestedText.isEmpty) {
      nestedText = _extractText(child);
    }
  });
  return nestedText;
}

@visibleForTesting
Finder debugParseFinder(WidgetTester tester, String selector) =>
    _parseFinder(tester, selector);

@visibleForTesting
String debugExtractText(Element element) => _extractText(element);

/// Capture screenshot on test failure
Future<void> _captureScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  String testCaseName,
  String stepName,
) async {
  print('  Attempting to capture screenshot...');
  try {
    // Generate filename with timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sanitizedTestName =
        testCaseName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final sanitizedStepName =
        stepName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final filename = '${timestamp}_${sanitizedTestName}_$sanitizedStepName';

    print('  Screenshot filename: $filename');

    // Take screenshot using integration test binding
    // On web, screenshots are handled by the WebDriver via driver callback
    final result = await binding.takeScreenshot(filename);

    print('📸 Screenshot captured: $filename (result: $result)');
  } catch (e, stackTrace) {
    print('  Warning: Failed to capture screenshot: $e');
    print('  Stack trace: $stackTrace');
  }
}
