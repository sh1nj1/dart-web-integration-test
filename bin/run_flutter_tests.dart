import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:glob/glob.dart';
import 'package:yaml/yaml.dart';
import '../lib/chrome_driver_manager.dart';

// Custom print function with [DSL] prefix
void log(Object? message) => print('[DSL] $message');

void main(List<String> args) async {
  if (args.isEmpty) {
    log('Usage: dart run bin/run_flutter_tests.dart <test_dsl_file|glob_pattern> [target-app-dir]');
    log('Examples:');
    log('  dart run bin/run_flutter_tests.dart test_dsl/sample_test.yaml');
    log('  dart run bin/run_flutter_tests.dart "test_dsl/*.yaml"');
    log('  dart run bin/run_flutter_tests.dart "test_dsl/**/*.yaml"');
    log('\nNote: Quote the pattern to prevent shell expansion!');
    exit(1);
  }

  // Determine if last arg is a directory (targetAppDir) or a test file
  String targetAppDir = './test_target';
  List<String> testPatterns;
  
  if (args.length > 1) {
    final lastArg = args.last;
    // Check if last arg looks like a directory or a test file
    if (Directory(lastArg).existsSync() || 
        (!lastArg.endsWith('.yaml') && !lastArg.endsWith('.json') && !lastArg.contains('*'))) {
      targetAppDir = lastArg;
      testPatterns = args.sublist(0, args.length - 1);
    } else {
      testPatterns = args;
    }
  } else {
    testPatterns = args;
  }

  // Resolve test files from patterns or single files
  final testFiles = <String>[];
  for (final pattern in testPatterns) {
    final files = await _resolveTestFiles(pattern);
    testFiles.addAll(files);
  }
  
  // Remove duplicates and sort
  final uniqueFiles = testFiles.toSet().toList();
  uniqueFiles.sort();
  
  if (uniqueFiles.isEmpty) {
    log('❌ No test files found');
    exit(1);
  }

  log('Found ${uniqueFiles.length} test file(s):');
  for (final file in uniqueFiles) {
    log('  - $file');
  }
  log('');

  // Check if ChromeDriver is installed
  if (!await _isChromeDriverInstalled()) {
    log('\n❌ ChromeDriver not found!');
    log('Would you like to install it now? (y/n)');
    
    final response = stdin.readLineSync();
    if (response?.toLowerCase() == 'y' || response?.toLowerCase() == 'yes') {
      log('\nInstalling ChromeDriver...\n');
      final installResult = await Process.run(
        'dart',
        ['run', 'bin/install_chromedriver.dart'],
        runInShell: true,
      );
      
      stdout.write(installResult.stdout);
      stderr.write(installResult.stderr);
      
      if (installResult.exitCode != 0) {
        log('\n❌ ChromeDriver installation failed!');
        exit(1);
      }
      
      log('\n✓ ChromeDriver installed successfully!\n');
    } else {
      log('\nPlease install ChromeDriver by running:');
      log('  dart run bin/install_chromedriver.dart\n');
      exit(1);
    }
  }

  // Initialize ChromeDriver manager once for all tests
  final chromeDriverManager = ChromeDriverManager();
  bool chromeDriverStartedByUs = false;

  // Track test results
  int totalPassedFiles = 0;
  int totalFailedFiles = 0;
  int totalPassedCases = 0;
  int totalFailedCases = 0;
  final failedFiles = <String>[];

  try {
    // Check if ChromeDriver is already running
    final isRunning = await _isChromeDriverRunning();
    
    if (!isRunning) {
      // Start ChromeDriver only if not already running
      log('Starting ChromeDriver...');
      await chromeDriverManager.startDriver();
      chromeDriverStartedByUs = true;
      
      // Wait and verify ChromeDriver is ready
      log('Waiting for ChromeDriver to be ready...');
      for (int i = 0; i < 10; i++) {
        await Future.delayed(Duration(milliseconds: 500));
        if (await _isChromeDriverRunning()) {
          log('ChromeDriver is ready!');
          break;
        }
      }
    } else {
      log('ChromeDriver already running, using existing instance...');
    }

    // Create symlinks once for all tests
    try {
      log('Creating test infrastructure symlinks...');
      final currentDir = Directory.current.absolute.path;
      
      // Backup existing directories if they exist
      await _backupExistingDirectory('$targetAppDir/test_driver');
      await _backupExistingDirectory('$targetAppDir/integration_test');
      
      await _createSymlink('$currentDir/test_driver', '$targetAppDir/test_driver');
      await _createSymlink('$currentDir/integration_test', '$targetAppDir/integration_test');
      
      // Check if app_config.dart exists, if not create from template
      final appConfigFile = File('$targetAppDir/integration_test/app_config.dart');
      if (!await appConfigFile.exists()) {
        log('Note: app_config.dart not found. Using default template.');
        log('You may need to create app_config.dart for app-specific initialization.');
      }
      
      // Generate merged test DSL code from all test files
      log('Generating merged test DSL code from ${uniqueFiles.length} file(s)...');
      
      // Create build directory for generated files
      final buildDir = Directory('$currentDir/build/generated');
      if (!await buildDir.exists()) {
        await buildDir.create(recursive: true);
      }
      
      final generatedFile = '$currentDir/build/generated/test_dsl_data.dart';
      await _generateMergedTestDslCode(uniqueFiles, generatedFile);
      
      // Copy generated file to integration_test symlink
      await File(generatedFile).copy('$targetAppDir/integration_test/test_dsl_data.dart');

      // Run Flutter driver test for web (once for all tests)
      log('\n${'=' * 60}');
      log('Running merged test suite with ${uniqueFiles.length} file(s)');
      log('=' * 60);
      log('Target app directory: $targetAppDir\n');
      log('Starting Flutter driver...');
      
      // Prepare Chrome arguments for CI environment
      final chromeArgs = Platform.environment['CHROME_ARGS'] ?? '';
      final chromeExecutable = Platform.environment['CHROME_EXECUTABLE'];
      
      final args = [
        'drive',
        '--driver=test_driver/integration_test.dart',
        '--target=integration_test/dsl_runner.dart',
        '-d',
        'chrome',
      ];
      
      // Specify Chrome binary if provided (for CI)
      if (chromeExecutable != null && chromeExecutable.isNotEmpty) {
        args.add('--chrome-binary=$chromeExecutable');
        log('Using Chrome binary: $chromeExecutable');
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
      int passedCases = 0;
      int failedCases = 0;
      
      process.stdout.transform(SystemEncoding().decoder).listen((data) {
        stdout.write(data);
        
        // Parse test case results from dsl_runner output
        final passedMatch = RegExp(r'\[DSL\] Passed: (\d+)').firstMatch(data);
        if (passedMatch != null) {
          passedCases = int.parse(passedMatch.group(1)!);
        }
        final failedMatch = RegExp(r'\[DSL\] Failed: (\d+)').firstMatch(data);
        if (failedMatch != null) {
          failedCases = int.parse(failedMatch.group(1)!);
        }
        
        if (data.contains('All tests passed!')) {
          // Tests passed, kill the process
          Future.delayed(Duration(milliseconds: 500), () {
            process.kill();
            if (!completer.isCompleted) completer.complete(0);
          });
        } else if (data.contains('Some tests failed')) {
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
      totalPassedCases = passedCases;
      totalFailedCases = failedCases;
      
      if (exitCode == 0) {
        totalPassedFiles = uniqueFiles.length;
      } else {
        totalFailedFiles = uniqueFiles.length;
        failedFiles.addAll(uniqueFiles);
      }
      
      // Kill any remaining Chrome processes
      await _killChromeProcesses();
      
      // Clean up symlinks and restore backups
      log('\nCleaning up test infrastructure...');
      await _deleteSymlink('$targetAppDir/test_driver');
      await _deleteSymlink('$targetAppDir/integration_test');
      
      // Restore backed up directories
      await _restoreBackup('$targetAppDir/test_driver');
      await _restoreBackup('$targetAppDir/integration_test');
    } catch (e) {
      log('Error: $e');
      totalFailedFiles = uniqueFiles.length;
      failedFiles.addAll(uniqueFiles);
      
      // Clean up on error
      await _deleteSymlink('$targetAppDir/test_driver');
      await _deleteSymlink('$targetAppDir/integration_test');
      
      // Restore backups
      await _restoreBackup('$targetAppDir/test_driver');
      await _restoreBackup('$targetAppDir/integration_test');
    }

    // Stop ChromeDriver only if we started it
    if (chromeDriverStartedByUs) {
      log('Stopping ChromeDriver...');
      await chromeDriverManager.stopDriver();
    }
  } catch (e) {
    log('Fatal error: $e');
    exit(1);
  }

  // Print overall summary
  log('\n${'=' * 60}');
  log('OVERALL TEST SUMMARY');
  log('=' * 60);
  log('Test Files: ${uniqueFiles.length} (Passed: $totalPassedFiles, Failed: $totalFailedFiles)');
  log('Test Cases: ${totalPassedCases + totalFailedCases} (Passed: $totalPassedCases, Failed: $totalFailedCases)');
  
  if (failedFiles.isNotEmpty) {
    log('\nFailed test files:');
    for (final file in failedFiles) {
      log('  ✗ $file');
    }
  }
  log('=' * 60);
  
  // Exit with appropriate code
  exit(totalFailedFiles > 0 ? 1 : 0);
}

Future<List<String>> _resolveTestFiles(String pattern) async {
  // Check if pattern contains glob characters
  if (pattern.contains('*') || pattern.contains('?') || pattern.contains('[')) {
    // Use glob to find matching files
    final glob = Glob(pattern);
    final files = <String>[];
    
    // Extract directory path from pattern
    final parts = pattern.split('/');
    var dirPath = '.';
    for (int i = 0; i < parts.length - 1; i++) {
      if (!parts[i].contains('*') && !parts[i].contains('?')) {
        dirPath = parts.sublist(0, i + 1).join('/');
      } else {
        break;
      }
    }
    
    // List files recursively and filter by glob
    final dir = Directory(dirPath);
    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && glob.matches(entity.path)) {
          files.add(entity.path);
        }
      }
    }
    
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

Future<void> _generateMergedTestDslCode(List<String> dslPaths, String outputPath) async {
  final mergedTests = <Map<String, dynamic>>[];
  
  for (final dslPath in dslPaths) {
    final dslFile = File(dslPath);
    final dslContent = await dslFile.readAsString();
    
    // Convert to JSON if input is YAML
    Map<String, dynamic> data;
    if (dslPath.endsWith('.yaml') || dslPath.endsWith('.yml')) {
      final yaml = loadYaml(dslContent);
      data = _convertYamlToMap(yaml);
    } else {
      data = jsonDecode(dslContent);
    }
    
    // Add _sourceFile to each test case
    if (data['tests'] is List) {
      for (final test in data['tests']) {
        if (test is Map) {
          test['_sourceFile'] = dslPath;
        }
      }
    }
    
    // Collect all tests
    if (data['tests'] is List) {
      mergedTests.addAll((data['tests'] as List).cast<Map<String, dynamic>>());
    }
  }
  
  // Create merged test suite
  final mergedData = {
    'name': 'Merged Test Suite',
    'tests': mergedTests,
  };
  
  final jsonContent = jsonEncode(mergedData);
  
  // Escape the JSON content for Dart string literal
  final escapedContent = jsonContent
      .replaceAll(r'\', r'\\')
      .replaceAll(r"'", r"\'");
  
  final dartCode = '// Auto-generated file - do not edit\n'
      '// Generated from ${dslPaths.length} test file(s)\n\n'
      "const String testDslJson = '''\n"
      '$escapedContent\n'
      "''';\n";
  
  final outputFile = File(outputPath);
  await outputFile.writeAsString(dartCode);
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
    log('  Backing up existing directory: $path -> $backupPath');
    await dir.rename(backupPath);
  }
}

Future<void> _restoreBackup(String path) async {
  final backupPath = '$path.bak';
  final backupDir = Directory(backupPath);
  
  if (await backupDir.exists()) {
    log('  Restoring backup: $backupPath -> $path');
    await backupDir.rename(path);
  }
}
