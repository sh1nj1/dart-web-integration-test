import 'dart:io';
import '../lib/chrome_driver_manager.dart';
import '../lib/test_dsl_parser.dart';
import '../lib/test_executor.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/run_tests.dart <test-dsl-file>');
    exit(1);
  }
  
  final testDslFile = args[0];
  final driverManager = ChromeDriverManager();
  
  try {
    print('Starting ChromeDriver...');
    await driverManager.startDriver();
    
    print('Creating WebDriver instance...');
    final driver = await driverManager.createWebDriver(headless: false);
    
    print('Loading test suite from: $testDslFile');
    final testSuite = await TestSuite.loadFromFile(testDslFile);
    
    print('Executing test suite: ${testSuite.name}');
    print('Base URL: ${testSuite.baseUrl}');
    
    final executor = TestExecutor(driver);
    int passed = 0;
    int failed = 0;
    
    for (final testCase in testSuite.testCases) {
      final result = await executor.executeTestCase(testCase, testSuite.baseUrl);
      if (result) {
        passed++;
      } else {
        failed++;
      }
    }
    
    print('\n=== Test Results ===');
    print('Total: ${passed + failed}');
    print('Passed: $passed');
    print('Failed: $failed');
    
    if (failed > 0) {
      exit(1);
    }
    
  } catch (e) {
    print('Error: $e');
    exit(1);
  } finally {
    print('Stopping ChromeDriver...');
    await driverManager.stopDriver();
  }
}
