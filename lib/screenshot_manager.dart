import 'dart:io';
import 'dart:typed_data';
import 'package:webdriver/io.dart';

class ScreenshotManager {
  static const String defaultScreenshotDir = './screenshots';
  
  final String screenshotDirectory;
  
  ScreenshotManager({this.screenshotDirectory = defaultScreenshotDir});
  
  /// 스크린샷 디렉토리 생성
  Future<void> ensureScreenshotDirectory() async {
    final dir = Directory(screenshotDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      print('Created screenshot directory: $screenshotDirectory');
    }
  }
  
  /// 테스트 실패 시 스크린샷 저장
  Future<String?> captureFailureScreenshot(
    WebDriver driver, 
    String testCaseName, 
    String stepAction,
    [String? errorMessage]
  ) async {
    try {
      await ensureScreenshotDirectory();
      
      // 파일명 생성: timestamp_testcase_step.png
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final sanitizedTestName = _sanitizeFileName(testCaseName);
      final sanitizedStepAction = _sanitizeFileName(stepAction);
      final fileName = '${timestamp}_${sanitizedTestName}_${sanitizedStepAction}.png';
      final filePath = '$screenshotDirectory/$fileName';
      
      // 스크린샷 촬영
      final List<int> screenshot = await driver.captureScreenshotAsList();
      final file = File(filePath);
      await file.writeAsBytes(screenshot);
      
      print('📸 Screenshot saved: $filePath');
      if (errorMessage != null) {
        print('   Error: $errorMessage');
      }
      
      return filePath;
    } catch (e) {
      print('Failed to capture screenshot: $e');
      return null;
    }
  }
  
  /// 단계별 스크린샷 저장 (디버깅용)
  Future<String?> captureStepScreenshot(
    WebDriver driver,
    String testCaseName,
    String stepAction,
    int stepIndex,
  ) async {
    try {
      await ensureScreenshotDirectory();
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final sanitizedTestName = _sanitizeFileName(testCaseName);
      final sanitizedStepAction = _sanitizeFileName(stepAction);
      final fileName = '${timestamp}_${sanitizedTestName}_step${stepIndex}_${sanitizedStepAction}.png';
      final filePath = '$screenshotDirectory/$fileName';
      
      final List<int> screenshot = await driver.captureScreenshotAsList();
      final file = File(filePath);
      await file.writeAsBytes(screenshot);
      
      print('📷 Step screenshot saved: $filePath');
      return filePath;
    } catch (e) {
      print('Failed to capture step screenshot: $e');
      return null;
    }
  }
  
  /// 파일명에서 특수문자 제거
  String _sanitizeFileName(String fileName) {
    return fileName
        .replaceAll(RegExp(r'[^\w\s-]'), '') // 특수문자 제거
        .replaceAll(RegExp(r'\s+'), '_')     // 공백을 언더스코어로
        .toLowerCase();
  }
  
  /// 오래된 스크린샷 정리 (선택적)
  Future<void> cleanupOldScreenshots({int keepDays = 7}) async {
    try {
      final dir = Directory(screenshotDirectory);
      if (!await dir.exists()) return;
      
      final cutoffTime = DateTime.now().subtract(Duration(days: keepDays));
      final files = await dir.list().toList();
      
      for (final file in files) {
        if (file is File && file.path.endsWith('.png')) {
          final stat = await file.stat();
          if (stat.modified.isBefore(cutoffTime)) {
            await file.delete();
            print('Deleted old screenshot: ${file.path}');
          }
        }
      }
    } catch (e) {
      print('Failed to cleanup old screenshots: $e');
    }
  }
}
