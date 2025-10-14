import 'dart:convert';

/// Defines the protocol for structured log messages exchanged between the DSL
/// runner and the host test runner.
class DslLogProtocol {
  DslLogProtocol._();

  /// Prefix used to signal structured log records.
  static const String prefix = r'$data=';

  /// Serialise a structured message into a log line.
  static String encode(String type, Map<String, dynamic> payload) {
    return '$prefix${jsonEncode({'type': type, 'payload': payload})}';
  }

  /// Attempt to parse a structured message from a log line. Returns null if the
  /// line does not contain a structured payload or parsing fails.
  static DslLogMessage? decode(String line) {
    if (!line.startsWith(prefix)) {
      return null;
    }

    final raw = line.substring(prefix.length);
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final type = decoded['type'];
      final payload = decoded['payload'];
      if (type is! String || payload is! Map) {
        return null;
      }
      return DslLogMessage(
        type: type,
        payload: Map<String, dynamic>.from(payload as Map),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Simple data holder for structured DSL log messages.
class DslLogMessage {
  const DslLogMessage({required this.type, required this.payload});

  final String type;
  final Map<String, dynamic> payload;
}

/// Known message type identifiers shared between the DSL runner and host.
class DslLogEventType {
  static const String sourceFile = 'source_file';
  static const String testCaseStart = 'test_case_start';
  static const String testCaseResult = 'test_case_result';
  static const String summary = 'summary';
}
