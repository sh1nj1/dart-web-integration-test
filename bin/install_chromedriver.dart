import 'dart:io';

void main() async {
  print('=== ChromeDriver Installation Script ===\n');

  try {
    final chromeVersion = await detectChromeVersion();
    await installChromeDriver(chromeVersion);
    await setupSymlink();
    await verifyInstallation();

    print('\n=== Installation Complete ===');
  } catch (e) {
    print('❌ Error: $e');
    exit(1);
  }
}

/// Detect installed Chrome version
Future<String> detectChromeVersion() async {
  String? chromeVersion;

  if (Platform.isMacOS) {
    // macOS
    final chromePath = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
    if (await File(chromePath).exists()) {
      final result = await Process.run(chromePath, ['--version']);
      if (result.exitCode == 0) {
        chromeVersion = (result.stdout as String).trim().split(' ').last;
      }
    }
  } else if (Platform.isLinux) {
    // Linux
    for (final command in ['google-chrome', 'chromium-browser']) {
      final result = await Process.run('which', [command], runInShell: true);
      if (result.exitCode == 0) {
        final versionResult = await Process.run(command, ['--version'], runInShell: true);
        if (versionResult.exitCode == 0) {
          chromeVersion = (versionResult.stdout as String).trim().split(' ').last;
          break;
        }
      }
    }
  } else if (Platform.isWindows) {
    // Windows
    final chromePaths = [
      r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    ];
    
    for (final chromePath in chromePaths) {
      if (await File(chromePath).exists()) {
        final result = await Process.run(chromePath, ['--version']);
        if (result.exitCode == 0) {
          chromeVersion = (result.stdout as String).trim().split(' ').last;
          break;
        }
      }
    }
  }

  if (chromeVersion == null || chromeVersion.isEmpty) {
    print('❌ Chrome not found. Installing latest ChromeDriver...');
    return 'latest';
  } else {
    print('✓ Detected Chrome version: $chromeVersion');
    return chromeVersion;
  }
}

/// Install ChromeDriver using Puppeteer
Future<void> installChromeDriver(String chromeVersion) async {
  print('\nInstalling ChromeDriver $chromeVersion...');

  String version;
  if (chromeVersion != 'latest') {
    // Extract major version (e.g., 131.0.6778.204 -> 131)
    final majorVersion = chromeVersion.split('.').first;
    version = majorVersion;
    print('Installing ChromeDriver for Chrome $majorVersion...');
  } else {
    version = 'latest';
  }

  final result = await Process.run(
    'npx',
    ['--yes', '@puppeteer/browsers', 'install', 'chromedriver@$version'],
    runInShell: true,
  );

  stdout.write(result.stdout);
  stderr.write(result.stderr);

  if (result.exitCode != 0) {
    throw Exception('Failed to install ChromeDriver');
  }
}

/// Setup symlink to drivers/chromedriver
Future<void> setupSymlink() async {
  print('\nSetting up drivers directory...');

  // Create drivers directory
  final driversDir = Directory('drivers');
  if (!await driversDir.exists()) {
    await driversDir.create();
  }

  // Find ChromeDriver executable
  final chromedriverDir = Directory('chromedriver');
  if (!await chromedriverDir.exists()) {
    throw Exception('ChromeDriver directory not found');
  }

  String? chromedriverPath;
  await for (final entity in chromedriverDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith(Platform.isWindows ? 'chromedriver.exe' : 'chromedriver')) {
      // Check if it's actually an executable (not .map or other files)
      final filename = entity.uri.pathSegments.last;
      if (filename == 'chromedriver' || filename == 'chromedriver.exe') {
        chromedriverPath = entity.path;
        break;
      }
    }
  }

  if (chromedriverPath == null) {
    throw Exception('ChromeDriver executable not found');
  }

  print('✓ Found ChromeDriver at: $chromedriverPath');

  // Setup link/copy
  final targetPath = Platform.isWindows ? 'drivers\\chromedriver.exe' : 'drivers/chromedriver';
  final targetFile = File(targetPath);
  
  // Remove existing file/link if exists
  if (await targetFile.exists()) {
    await targetFile.delete();
  }
  final targetLink = Link(targetPath);
  if (await targetLink.exists()) {
    await targetLink.delete();
  }

  // Get absolute path
  final absolutePath = File(chromedriverPath).absolute.path;

  if (Platform.isWindows) {
    // On Windows, copy the file instead of creating a symlink
    // because symlinks require admin privileges
    await File(chromedriverPath).copy(targetPath);
    print('✓ Copied ChromeDriver to: $targetPath');
  } else {
    // On Unix systems, create a symlink
    await Link(targetPath).create(absolutePath);
    
    // Make executable
    await Process.run('chmod', ['+x', targetPath]);
    print('✓ Symlink created: $targetPath -> $chromedriverPath');
  }
}

/// Verify ChromeDriver installation
Future<void> verifyInstallation() async {
  print('\nVerifying installation...');

  final executable = Platform.isWindows ? 'drivers\\chromedriver.exe' : 'drivers/chromedriver';
  
  final result = await Process.run(executable, ['--version']);
  
  if (result.exitCode == 0) {
    final version = (result.stdout as String).trim();
    print('✓ ChromeDriver installed successfully!');
    print('  $version');
  } else {
    throw Exception('ChromeDriver verification failed');
  }
}
