import 'dart:convert';
import 'dart:io';

class TestStep {
  final String action;
  final String? selector;
  final String? value;
  final String? expected;
  final int? waitTime;
  
  TestStep({
    required this.action,
    this.selector,
    this.value,
    this.expected,
    this.waitTime,
  });
  
  factory TestStep.fromJson(Map<String, dynamic> json) {
    return TestStep(
      action: json['action'] as String,
      selector: json['selector'] as String?,
      value: json['value'] as String?,
      expected: json['expected'] as String?,
      waitTime: json['waitTime'] as int?,
    );
  }
}

class TestCase {
  final String name;
  final String description;
  final String? url;
  final List<TestStep> steps;
  
  TestCase({
    required this.name,
    required this.description,
    this.url,
    required this.steps,
  });
  
  factory TestCase.fromJson(Map<String, dynamic> json) {
    return TestCase(
      name: json['name'] as String,
      description: json['description'] as String,
      url: json['url'] as String?,
      steps: (json['steps'] as List)
          .map((step) => TestStep.fromJson(step as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TestSuite {
  final String name;
  final String baseUrl;
  final List<TestCase> testCases;
  
  TestSuite({
    required this.name,
    required this.baseUrl,
    required this.testCases,
  });
  
  factory TestSuite.fromJson(Map<String, dynamic> json) {
    return TestSuite(
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      testCases: (json['testCases'] as List)
          .map((testCase) => TestCase.fromJson(testCase as Map<String, dynamic>))
          .toList(),
    );
  }
  
  static Future<TestSuite> loadFromFile(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    return TestSuite.fromJson(json);
  }
}
