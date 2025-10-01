# Dart Web Integration Test

Chrome WebDriver를 사용한 Dart 웹 애플리케이션 integration test 프레임워크

## 프로젝트 구조

```
dart-web-integration-test/
├── lib/                          # 핵심 라이브러리 (Selenium 방식)
│   ├── chrome_driver_manager.dart # ChromeDriver 관리
│   ├── test_dsl_parser.dart       # JSON 테스트 DSL 파서
│   └── test_executor.dart         # 테스트 실행 엔진
├── bin/                          # 실행 파일
│   ├── run_tests.dart            # Selenium 테스트 실행기
│   └── run_flutter_tests.dart    # Flutter Integration 테스트 실행기
├── test-dsl/                     # 테스트 DSL JSON 파일들
│   ├── sample_test.json          # 샘플 테스트 케이스
│   └── failing_test.json         # 실패 테스트 (스크린샷 데모용)
├── integration_test/             # Flutter Integration Test 러너
│   └── dsl_runner.dart           # JSON DSL을 Flutter 테스트로 변환
├── test_driver/                  # Flutter Driver
│   └── integration_test.dart     # Integration test driver
├── test_target/                  # 테스트 대상 Flutter 웹 앱 (독립적)
│   ├── lib/main.dart            # Flutter 앱 메인 파일
│   ├── pubspec.yaml             # Flutter 프로젝트 설정
│   └── web/                     # 웹 빌드 파일들
├── drivers/                      # ChromeDriver 실행 파일 저장소
├── screenshots/                  # 테스트 실패 시 스크린샷 저장소
├── config/                       # 설정 파일들
│   └── chromedriver_config.json  # ChromeDriver 설정
└── test/                         # 단위 테스트
```

## 설치 및 설정

### 1. 의존성 설치
```bash
dart pub get
```

### 2. ChromeDriver 다운로드
[ChromeDriver 다운로드 페이지](https://chromedriver.chromium.org/)에서 Chrome 버전에 맞는 ChromeDriver를 다운로드하여 `drivers/` 폴더에 저장

### 3. Flutter 웹 앱 실행
```bash
# test_target 디렉토리에서 Flutter 웹 앱 실행
cd test_target
flutter run -d chrome --web-port 3001
```

**참고**: 최신 Flutter는 자동으로 CanvasKit 렌더러를 사용합니다. 테스트 프레임워크는 자동으로 접근성을 활성화하여 Selenium이 요소를 찾을 수 있도록 합니다.

## 사용법

### 테스트 실행

Flutter의 CanvasKit 렌더러는 Canvas로 렌더링하므로 Selenium WebDriver로 DOM 요소를 찾을 수 없습니다. 따라서 Flutter Integration Test를 사용합니다:

```bash
# Flutter Integration Test 실행 (권장)
dart run bin/run_flutter_tests.dart test-dsl/sample_test.json

# 다른 Flutter 앱 테스트 (런타임에 클론된 앱 등)
dart run bin/run_flutter_tests.dart test-dsl/sample_test.json /path/to/flutter/app
```

**참고**: 테스트 실행 시 `integration_test/`와 `test_driver/` 디렉토리가 자동으로 대상 앱에 복사되고, 테스트 완료 후 삭제됩니다.

### 다른 Flutter 앱에서 사용하기

1. **app_config.dart 생성**: `integration_test/app_config.dart.template`을 복사하여 앱별 설정 생성
   ```dart
   // integration_test/app_config.dart
   import 'package:flutter_test/flutter_test.dart';
   import 'package:your_app/main.dart' as app;

   Future<void> startApp(WidgetTester tester) async {
     app.main();
     await tester.pumpAndSettle();
   }
   ```

2. **위젯에 Key 추가**: 테스트할 위젯에 식별 가능한 Key 추가
   ```dart
   TextFormField(
     key: const Key('username-input'),
     decoration: const InputDecoration(labelText: 'Username'),
   )
   ```

3. **테스트 DSL 작성**: `key:`, `text:`, `type:` 셀렉터 사용
   ```json
   {
     "action": "type",
     "selector": "key:username-input",
     "value": "testuser"
   }
   ```

4. **테스트 실행**:
   ```bash
   dart run bin/run_flutter_tests.dart my-test.json /path/to/your/flutter/app
   ```

**Selenium 방식 (참고용 - CanvasKit에서는 작동하지 않음)**
```bash
# Selenium 기반 테스트 (HTML 렌더러에서만 작동)
dart run bin/run_tests.dart test-dsl/sample_test.json
```

### 테스트 DSL 형식

```json
{
  "name": "테스트 스위트 이름",
  "baseUrl": "http://localhost:3000",
  "testCases": [
    {
      "name": "테스트 케이스 이름",
      "description": "테스트 설명",
      "url": "선택적 URL (기본: baseUrl 사용)",
      "steps": [
        {
          "action": "click|type|wait|assert_text|assert_visible|navigate",
          "selector": "CSS 선택자 (필요시)",
          "value": "입력값 (type, navigate 액션용)",
          "expected": "예상값 (assert 액션용)",
          "waitTime": "대기시간 (밀리초)"
        }
      ]
    }
  ]
}
```

### 지원되는 액션

- `click`: 요소 클릭
- `type`: 텍스트 입력
- `wait`: 지정된 시간 대기
- `assert_text`: 텍스트 내용 검증
- `assert_visible`: 요소 가시성 검증
- `navigate`: 페이지 이동

### 셀렉터 형식

새로운 명시적 셀렉터 형식 (권장):
- `text:Button Text` - 정확한 텍스트로 찾기
- `textContains:partial text` - 부분 텍스트로 찾기
- `key:my-widget-key` - Key로 찾기
- `type:ElevatedButton` - 위젯 타입으로 찾기

지원되는 위젯 타입:
- `ElevatedButton`, `TextButton`, `OutlinedButton`, `IconButton`
- `TextField`, `TextFormField`
- `Checkbox`, `Radio`, `Switch`

레거시 셀렉터 (하위 호환성):
- `flt-semantics[aria-label='text']` - 자동으로 `text:text`로 변환
- `[key='my-key']` - 자동으로 `key:my-key`로 변환

## 스크린샷 기능

### 테스트 실패 시 자동 스크린샷
- 테스트가 실패하면 자동으로 `screenshots/` 디렉토리에 스크린샷이 저장됩니다
- 파일명 형식: `{timestamp}_{testcase}_{step}.png`
- 실패한 단계와 전체 테스트 실패 시점의 스크린샷을 촬영합니다

### 설정 옵션
- `captureScreenshotsOnFailure`: 실패 시 스크린샷 촬영 (기본값: true)
- `captureStepScreenshots`: 모든 단계별 스크린샷 촬영 (기본값: false)

## 개발

새로운 액션 추가는 `lib/test_executor.dart`의 `executeStep` 메서드를 수정하세요.
