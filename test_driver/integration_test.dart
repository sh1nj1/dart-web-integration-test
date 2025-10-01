import 'dart:io';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  return integrationDriver(
    onScreenshot: (String screenshotName, List<int> screenshotBytes, [Map<String, Object?>? args]) async {
      // Save screenshot to screenshots directory
      final screenshotsDir = Directory('../screenshots');
      if (!await screenshotsDir.exists()) {
        await screenshotsDir.create(recursive: true);
      }
      
      final filepath = '../screenshots/$screenshotName.png';
      final file = File(filepath);
      await file.writeAsBytes(screenshotBytes);
      
      print('📸 Screenshot saved: $filepath');
      return true;
    },
  );
}
