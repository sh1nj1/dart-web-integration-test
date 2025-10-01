import 'dart:io';
import 'package:webdriver/io.dart';

class ChromeDriverManager {
  static const String defaultDriverPath = './drivers/chromedriver';
  static const int defaultPort = 9515;
  
  Process? _driverProcess;
  WebDriver? _driver;
  
  String driverPath;
  int port;
  
  ChromeDriverManager({
    this.driverPath = defaultDriverPath,
    this.port = defaultPort,
  });
  
  Future<void> startDriver() async {
    // ChromeDriver 프로세스 시작
    _driverProcess = await Process.start(
      driverPath,
      ['--port=$port', '--whitelisted-ips='],
    );
    
    // 드라이버가 시작될 때까지 잠깐 대기
    await Future.delayed(Duration(seconds: 2));
  }
  
  Future<WebDriver> createWebDriver({
    bool headless = false,
    Map<String, dynamic>? additionalOptions,
  }) async {
    final capabilities = Capabilities.chrome;
    final chromeOptions = <String, dynamic>{
      'args': [
        '--no-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
        if (headless) '--headless',
      ]
    };
    
    if (additionalOptions != null) {
      chromeOptions.addAll(additionalOptions);
    }
    
    capabilities['goog:chromeOptions'] = chromeOptions;
    
    _driver = await createDriver(
      uri: Uri.parse('http://localhost:$port'),
      desired: capabilities,
    );
    
    return _driver!;
  }
  
  Future<void> stopDriver() async {
    await _driver?.quit();
    _driverProcess?.kill();
    _driverProcess = null;
    _driver = null;
  }
}
