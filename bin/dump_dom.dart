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
          'args': ['--headless', '--no-sandbox', '--disable-dev-shm-usage']
        }
      },
    );

    print('Navigating to http://localhost:3001/#/...');
    driver.get('http://localhost:3001/#/');
    
    print('Waiting for page to load...');
    await Future.delayed(Duration(seconds: 5));

    print('\n=== Getting page source ===');
    final pageSource = driver.pageSource;
    
    // Save to file
    final file = File('./dom_dump.html');
    await file.writeAsString(pageSource);
    print('Page source saved to: ${file.absolute.path}');

    print('\n=== Executing JavaScript to inspect Flutter ===');
    
    // Check window._flutter
    final flutterCheck = driver.execute('''
      return {
        hasFlutter: typeof window._flutter !== 'undefined',
        flutterKeys: window._flutter ? Object.keys(window._flutter) : [],
        hasFlutterLoader: window._flutter && typeof window._flutter.loader !== 'undefined',
        bodyHTML: document.body.innerHTML.substring(0, 2000)
      };
    ''', []);
    
    print('Flutter check: $flutterCheck');
    
    // Try to find flt-glass-pane
    final glassPane = driver.execute('''
      const glassPane = document.querySelector('flt-glass-pane');
      if (glassPane) {
        return {
          found: true,
          innerHTML: glassPane.innerHTML.substring(0, 1000),
          children: Array.from(glassPane.children).map(c => c.tagName)
        };
      }
      return { found: false };
    ''', []);
    
    print('\nGlass pane: $glassPane');
    
    // Look for all flt-* elements
    final flutterElements = driver.execute('''
      const allElements = document.querySelectorAll('*');
      const fltElements = {};
      
      allElements.forEach(el => {
        if (el.tagName.toLowerCase().startsWith('flt-')) {
          const tag = el.tagName.toLowerCase();
          fltElements[tag] = (fltElements[tag] || 0) + 1;
        }
      });
      
      return fltElements;
    ''', []);
    
    print('\nFlutter elements found: $flutterElements');

    driver.quit();
  } finally {
    chromeDriverProcess.kill();
  }
}
