import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';

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
  final String description;
  final List<TestStep> steps;
  
  TestCase({
    required this.description,
    required this.steps,
  });
  
  factory TestCase.fromJson(Map<String, dynamic> json) {
    return TestCase(
      description: json['description'] as String,
      steps: (json['steps'] as List)
          .map((step) => TestStep.fromJson(step as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TestSuite {
  final String name;
  final List<TestCase> testCases;
  
  TestSuite({
    required this.name,
    required this.testCases,
  });
  
  factory TestSuite.fromJson(Map<String, dynamic> json) {
    return TestSuite(
      name: json['name'] as String,
      testCases: (json['testCases'] as List)
          .map((testCase) => TestCase.fromJson(testCase as Map<String, dynamic>))
          .toList(),
    );
  }
  
  static Future<TestSuite> loadFromFile(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    
    Map<String, dynamic> data;
    if (filePath.endsWith('.yaml') || filePath.endsWith('.yml')) {
      final yaml = loadYaml(content);
      data = _convertYamlToMap(yaml);
    } else {
      data = jsonDecode(content) as Map<String, dynamic>;
    }
    
    return TestSuite.fromJson(data);
  }
  
  static Map<String, dynamic> _convertYamlToMap(dynamic yaml) {
    if (yaml is YamlMap) {
      return Map<String, dynamic>.from(yaml.map((key, value) => MapEntry(key.toString(), _convertYamlToMap(value))));
    } else if (yaml is YamlList) {
      throw UnsupportedError('Yaml lists are not supported');
    } else {
      return yaml;
    }
  }
}
