import 'package:webdriver/io.dart';
import 'test_dsl_parser.dart';
import 'screenshot_manager.dart';

class TestExecutor {
  final WebDriver driver;
  final ScreenshotManager screenshotManager;
  final bool captureScreenshotsOnFailure;
  final bool captureStepScreenshots;
  final int defaultWaitTimeout;
  
  TestExecutor(
    this.driver, {
    ScreenshotManager? screenshotManager,
    this.captureScreenshotsOnFailure = true,
    this.captureStepScreenshots = false,
    this.defaultWaitTimeout = 5000, // 기본 5초 대기
  }) : screenshotManager = screenshotManager ?? ScreenshotManager();
  
  /// Initialize the test executor and set implicit wait
  Future<void> initialize() async {
    // Set implicit wait timeout
    await driver.timeouts.setImplicitTimeout(Duration(milliseconds: defaultWaitTimeout));
  }
  
  Future<bool> executeTestCase(TestCase testCase, String baseUrl) async {
    print('Executing test case: ${testCase.name}');
    
    try {
      // Navigate to URL if specified, otherwise use base URL
      final targetUrl = testCase.url ?? baseUrl;
      await driver.get(targetUrl);
      
      // Enable Flutter accessibility for CanvasKit renderer
      await _enableFlutterAccessibility();
      
      // Execute each step
      for (int i = 0; i < testCase.steps.length; i++) {
        final step = testCase.steps[i];
        try {
          await executeStep(step, testCase.name, i);
          
          // Capture step screenshot if enabled
          if (captureStepScreenshots) {
            await screenshotManager.captureStepScreenshot(
              driver, 
              testCase.name, 
              step.action,
              i + 1,
            );
          }
        } catch (stepError) {
          // Capture failure screenshot
          if (captureScreenshotsOnFailure) {
            await screenshotManager.captureFailureScreenshot(
              driver,
              testCase.name,
              step.action,
              stepError.toString(),
            );
          }
          rethrow;
        }
      }
      
      print('✓ Test case "${testCase.name}" passed');
      return true;
    } catch (e) {
      print('✗ Test case "${testCase.name}" failed: $e');
      
      // Capture final failure screenshot if not already captured
      if (captureScreenshotsOnFailure) {
        await screenshotManager.captureFailureScreenshot(
          driver,
          testCase.name,
          'test_failure',
          e.toString(),
        );
      }
      
      return false;
    }
  }
  
  Future<void> executeStep(TestStep step, String testCaseName, int stepIndex) async {
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
  
  /// Enable Flutter accessibility for CanvasKit renderer
  /// This makes DOM elements available for Selenium to interact with
  Future<void> _enableFlutterAccessibility() async {
    try {
      // Click the "Enable accessibility" button using JavaScript
      // The button is positioned off-screen, so regular click won't work
      final result = await driver.execute('''
        const button = document.querySelector('flt-semantics-placeholder[aria-label="Enable accessibility"]');
        if (button) {
          button.click();
          return true;
        }
        return false;
      ''', []);
      
      // Wait for accessibility tree to be built
      await Future.delayed(Duration(milliseconds: 3000));
      
      // Debug: Check what elements are available
      final debugInfo = await driver.execute('''
        const semantics = document.querySelectorAll('flt-semantics');
        const inputs = document.querySelectorAll('input');
        const textareas = document.querySelectorAll('textarea');
        
        return {
          semanticsCount: semantics.length,
          inputsCount: inputs.length,
          textareasCount: textareas.length,
          semanticsSample: Array.from(semantics).slice(0, 5).map(el => ({
            ariaLabel: el.getAttribute('aria-label'),
            role: el.getAttribute('role'),
            tagName: el.tagName
          }))
        };
      ''', []);
      
      print('  ✓ Flutter accessibility enabled');
      print('  Debug: $debugInfo');
    } catch (e) {
      print('  Note: Could not enable Flutter accessibility: $e');
    }
  }
}
