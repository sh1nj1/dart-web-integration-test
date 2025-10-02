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
void log(Object? message) => log('$message');

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

      for (final testCase in testCases) {
        log('\n' + Executing test case: ${testCase['name']}');
        
        try {
          // Navigate to URL if specified by clicking the navigation button
          if (testCase['url'] != null) {
            final url = testCase['url'] as String;
            final route = _extractRoute(url);
            if (route.isNotEmpty && route != '/') {
              // Navigate by clicking the appropriate button
              await _navigateToRoute(tester, route);
              await tester.pumpAndSettle();
            }
          }

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
              // await _captureScreenshot(binding, testCase['name'], 'step_${i + 1}_${step['action']}_failure');
              rethrow;
            }
          }

          log('✓ Test case "${testCase['name']}" passed');
          passed++;
        } catch (e) {
          log('✗ Test case "${testCase['name']}" failed');
          failed++;
          failedTests.add(testCase['name']);
        }
      }
      
      // Print test summary
      log('\n' + '=' * 60);
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

String _extractRoute(String url) {
  final uri = Uri.parse(url);
  final fragment = uri.fragment;
  return fragment.isEmpty ? uri.path : fragment;
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

    case 'navigate':
      final route = step['value'] as String;
      await _navigateToRoute(tester, route);
      await tester.pumpAndSettle();
      break;

    default:
      print('  Warning: Unknown action "$action"');
  }
}

Future<void> _clickElement(WidgetTester tester, Map<String, dynamic> step) async {
  final selector = step['selector'] as String?;
  if (selector == null) return;

  final finder = _parseFinder(tester, selector);
  expect(finder, findsWidgets);
  await tester.tap(finder.first);
}

Future<void> _typeText(WidgetTester tester, Map<String, dynamic> step) async {
  final value = step['value'] as String;
  final selector = step['selector'] as String?;

  final finder = selector != null 
      ? _parseFinder(tester, selector)
      : find.byType(TextFormField).first;

  expect(finder, findsWidgets);
  await tester.enterText(finder, value);
}

Future<void> _assertText(WidgetTester tester, Map<String, dynamic> step) async {
  final expected = step['expected'] as String;
  final selector = step['selector'] as String?;

  final finder = selector != null 
      ? _parseFinder(tester, selector)
      : find.text(expected);

  expect(finder, findsWidgets);
  
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
  expect(finder, findsWidgets);
}

/// Parse a selector string and return a Finder
/// 
/// Supported selector formats:
/// - text:Button Text - find by text
/// - key:my-key - find by key
/// - type:ElevatedButton - find by widget type
/// - index:2 - find by index (combined with type)
/// - Contains patterns for backward compatibility
Finder _parseFinder(WidgetTester tester, String selector) {
  // New explicit selector format: type:value
  if (selector.contains(':')) {
    final parts = selector.split(':');
    final selectorType = parts[0];
    final selectorValue = parts.sublist(1).join(':'); // Handle colons in value
    
    switch (selectorType) {
      case 'text':
        return find.text(selectorValue);
      case 'textContains':
        return find.textContaining(selectorValue);
      case 'key':
        return find.byKey(Key(selectorValue));
      case 'type':
        return _findByTypeName(selectorValue);
      default:
        print('  Warning: Unknown selector type "$selectorType"');
    }
  }
  
  // Legacy/implicit selectors for backward compatibility
  // Try to guess the intent from the selector string
  
  // Check for aria-label pattern (semantic web selectors)
  if (selector.contains('aria-label')) {
    final ariaLabel = _extractAriaLabel(selector);
    return find.text(ariaLabel);
  }
  
  // Check for key pattern
  if (selector.contains('[key=')) {
    final keyMatch = RegExp(r"\[key='([^']+)'\]").firstMatch(selector);
    if (keyMatch != null) {
      return find.byKey(Key(keyMatch.group(1)!));
    }
  }
  
  // Default: try to find as text
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

String _extractAriaLabel(String selector) {
  final regex = RegExp(r"aria-label='([^']+)'");
  final match = regex.firstMatch(selector);
  return match?.group(1) ?? '';
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

Future<void> _navigateToRoute(WidgetTester tester, String route) async {
  // Extract route name from URL patterns
  final routeName = route.replaceAll('/#', '').replaceAll('#', '');
  
  // Try to find and click navigation button by route name
  // This assumes navigation buttons have text matching the route
  final routeParts = routeName.split('/').where((p) => p.isNotEmpty).toList();
  
  if (routeParts.isEmpty) {
    // Navigate to home
    final finder = find.text('Home');
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder.first);
      return;
    }
  } else {
    // Try to find button with capitalized route name
    final routeText = routeParts.first[0].toUpperCase() + 
                     routeParts.first.substring(1);
    final finder = find.text(routeText);
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder.first);
      return;
    }
  }
  
  log('  Warning: Could not navigate to route "$route"');
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
