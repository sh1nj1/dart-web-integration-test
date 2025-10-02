import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:glob/glob.dart';
import 'package:yaml/yaml.dart';
import '../lib/chrome_driver_manager.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/run_flutter_tests.dart <test_dsl_file|glob_pattern> [target-app-dir]');
    print('Examples:');
    print('  dart run bin/run_flutter_tests.dart test_dsl/sample_test.yaml');
    print('  dart run bin/run_flutter_tests.dart "test_dsl/*.yaml"');
    print('  dart run bin/run_flutter_tests.dart "test_dsl/**/*.yaml"');
    exit(1);
  }

  final testDslPattern = args[0];
  final targetAppDir = args.length > 1 ? args[1] : './test_target';

  // Resolve test files from pattern or single file
  final testFiles = await _resolveTestFiles(testDslPattern);
  
  if (testFiles.isEmpty) {
    print('❌ No test files found matching: $testDslPattern');
    exit(1);
  }

  print('Found ${testFiles.length} test file(s):');
  for (final file in testFiles) {
    print('  - $file');
  }
  print('');

  // Check if ChromeDriver is installed
  if (!await _isChromeDriverInstalled()) {
    print('\n❌ ChromeDriver not found!');
    print('Would you like to install it now? (y/n)');
    
    final response = stdin.readLineSync();
    if (response?.toLowerCase() == 'y' || response?.toLowerCase() == 'yes') {
      print('\nInstalling ChromeDriver...\n');
      final installResult = await Process.run(
        'dart',
        ['run', 'bin/install_chromedriver.dart'],
        runInShell: true,
      );
      
      stdout.write(installResult.stdout);
      stderr.write(installResult.stderr);
      
      if (installResult.exitCode != 0) {
        print('\n❌ ChromeDriver installation failed!');
        exit(1);
      }
      
      print('\n✓ ChromeDriver installed successfully!\n');
    } else {
      print('\nPlease install ChromeDriver by running:');
      print('  dart run bin/install_chromedriver.dart\n');
      exit(1);
    }
  }

  // Run tests for each file
  int totalPassed = 0;
  int totalFailed = 0;
  final failedFiles = <String>[];

  for (int fileIndex = 0; fileIndex < testFiles.length; fileIndex++) {
    final testDslFile = testFiles[fileIndex];
    final absolutePath = File(testDslFile).absolute.path;

    print('\n${'=' * 60}');
    print('Running test file ${fileIndex + 1}/${testFiles.length}: $testDslFile');
    print('=' * 60);
    print('Target app directory: $targetAppDir\n');

    // Initialize ChromeDriver manager
    final chromeDriverManager = ChromeDriverManager();
    bool chromeDriverStartedByUs = false;

    try {
      // Check if ChromeDriver is already running
      final isRunning = await _isChromeDriverRunning();
      
      if (!isRunning) {
        // Start ChromeDriver only if not already running
        print('Starting ChromeDriver...');
        await chromeDriverManager.startDriver();
        chromeDriverStartedByUs = true;
        
        // Wait and verify ChromeDriver is ready
        print('Waiting for ChromeDriver to be ready...');
        for (int i = 0; i < 10; i++) {
          await Future.delayed(Duration(milliseconds: 500));
          if (await _isChromeDriverRunning()) {
            print('ChromeDriver is ready!');
            break;
          }
        }
      } else {
        print('ChromeDriver already running, using existing instance...');
      }
      
      // Create symlinks instead of copying files (keeps target app clean)
      print('Creating test infrastructure symlinks...');
      final currentDir = Directory.current.absolute.path;
      
      // Backup existing directories if they exist
      await _backupExistingDirectory('$targetAppDir/test_driver');
      await _backupExistingDirectory('$targetAppDir/integration_test');
      
      await _createSymlink('$currentDir/test_driver', '$targetAppDir/test_driver');
      await _createSymlink('$currentDir/integration_test', '$targetAppDir/integration_test');
      
      // Check if app_config.dart exists, if not create from template
      final appConfigFile = File('$targetAppDir/integration_test/app_config.dart');
      if (!await appConfigFile.exists()) {
        print('Note: app_config.dart not found. Using default template.');
        print('You may need to create app_config.dart for app-specific initialization.');
      }
      
      // Generate test DSL as Dart code (for web compatibility)
      print('Generating test DSL code...');
      await _generateTestDslCode(testDslFile, '$targetAppDir/integration_test/test_dsl_data.dart');

    // Run Flutter driver test for web
    print('Starting Flutter driver...');
    
    // Prepare Chrome arguments for CI environment
    final chromeArgs = Platform.environment['CHROME_ARGS'] ?? '';
    final chromeExecutable = Platform.environment['CHROME_EXECUTABLE'];
    
    final args = [
      'drive',
      '--driver=test_driver/integration_test.dart',
      '--target=integration_test/dsl_runner.dart',
      '-d',
      'chrome',
      '--dart-define=TEST_DSL_PATH=$absolutePath',
    ];
    
    // Specify Chrome binary if provided (for CI)
    if (chromeExecutable != null && chromeExecutable.isNotEmpty) {
      args.add('--chrome-binary=$chromeExecutable');
      print('Using Chrome binary: $chromeExecutable');
    }
    
    // Add Chrome arguments as web browser flags if provided
    if (chromeArgs.isNotEmpty) {
      for (final arg in chromeArgs.split(' ')) {
        if (arg.isNotEmpty) {
          args.add('--web-browser-flag=$arg');
        }
      }
    }
    
    final process = await Process.start(
      'flutter',
      args,
      workingDirectory: targetAppDir,
      runInShell: true,
    );

    // Monitor output and kill process when tests complete
    final completer = Completer<int>();
    var testsFailed = false;
    
    process.stdout.transform(SystemEncoding().decoder).listen((data) {
      stdout.write(data);
      if (data.contains('All tests passed!')) {
        // Tests passed, kill the process
        Future.delayed(Duration(milliseconds: 500), () {
          process.kill();
          if (!completer.isCompleted) completer.complete(0);
        });
      } else if (data.contains('Some tests failed')) {
        testsFailed = true;
        Future.delayed(Duration(milliseconds: 500), () {
          process.kill();
          if (!completer.isCompleted) completer.complete(1);
        });
      }
    });
    
    process.stderr.transform(SystemEncoding().decoder).listen(stderr.write);

      // Wait for either manual completion or process exit
      final exitCode = await Future.any([
        completer.future,
        process.exitCode,
      ]);
      
      // Track results
      if (exitCode == 0) {
        totalPassed++;
      } else {
        totalFailed++;
        failedFiles.add(testDslFile);
      }
      
      // Kill any remaining Chrome processes
      await _killChromeProcesses();
      
      // Clean up symlinks and restore backups
      print('\nCleaning up test infrastructure...');
      await _deleteSymlink('$targetAppDir/test_driver');
      await _deleteSymlink('$targetAppDir/integration_test');
      
      // Restore backed up directories
      await _restoreBackup('$targetAppDir/test_driver');
      await _restoreBackup('$targetAppDir/integration_test');
      
      // Stop ChromeDriver only if we started it
      if (chromeDriverStartedByUs) {
        print('Stopping ChromeDriver...');
        await chromeDriverManager.stopDriver();
      }
    } catch (e) {
      print('Error: $e');
      totalFailed++;
      failedFiles.add(testDslFile);
      
      // Clean up on error
      await _deleteSymlink('$targetAppDir/test_driver');
      await _deleteSymlink('$targetAppDir/integration_test');
      
      // Restore backups
      await _restoreBackup('$targetAppDir/test_driver');
      await _restoreBackup('$targetAppDir/integration_test');
      
      if (chromeDriverStartedByUs) {
        await chromeDriverManager.stopDriver();
      }
    }
  }

  // Print overall summary
  print('\n${'=' * 60}');
  print('OVERALL TEST SUMMARY');
  print('=' * 60);
  print('Total test files: ${testFiles.length}');
  print('Passed: $totalPassed');
  print('Failed: $totalFailed');
  
  if (failedFiles.isNotEmpty) {
    print('\nFailed test files:');
    for (final file in failedFiles) {
      print('  ✗ $file');
    }
  }
  print('=' * 60);
  
  // Exit with appropriate code
  exit(totalFailed > 0 ? 1 : 0);
}

Future<List<String>> _resolveTestFiles(String pattern) async {
  // Check if pattern contains glob characters
  if (pattern.contains('*') || pattern.contains('?') || pattern.contains('[')) {
    // Use glob to find matching files
    final glob = Glob(pattern);
    final files = await glob.list().where((entity) => entity is File).map((entity) => entity.path).toList();
    files.sort(); // Sort for consistent ordering
    return files;
  } else {
    // Single file
    final file = File(pattern);
    if (await file.exists()) {
      return [pattern];
    } else {
      return [];
    }
  }
}

Future<void> _createSymlink(String source, String destination) async {
  final sourceDir = Directory(source);
  
  if (!await sourceDir.exists()) {
    throw Exception('Source directory does not exist: $source');
  }

  final link = Link(destination);
  
  // Remove existing link or directory if it exists
  if (await link.exists()) {
    await link.delete();
  } else if (await Directory(destination).exists()) {
    await Directory(destination).delete(recursive: true);
  }

  // Create symlink
  await link.create(source);
}

Future<void> _deleteSymlink(String path) async {
  final link = Link(path);
  
  if (await link.exists()) {
    await link.delete();
  } else if (await Directory(path).exists()) {
    // Fallback: if it's a directory (not a symlink), delete it
    await Directory(path).delete(recursive: true);
  }
}

Future<void> _generateTestDslCode(String dslPath, String outputPath) async {
  final dslFile = File(dslPath);
  final dslContent = await dslFile.readAsString();
  
  // Convert to JSON if input is YAML
  String jsonContent;
  if (dslPath.endsWith('.yaml') || dslPath.endsWith('.yml')) {
    final yaml = loadYaml(dslContent);
    final Map<String, dynamic> data = _convertYamlToMap(yaml);
    jsonContent = jsonEncode(data);
  } else {
    jsonContent = dslContent;
  }
  
  // Escape the JSON content for Dart string literal
  final escapedContent = jsonContent
      .replaceAll(r'\', r'\\')
      .replaceAll(r"'", r"\'");
  
  final dartCode = '// Auto-generated file - do not edit\n'
      '// Generated from: $dslPath\n\n'
      "const String testDslJson = '''\n"
      '$escapedContent\n'
      "''';\n";
  
  final outputFile = File(outputPath);
  await outputFile.writeAsString(dartCode);
}

dynamic _convertYamlToMap(dynamic yaml) {
  if (yaml is YamlMap) {
    return Map<String, dynamic>.from(yaml.map((key, value) => 
      MapEntry(key.toString(), _convertYamlToMap(value))));
  } else if (yaml is YamlList) {
    return yaml.map((item) => _convertYamlToMap(item)).toList();
  } else {
    return yaml;
  }
}

Future<void> _killChromeProcesses() async {
  try {
    if (Platform.isMacOS || Platform.isLinux) {
      // Kill Chrome processes that were started by flutter drive
      await Process.run('pkill', ['-f', 'Chrome.*--remote-debugging-port']);
    } else if (Platform.isWindows) {
      await Process.run('taskkill', ['/F', '/IM', 'chrome.exe']);
    }
  } catch (e) {
    // Ignore errors if no processes found
  }
}

Future<bool> _isChromeDriverInstalled() async {
  // Check in drivers/ directory
  final localDriver = File(Platform.isWindows ? 'drivers/chromedriver.exe' : 'drivers/chromedriver');
  if (await localDriver.exists()) {
    return true;
  }

  // Check in system PATH
  try {
    final result = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      ['chromedriver'],
      runInShell: true,
    );
    return result.exitCode == 0;
  } catch (e) {
    return false;
  }
}

Future<bool> _isChromeDriverRunning() async {
  try {
    // Try to connect to ChromeDriver's default port (4444)
    final socket = await Socket.connect('localhost', 4444, timeout: Duration(seconds: 1));
    await socket.close();
    return true;
  } catch (e) {
    return false;
  }
}

Future<void> _backupExistingDirectory(String path) async {
  final dir = Directory(path);
  final link = Link(path);
  
  // Check if it's a real directory (not a symlink)
  if (await dir.exists() && !await link.exists()) {
    final backupPath = '$path.bak';
    print('  Backing up existing directory: $path -> $backupPath');
    await dir.rename(backupPath);
  }
}

Future<void> _restoreBackup(String path) async {
  final backupPath = '$path.bak';
  final backupDir = Directory(backupPath);
  
  if (await backupDir.exists()) {
    print('  Restoring backup: $backupPath -> $path');
    await backupDir.rename(path);
  }
}
