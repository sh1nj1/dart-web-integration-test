import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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

/// Generic DSL test runner for Flutter integration tests
///
/// This runner does not depend on any specific app implementation.
/// To customize for your app:
/// 1. Create app_config.dart from app_config.dart.template
/// 2. Implement the startApp() function to launch your app
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

      final testCases = testSuite['testCases'] as List;
      int passed = 0;
      int failed = 0;
      final failedTests = <String>[];
      String? currentFile;

      for (final testCase in testCases) {
        // Log when switching to a new source file
        final sourceFile = testCase['_sourceFile'] as String?;
        if (sourceFile != null && sourceFile != currentFile) {
          currentFile = sourceFile;
          log('\n${'=' * 60}');
          log('Running tests from: $sourceFile');
          log('=' * 60);
          logData(DslLogEventType.sourceFile, {
            'path': sourceFile,
          });
        }

        final description = testCase['description'] as String;
        log('Running test case: $description');
        logData(DslLogEventType.testCaseStart, {
          'description': description,
          if (currentFile != null) 'sourceFile': currentFile,
        });

        try {
          // Execute steps
          final steps = testCase['steps'] as List;
          for (int i = 0; i < steps.length; i++) {
            final step = steps[i];
            log('  Step ${i + 1}/${steps.length}: ${step['action']}');

            try {
              await _executeStep(tester, step);
            } catch (e) {
              // Log failure (screenshot disabled for web compatibility)
              log('  ✗ Step failed: $e');
              // TODO: Re-enable when WebDriver screenshot works on web
              // await _captureScreenshot(binding, testCase['description'], 'step_${i + 1}_${step['action']}_failure');
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
        } catch (e) {
          log('❌ Test case "$description" failed');
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

      // Print test summary
      log('=' * 60);
      log('TEST SUMMARY');
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

      // Fail the test if any test case failed
      if (failed > 0) {
        fail('$failed test case(s) failed');
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
  final fallback = selector == null || selector.isEmpty
      ? find.byType(TextFormField)
      : null;

  final finder = await _obtainFinder(tester, step, fallback: fallback);
  await tester.enterText(finder.first, value);
}

Future<void> _assertText(WidgetTester tester, Map<String, dynamic> step) async {
  final expected = step['expected'] as String;
  final selector = step['selector'] as String?;

  final fallback = selector == null || selector.isEmpty
      ? find.text(expected)
      : null;

  final finder = await _obtainFinder(tester, step, fallback: fallback);

  // Verify text content if a specific element was selected
  final hasSpecificTarget =
      (selector != null && selector.isNotEmpty) ||
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
          throw Exception('Finder alias "$selectorValue" has not been registered yet.');
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
