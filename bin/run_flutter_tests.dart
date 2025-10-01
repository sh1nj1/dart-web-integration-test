import 'dart:async';
import 'dart:io';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/run_flutter_tests.dart <test-dsl-file> [target-app-dir]');
    exit(1);
  }

  final testDslFile = args[0];
  final targetAppDir = args.length > 1 ? args[1] : './test_target';
  final absolutePath = File(testDslFile).absolute.path;

  print('Running Flutter integration tests with DSL: $testDslFile');
  print('Target app directory: $targetAppDir');

  try {
    // Copy test infrastructure to target app directory
    print('Copying test infrastructure...');
    await _copyDirectory('./test_driver', '$targetAppDir/test_driver');
    await _copyDirectory('./integration_test', '$targetAppDir/integration_test');
    
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
    final process = await Process.start(
      'flutter',
      [
        'drive',
        '--driver=test_driver/integration_test.dart',
        '--target=integration_test/dsl_runner.dart',
        '-d',
        'chrome',
        '--headless',
        '--dart-define=TEST_DSL_PATH=$absolutePath',
      ],
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
    
    // Kill any remaining Chrome processes
    await _killChromeProcesses();
    
    // Clean up before exiting
    print('\nCleaning up test infrastructure...');
    await _deleteDirectory('$targetAppDir/test_driver');
    await _deleteDirectory('$targetAppDir/integration_test');
    
    print('Done!');
    
    // Force exit
    exit(exitCode);
  } catch (e) {
    print('Error: $e');
    // Clean up on error
    await _deleteDirectory('$targetAppDir/test_driver');
    await _deleteDirectory('$targetAppDir/integration_test');
    exit(1);
  }
}

Future<void> _copyDirectory(String source, String destination) async {
  final sourceDir = Directory(source);
  final destDir = Directory(destination);

  if (!await sourceDir.exists()) {
    throw Exception('Source directory does not exist: $source');
  }

  // Create destination directory
  await destDir.create(recursive: true);

  // Copy all files
  await for (final entity in sourceDir.list(recursive: true)) {
    if (entity is File) {
      final relativePath = entity.path.substring(sourceDir.path.length);
      final newPath = destination + relativePath;
      await Directory(newPath.substring(0, newPath.lastIndexOf('/'))).create(recursive: true);
      await entity.copy(newPath);
    }
  }
}

Future<void> _deleteDirectory(String path) async {
  final dir = Directory(path);
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}

Future<void> _generateTestDslCode(String jsonPath, String outputPath) async {
  final jsonFile = File(jsonPath);
  final jsonContent = await jsonFile.readAsString();
  
  // Escape the JSON content for Dart string literal
  final escapedContent = jsonContent
      .replaceAll(r'\', r'\\')
      .replaceAll(r"'", r"\'");
  
  final dartCode = '// Auto-generated file - do not edit\n'
      '// Generated from: $jsonPath\n\n'
      "const String testDslJson = '''\n"
      '$escapedContent\n'
      "''';\n";
  
  final outputFile = File(outputPath);
  await outputFile.writeAsString(dartCode);
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
