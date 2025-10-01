import 'dart:io';
import 'package:webdriver/sync_io.dart';

void main() async {
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
          'args': ['--no-sandbox', '--disable-dev-shm-usage']
        }
      },
    );

    print('Navigating to http://localhost:3001/#/...');
    driver.get('http://localhost:3001/#/');
    
    print('Waiting for page to load...');
    await Future.delayed(Duration(seconds: 3));

    print('\n=== Enabling accessibility ===');
    try {
      final accessibilityButton = driver.findElement(
        By.cssSelector('flt-semantics-placeholder[aria-label="Enable accessibility"]')
      );
      accessibilityButton.click();
      print('Clicked accessibility button');
      
      await Future.delayed(Duration(milliseconds: 3000));
      
      print('\n=== After enabling accessibility ===');
      
      // Look for flt-semantics elements
      final semanticsElements = driver.execute('''
        const semantics = document.querySelectorAll('flt-semantics');
        return Array.from(semantics).slice(0, 20).map(el => ({
          tag: el.tagName,
          role: el.getAttribute('role'),
          ariaLabel: el.getAttribute('aria-label'),
          innerText: el.innerText ? el.innerText.substring(0, 50) : null
        }));
      ''', []);
      
      print('Semantics elements:');
      print(semanticsElements);
      
      // Check semantics host
      final semanticsHost = driver.execute('''
        const host = document.querySelector('flt-semantics-host');
        if (host) {
          return {
            found: true,
            childrenCount: host.children.length,
            innerHTML: host.innerHTML.substring(0, 2000)
          };
        }
        return { found: false };
      ''', []);
      
      print('\nSemantics host:');
      print(semanticsHost);
      
      // Save DOM
      final file = File('./dom_after_accessibility.html');
      await file.writeAsString(driver.pageSource);
      print('\nPage source saved to: ${file.absolute.path}');
      
    } catch (e) {
      print('Error: $e');
    }

    print('\nPress Enter to close...');
    stdin.readLineSync();
    
    driver.quit();
  } finally {
    chromeDriverProcess.kill();
  }
}
