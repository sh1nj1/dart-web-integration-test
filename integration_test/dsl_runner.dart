import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Import generated test DSL data
import 'test_dsl_data.dart';

// Import app-specific configuration (optional)
// If app_config.dart exists, it will be used to start the app
// Otherwise, the app must be running before tests start
import 'app_config.dart' as config;

// Custom print function with [DSL] prefix
void log(Object? message) => print('[DSL] $message');

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
        }
        
        log('Running test case: ${testCase['description']}');
        
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

          log('✅ Test case "${testCase['description']}" passed');
          passed++;
        } catch (e) {
          log('❌ Test case "${testCase['description']}" failed');
          failed++;
          failedTests.add(testCase['description']);
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

Future<void> _executeStep(WidgetTester tester, Map<String, dynamic> step) async {
  final action = step['action'] as String;

  switch (action.toLowerCase()) {
    case 'wait':
      final waitTime = step['waitTime'] as int? ?? 1000;
      await Future.delayed(Duration(milliseconds: waitTime));
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

Future<void> _clickElement(WidgetTester tester, Map<String, dynamic> step) async {
  final selector = step['selector'] as String?;
  if (selector == null) return;

  final finder = _parseFinder(tester, selector);
  await _waitForFinder(tester, finder);
  await tester.tap(finder.first);
}

Future<void> _typeText(WidgetTester tester, Map<String, dynamic> step) async {
  final value = step['value'] as String;
  final selector = step['selector'] as String?;

  final finder = selector != null 
      ? _parseFinder(tester, selector)
      : find.byType(TextFormField);

  await _waitForFinder(tester, finder);
  await tester.enterText(finder.first, value);
}

Future<void> _assertText(WidgetTester tester, Map<String, dynamic> step) async {
  final expected = step['expected'] as String;
  final selector = step['selector'] as String?;

  final finder = selector != null 
      ? _parseFinder(tester, selector)
      : find.text(expected);

  await _waitForFinder(tester, finder);
  
  // Verify text content if a specific element was selected
  if (selector != null) {
    final element = finder.evaluate().first;
    final text = _extractText(element);
    expect(text, contains(expected));
  }
}

Future<void> _assertVisible(WidgetTester tester, Map<String, dynamic> step) async {
  final selector = step['selector'] as String?;
  if (selector == null) return;
  
  final finder = _parseFinder(tester, selector);
  await _waitForFinder(tester, finder);
}

/// Parse a selector string and return a Finder
/// 
/// Supported selector formats:
/// - Button Text - find by exact text (no prefix needed)
/// - contains:partial - find by partial text
/// - key:my-key - find by key
/// - type:ElevatedButton - find by widget type
Finder _parseFinder(WidgetTester tester, String selector) {
  if (selector.contains(':')) {
    final parts = selector.split(':');
    final selectorType = parts[0];
    final selectorValue = parts.sublist(1).join(':'); // Handle colons in value
    
    switch (selectorType) {
      case 'contains':
        return find.textContaining(selectorValue);
      case 'label':
        finder = find.bySemanticsLabel(selectorValue);
        break;
      case 'key':
        return find.byKey(Key(selectorValue));
      case 'type':
        return _findByTypeName(selectorValue);
      default:
        print('  Warning: Unknown selector type "$selectorType"');
        return find.text(selector); // Fallback to text search
    }
  }
  
  // No colon found - treat as plain text selector
  return find.text(selector);
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
    return widget.data ?? '';
  } else if (widget is RichText) {
    return widget.text.toPlainText();
  }
  // Try to find text in children
  return '';
}


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
    final sanitizedTestName = testCaseName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final sanitizedStepName = stepName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
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
