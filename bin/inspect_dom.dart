import 'dart:io';
import 'package:webdriver/sync_io.dart';

void main() async {
  // ChromeDriver 시작
  print('Starting ChromeDriver...');
  final chromeDriverProcess = await Process.start(
    './drivers/chromedriver',
    ['--port=4444'],
    workingDirectory: Directory.current.path,
  );

  await Future.delayed(Duration(seconds: 2));

  try {
    print('Creating WebDriver instance...');
    final driver = createDriver(
      uri: Uri.parse('http://localhost:4444/'),
      desired: {
        'browserName': 'chrome',
        'goog:chromeOptions': {
          'args': ['--headless', '--no-sandbox', '--disable-dev-shm-usage']
        }
      },
    );

    print('Navigating to http://localhost:3001/#/...');
    driver.get('http://localhost:3001/#/');
    
    await Future.delayed(Duration(seconds: 5));

    print('\n=== Page Source ===');
    final pageSource = driver.pageSource;
    print(pageSource);

    print('\n=== Finding elements ===');
    
    // flt-semantics 찾기
    try {
      final semantics = driver.findElements(By.tagName('flt-semantics'));
      print('Found ${semantics.length} flt-semantics elements');
      for (var i = 0; i < semantics.length && i < 10; i++) {
        final elem = semantics[i];
        final ariaLabel = elem.attributes['aria-label'];
        final role = elem.attributes['role'];
        print('  [$i] aria-label: $ariaLabel, role: $role');
      }
    } catch (e) {
      print('Error finding flt-semantics: $e');
    }

    // input 찾기
    try {
      final inputs = driver.findElements(By.tagName('input'));
      print('\nFound ${inputs.length} input elements');
    } catch (e) {
      print('Error finding inputs: $e');
    }

    driver.quit();
  } finally {
    chromeDriverProcess.kill();
  }
}
