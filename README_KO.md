# Flutter Web Integration Test

[🇰🇷 (한국어)](./README_KO.md) | [🇬🇧 (English)](./README.md)

Chrome WebDriver를 사용한 Flutter 웹 애플리케이션 integration test 프레임워크

[샘플 테스트를 구동하는 스크린캐스트](https://youtu.be/5ak3G1bGFAw)

## 프로젝트 구조

```
flutter-web-integration-test/
├── lib/                          # 핵심 라이브러리
│   ├── chrome_driver_manager.dart # ChromeDriver 관리
│   └── test_dsl_parser.dart       # JSON/YAML 테스트 DSL 파서
├── bin/                          # 실행 파일
│   └── run_flutter_tests.dart    # Flutter Integration 테스트 실행기
├── test_dsl/                     # 테스트 DSL 파일들 (JSON/YAML)
│   ├── sample_test.json          # 샘플 테스트 케이스 (JSON)
│   ├── sample_test.yaml          # 샘플 테스트 케이스 (YAML)
│   └── anchor_test.yaml          # YAML anchor 예제
├── integration_test/             # Flutter Integration Test 러너
│   └── dsl_runner.dart           # JSON/YAML DSL을 Flutter 테스트로 변환
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

### 2. ChromeDriver 설치
ChromeDriver가 설치되어 있지 않으면 테스트 실행 시 자동으로 설치 여부를 물어봅니다.

원하는 경우 미리 수동으로 설치할 수 있습니다:

```bash
# 자동 설치 (Chrome 버전에 맞게 설치)
dart run bin/install_chromedriver.dart

# 또는 수동으로 ChromeDriver를 다운로드하여 drivers/chromedriver에 배치
```

## 사용법

### 테스트 실행

```bash
# 단일 테스트 파일 실행 (YAML 권장, JSON도 지원)
./test.sh test_dsl/sample_test.yaml

# 여러 테스트 파일 실행 (glob 패턴 사용)
./test.sh "test_dsl/*.yaml"
./test.sh "test_dsl/**/*.yaml"

# 다른 Flutter 앱 테스트 (자동 app_config.dart 생성)
./test.sh test_dsl/* --target-app ../myapp
./test.sh test_dsl/* --target-app /path/to/app

# 추가 Flutter 인자 전달 (--dart-define 등)
./test.sh test_dsl/* --dart-define flavor=local
./test.sh test_dsl/* --target-app ../myapp --dart-define ENV=prod

# 또는 앱 디렉토리 직접 지정 (수동 app_config.dart 필요)
./test.sh test_dsl/sample_test.yaml /path/to/flutter/app
```

`test.sh`는 `dart run bin/run_flutter_tests.dart`를 감싸는 간단한 스크립트이므로 필요하다면 기존 Dart 명령을 그대로 사용할 수도 있습니다.

**참고**: 테스트 실행 시 `integration_test/`와 `test_driver/` 디렉토리에 대한 심볼릭 링크가 생성되고, 테스트 완료 후 자동으로 삭제됩니다.

### 다른 Flutter 앱에서 사용하기

1. add integration_test dependency
   ```yaml
   dev_dependencies:
     flutter_test:
       sdk: flutter
     integration_test:
       sdk: flutter
   ```

2. **위젯에 Key 추가**: 테스트할 위젯에 식별 가능한 Key 추가
   ```dart
   TextFormField(
     key: const Key('username-input'),
     decoration: const InputDecoration(labelText: 'Username'),
   )
   ```

3. **테스트 DSL 작성**: 텍스트, `key:`, `type:` 셀렉터 사용
   ```yaml
   - action: type
     selector: "key:username-input"
     value: testuser
   ```

4. **테스트 실행**:
   ```bash
   ./test.sh my-test.yaml --target-app /path/to/your/flutter/app
   ```



### 테스트 DSL 형식

YAML 형식으로 테스트를 작성합니다 (JSON 형식도 지원).

```yaml
name: 테스트 스위트 이름
testCases:
  - description: 테스트 설명
    steps:
      - action: click|type|wait|assert_text|assert_visible
        selector: "셀렉터 (필요시)"
        value: 입력값 (type 액션용)
        expected: 예상값 (assert 액션용)
        waitTime: 대기시간 (밀리초)
        alias: account-input  # 이후 스텝에서 재사용할 별칭
```

#### YAML Anchor 사용 (재사용 가능한 스텝)

YAML anchor와 alias를 사용하여 반복되는 스텝을 재사용할 수 있습니다:

```yaml
name: YAML Anchor Example

# 재사용 가능한 스텝 정의
x-common-steps:
  wait-short: &wait-short
    action: wait
    waitTime: 500
  
  wait-long: &wait-long
    action: wait
    waitTime: 3000

testCases:
  - description: Example test with anchors
    steps:
      - *wait-long  # anchor 참조
      - action: click
        selector: "text:Button"
      - *wait-short
```

### 지원되는 액션

- `click`: 요소 클릭
- `type`: 텍스트 입력
- `wait`: 지정된 시간 대기
- `assert_text`: 텍스트 내용 검증
- `assert_visible`: 요소 가시성 검증

### 셀렉터 형식

셀렉터 형식:
- `Button Text` - 정확한 텍스트로 찾기 (접두사 불필요)
- `Button Text[0]` - 첫 번째 매칭되는 텍스트
- `contains:partial text` - 부분 텍스트로 찾기
- `contains:partial[1]` - 두 번째 매칭되는 부분 텍스트
- `key:my-widget-key` - Key로 찾기
- `key:my-key[0]` - 첫 번째 매칭되는 Key
- `label:Submit Button` - Semantics 라벨로 찾기
- `label:Submit[0]` - 첫 번째 매칭되는 Semantics 라벨
- `type:ElevatedButton` - 위젯 타입으로 찾기
- `type:TextField[2]` - 세 번째 매칭되는 위젯 타입
- `alias:별칭` - 이전 스텝에서 `alias:`로 저장한 Finder 재사용

동일한 위젯을 여러 번 참조해야 한다면 `alias:`를 사용하세요 (`selector`와 같은 수준에서 정의).

```yaml
- action: type
  selector: "label:Account"
  alias: account-input
  value: first@example.com

- action: type
  selector: "alias:account-input"
  value: second@example.com
```

**인덱스 사용**: 여러 개의 위젯이 매칭될 때 `[숫자]`를 추가하여 특정 순서의 위젯을 선택할 수 있습니다 (0부터 시작).

지원되는 위젯 타입:
- `ElevatedButton`, `TextButton`, `OutlinedButton`, `IconButton`
- `TextField`, `TextFormField`
- `Checkbox`, `Radio`, `Switch`

## 스크린샷 기능

### Flutter Integration Test
**현재 웹에서는 스크린샷이 작동하지 않습니다.**

- Flutter integration test의 `takeScreenshot()`이 웹에서 WebDriver 세션 문제로 hang됩니다
- 스크린샷 코드는 구현되어 있지만 비활성화되어 있습니다
- 모바일/데스크톱 플랫폼에서는 정상 작동할 수 있습니다
- 향후 WebDriver 세션 문제가 해결되면 재활성화 가능합니다

## 개발

새로운 액션을 추가하려면 `integration_test/dsl_runner.dart`의 `_executeStep` 함수를 수정하세요.
