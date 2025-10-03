import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/dsl_runner.dart' as dsl;

void main() {
  group('dsl_runner selector parsing', () {
    testWidgets('supports basic selectors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Text('Hello World'),
                const Text('Hello Flutter'),
                const SizedBox(key: Key('sized-box')),
                ElevatedButton(
                  onPressed: () {},
                  child: const Text('Action'),
                ),
                ElevatedButton(
                  onPressed: () {},
                  child: const Text('Action'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(dsl.debugParseFinder(tester, 'Hello World'), findsOneWidget);
      expect(dsl.debugParseFinder(tester, 'contains:Flutter'), findsOneWidget);
      expect(dsl.debugParseFinder(tester, 'key:sized-box'), findsOneWidget);
      expect(
        dsl.debugParseFinder(tester, 'type:ElevatedButton'),
        findsNWidgets(2),
      );
    });

    testWidgets('applies index suffix', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: const [
                Text('Item 0'),
                Text('Item 1'),
              ],
            ),
          ),
        ),
      );

      final finder = dsl.debugParseFinder(tester, 'contains:Item[1]');
      expect(finder, findsOneWidget);
      expect(tester.widget<Text>(finder).data, 'Item 1');
    });
  });

  group('dsl_runner text extraction', () {
    testWidgets('reads text and rich text widgets', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Text('Plain Text'),
                Text.rich(
                  TextSpan(
                    text: 'Rich',
                    style: const TextStyle(color: Colors.black),
                    children: const [TextSpan(text: ' Text')],
                  ),
                ),
                const Text.rich(
                  TextSpan(
                    text: 'Nested ',
                    children: [TextSpan(text: 'Content')],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final plainElement = tester.element(find.text('Plain Text'));
      expect(dsl.debugExtractText(plainElement), 'Plain Text');

      final richElement = tester.element(find.text('Rich Text'));
      expect(dsl.debugExtractText(richElement), 'Rich Text');

      final nestedElement = tester.element(find.text('Nested Content'));
      expect(dsl.debugExtractText(nestedElement), 'Nested Content');
    });
  });
}
