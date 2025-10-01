import 'package:webdriver/io.dart';
import 'test_dsl_parser.dart';

class TestExecutor {
  final WebDriver driver;
  
  TestExecutor(this.driver);
  
  Future<bool> executeTestCase(TestCase testCase, String baseUrl) async {
    print('Executing test case: ${testCase.name}');
    
    try {
      // Navigate to URL if specified, otherwise use base URL
      final targetUrl = testCase.url ?? baseUrl;
      await driver.get(targetUrl);
      
      // Execute each step
      for (final step in testCase.steps) {
        await executeStep(step);
      }
      
      print('✓ Test case "${testCase.name}" passed');
      return true;
    } catch (e) {
      print('✗ Test case "${testCase.name}" failed: $e');
      return false;
    }
  }
  
  Future<void> executeStep(TestStep step) async {
    print('  Executing step: ${step.action}');
    
    switch (step.action.toLowerCase()) {
      case 'click':
        if (step.selector != null) {
          final element = await driver.findElement(By.cssSelector(step.selector!));
          await element.click();
        }
        break;
        
      case 'type':
      case 'input':
        if (step.selector != null && step.value != null) {
          final element = await driver.findElement(By.cssSelector(step.selector!));
          await element.clear();
          await element.sendKeys(step.value!);
        }
        break;
        
      case 'wait':
        final waitTime = step.waitTime ?? 1000;
        await Future.delayed(Duration(milliseconds: waitTime));
        break;
        
      case 'assert_text':
      case 'verify_text':
        if (step.selector != null && step.expected != null) {
          final element = await driver.findElement(By.cssSelector(step.selector!));
          final actualText = await element.text;
          if (actualText != step.expected) {
            throw Exception('Text assertion failed. Expected: "${step.expected}", Actual: "$actualText"');
          }
        }
        break;
        
      case 'assert_visible':
      case 'verify_visible':
        if (step.selector != null) {
          final element = await driver.findElement(By.cssSelector(step.selector!));
          final isDisplayed = await element.displayed;
          if (!isDisplayed) {
            throw Exception('Element is not visible: ${step.selector}');
          }
        }
        break;
        
      case 'navigate':
        if (step.value != null) {
          await driver.get(step.value!);
        }
        break;
        
      default:
        print('  Warning: Unknown action "${step.action}"');
    }
    
    // Add delay if specified
    if (step.waitTime != null) {
      await Future.delayed(Duration(milliseconds: step.waitTime!));
    }
  }
}
