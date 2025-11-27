import 'dart:developer' as developer;

class Logger {
  static void debug(String message, [String? tag]) {
    developer.log(
      message,
      name: tag ?? 'OFFLINK',
      level: 700, // Debug level
    );
  }

  static void info(String message, [String? tag]) {
    developer.log(
      message,
      name: tag ?? 'OFFLINK',
      level: 800, // Info level
    );
  }

  static void warning(String message, [String? tag]) {
    developer.log(
      message,
      name: tag ?? 'OFFLINK',
      level: 900, // Warning level
    );
  }

  static void error(String message, [Object? error, StackTrace? stackTrace, String? tag]) {
    developer.log(
      message,
      name: tag ?? 'OFFLINK',
      level: 1000, // Error level
      error: error,
      stackTrace: stackTrace,
    );
  }
}




