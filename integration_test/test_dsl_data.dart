// Auto-generated file - do not edit
// Generated from: test_dsl/anchor_test.yaml

const String testDslJson = '''
{"name":"YAML Anchor Test","baseUrl":"http://localhost:3001","x-common-steps":{"wait-short":{"action":"wait","waitTime":500},"wait-long":{"action":"wait","waitTime":3000}},"testCases":[{"name":"Test with Anchors","description":"Demonstrate YAML anchor usage","url":"http://localhost:3001/#/","steps":[{"action":"wait","waitTime":3000},{"action":"assert_text","selector":"text:Welcome to Test Target","expected":"Welcome to Test Target"},{"action":"click","selector":"text:About"},{"action":"wait","waitTime":500},{"action":"assert_text","selector":"text:About Us","expected":"About Us"}]}]}
''';
