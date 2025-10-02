# Flutter Web Integration Test

Integration test framework for Flutter web applications built on top of Chrome WebDriver.

## Project Structure

```
dart-web-integration-test/
├── lib/                          # Core library code
│   ├── chrome_driver_manager.dart # ChromeDriver management
│   └── test_dsl_parser.dart       # JSON/YAML test DSL parser
├── bin/                          # Executables
│   └── run_flutter_tests.dart    # Flutter integration test runner
├── test_dsl/                     # Test DSL files (JSON/YAML)
│   ├── sample_test.json          # Sample test case (JSON)
│   ├── sample_test.yaml          # Sample test case (YAML)
│   └── anchor_test.yaml          # YAML anchor example
├── integration_test/             # Flutter integration test runner
│   └── dsl_runner.dart           # Converts JSON/YAML DSL into Flutter tests
├── test_driver/                  # Flutter driver
│   └── integration_test.dart     # Integration test driver
├── test_target/                  # Standalone Flutter web app under test
│   ├── lib/main.dart             # Flutter app entry point
│   ├── pubspec.yaml              # Flutter project configuration
│   └── web/                      # Web build assets
├── drivers/                      # ChromeDriver binaries
├── screenshots/                  # Screenshot output when tests fail
├── config/                       # Configuration files
│   └── chromedriver_config.json  # ChromeDriver settings
└── test/                         # Unit tests
```

## Installation and Setup

### 1. Install dependencies
```bash
dart pub get
```

### 2. Install ChromeDriver
If ChromeDriver is not installed, the test runner will ask whether it should install it automatically when you launch the tests.

You can also install it manually in advance:

```bash
# Automatic installation (downloads the matching version for Chrome)
dart run bin/install_chromedriver.dart

# Or download ChromeDriver yourself and place it under drivers/chromedriver
```

### 3. Run the Flutter web app
```bash
# Launch the Flutter web app from the test_target directory
cd test_target
flutter run -d chrome --web-port 3001
```


## Usage

### Run tests

```bash
# Run a single test file (YAML preferred, JSON also supported)
dart run bin/run_flutter_tests.dart test_dsl/sample_test.yaml

# Run multiple test files (supports glob patterns)
dart run bin/run_flutter_tests.dart "test_dsl/*.yaml"
dart run bin/run_flutter_tests.dart "test_dsl/**/*.yaml"

# Test a different Flutter app (auto-generates app_config.dart)
dart run bin/run_flutter_tests.dart test_dsl/* --target-app ../myapp
dart run bin/run_flutter_tests.dart test_dsl/* --target-app /path/to/app

# Pass additional Flutter arguments (e.g., --dart-define)
dart run bin/run_flutter_tests.dart test_dsl/* --dart-define flavor=local
dart run bin/run_flutter_tests.dart test_dsl/* --target-app ../myapp --dart-define ENV=prod

# Alternatively, point directly to an app directory (requires manual app_config.dart)
dart run bin/run_flutter_tests.dart test_dsl/sample_test.yaml /path/to/flutter/app
```

**Note**: When tests run, symbolic links to `integration_test/` and `test_driver/` are created and automatically removed when execution finishes.

### Use with another Flutter app

1. Add the `integration_test` dependency
   ```yaml
   dev_dependencies:
     flutter_test:
       sdk: flutter
     integration_test:
       sdk: flutter
   ```

2. **Add Keys to widgets**: Add identifiable keys to the widgets you want to test
   ```dart
   TextFormField(
     key: const Key('username-input'),
     decoration: const InputDecoration(labelText: 'Username'),
   )
   ```

3. **Write the test DSL**: Use selectors like text, `key:`, and `type:`
   ```yaml
   - action: type
     selector: "key:username-input"
     value: testuser
   ```

4. **Run the tests**
   ```bash
   dart run bin/run_flutter_tests.dart my-test.yaml --target-app /path/to/your/flutter/app
   ```


### Test DSL format

Write your tests in YAML (JSON is also supported).

```yaml
name: Test suite name
testCases:
  - description: Test description
    steps:
      - action: click|type|wait|assert_text|assert_visible
        selector: "Selector (if needed)"
        value: Input value (for type actions)
        expected: Expected value (for assert actions)
        waitTime: Wait time in milliseconds
```

#### Using YAML anchors (reusable steps)

Use YAML anchors and aliases to reuse repeated steps:

```yaml
name: YAML Anchor Example

# Reusable step definitions
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
      - *wait-long  # reference an anchor
      - action: click
        selector: "text:Button"
      - *wait-short
```

### Supported actions

- `click`: Tap or click a widget
- `type`: Enter text
- `wait`: Pause for the given duration
- `assert_text`: Verify widget text
- `assert_visible`: Verify widget visibility

### Selector formats

Selectors can be written as:
- `Button Text` - Match exact text (no prefix required)
- `Button Text[0]` - Select the first match with that text
- `contains:partial text` - Match partial text
- `contains:partial[1]` - Select the second match for a partial text
- `key:my-widget-key` - Match by widget key
- `key:my-key[0]` - Select the first match by key
- `label:Submit Button` - Match by semantics label
- `label:Submit[0]` - Select the first match for a semantics label
- `type:ElevatedButton` - Match by widget type
- `type:TextField[2]` - Select the third match for a widget type

**Using indexes**: When multiple widgets match, append `[number]` to target a specific instance (0-based).

Supported widget types:
- `ElevatedButton`, `TextButton`, `OutlinedButton`, `IconButton`
- `TextField`, `TextFormField`
- `Checkbox`, `Radio`, `Switch`

## Screenshot support

### Flutter integration test
**Screenshots are currently not available on the web.**

- `takeScreenshot()` in Flutter integration tests hangs on the web because of WebDriver session issues
- The screenshot code is implemented but disabled
- It should work on mobile and desktop platforms
- Once the WebDriver session issue is resolved, screenshots can be re-enabled

## Development

To add a new action, modify the `_executeStep` function in `integration_test/dsl_runner.dart`.
