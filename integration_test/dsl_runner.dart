import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:test_target/main.dart' as app;

// Import generated test DSL data
import 'test_dsl_data.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Flutter Web Integration Test', () {
    late Map<String, dynamic> testSuite;

    setUpAll(() async {
      // Load test DSL from generated Dart code
      testSuite = jsonDecode(testDslJson);
      print('Loaded test suite: ${testSuite['name']}');
    });

    testWidgets('Run DSL tests', (WidgetTester tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle();

      final testCases = testSuite['testCases'] as List;

      for (final testCase in testCases) {
        print('\nExecuting test case: ${testCase['name']}');
        
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
          print('  Executing step ${i + 1}: ${step['action']}');
          
          await _executeStep(tester, step);
        }

        print('✓ Test case "${testCase['name']}" passed');
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

  Finder finder;

  // Try to find by text content (for buttons)
  if (selector.contains('About')) {
    finder = find.text('About');
  } else if (selector.contains('Contact')) {
    finder = find.text('Contact');
  } else if (selector.contains('Home')) {
    finder = find.text('Home');
  } else if (selector.contains('Send Message')) {
    finder = find.text('Send Message');
  } else {
    // Try to find by button role
    finder = find.byType(ElevatedButton);
  }

  expect(finder, findsWidgets);
  await tester.tap(finder.first);
}

Future<void> _typeText(WidgetTester tester, Map<String, dynamic> step) async {
  final value = step['value'] as String;
  final selector = step['selector'] as String?;

  Finder finder;

  if (selector != null) {
    // Find by key if available
    if (selector.contains('name')) {
      finder = find.byKey(const Key('name-input'));
    } else if (selector.contains('email')) {
      finder = find.byKey(const Key('email-input'));
    } else if (selector.contains('message')) {
      finder = find.byKey(const Key('message-input'));
    } else if (selector.contains('input')) {
      // Find first available TextField
      finder = find.byType(TextFormField).first;
    } else if (selector.contains('textarea')) {
      // Find TextField with maxLines > 1 by using Key
      finder = find.byKey(const Key('message-input'));
    } else {
      finder = find.byType(TextFormField).first;
    }
  } else {
    finder = find.byType(TextFormField).first;
  }

  expect(finder, findsWidgets);
  await tester.enterText(finder, value);
}

Future<void> _assertText(WidgetTester tester, Map<String, dynamic> step) async {
  final expected = step['expected'] as String;
  final selector = step['selector'] as String?;

  // For semantics-based selectors, look for the text directly
  if (selector != null && selector.contains('aria-label')) {
    final ariaLabel = _extractAriaLabel(selector);
    final finder = find.text(ariaLabel);
    expect(finder, findsWidgets);
  } else {
    // Just find the text
    final finder = find.text(expected);
    expect(finder, findsWidgets);
  }
}

Future<void> _assertVisible(WidgetTester tester, Map<String, dynamic> step) async {
  final selector = step['selector'] as String?;
  
  if (selector != null && selector.contains('Thank you')) {
    final finder = find.textContaining('Thank you');
    expect(finder, findsWidgets);
  }
}

String _extractAriaLabel(String selector) {
  final regex = RegExp(r"aria-label='([^']+)'");
  final match = regex.firstMatch(selector);
  return match?.group(1) ?? '';
}

Future<void> _navigateToRoute(WidgetTester tester, String route) async {
  // Navigate by clicking the navigation button based on route
  switch (route) {
    case '/':
    case '/#/':
      final finder = find.text('Home');
      if (finder.evaluate().isNotEmpty) {
        await tester.tap(finder.first);
      }
      break;
    case '/about':
    case '/#/about':
      final finder = find.text('About');
      if (finder.evaluate().isNotEmpty) {
        await tester.tap(finder.first);
      }
      break;
    case '/contact':
    case '/#/contact':
      final finder = find.text('Contact');
      if (finder.evaluate().isNotEmpty) {
        await tester.tap(finder.first);
      }
      break;
    default:
      print('  Warning: Unknown route "$route"');
  }
}
