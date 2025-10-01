# Dart Web Integration Test

Chrome WebDriver를 사용한 Dart 웹 애플리케이션 integration test 프레임워크

## 프로젝트 구조

```
dart-web-integration-test/
├── lib/                          # 핵심 라이브러리
│   ├── chrome_driver_manager.dart # ChromeDriver 관리
│   ├── test_dsl_parser.dart       # JSON 테스트 DSL 파서
│   └── test_executor.dart         # 테스트 실행 엔진
├── bin/                          # 실행 파일
│   └── run_tests.dart            # 메인 테스트 실행기
├── test-dsl/                     # 테스트 DSL JSON 파일들
│   └── sample_test.json          # 샘플 테스트 케이스
├── test_target/                  # 테스트 대상 Flutter 웹 앱
│   ├── lib/main.dart            # Flutter 앱 메인 파일
│   ├── pubspec.yaml             # Flutter 프로젝트 설정
│   └── web/                     # 웹 빌드 파일들
├── drivers/                      # ChromeDriver 실행 파일 저장소
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

## 사용법

### 테스트 실행
```bash
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

## 개발

새로운 액션 추가는 `lib/test_executor.dart`의 `executeStep` 메서드를 수정하세요.
