/// Severity of a log record, ordered least → most severe.
enum LogLevel {
  debug(500, 'DEBUG'),
  info(800, 'INFO'),
  warning(900, 'WARNING'),
  error(1000, 'ERROR'),
  fatal(1200, 'FATAL');

  const LogLevel(this.value, this.label);

  /// `dart:developer` numeric level (also the ordering key).
  final int value;
  final String label;

  bool operator >=(LogLevel other) => value >= other.value;

  /// Warnings and above are forwarded to crash reporting as non-fatal records
  /// (fatals as fatal), so production issues surface without any UI.
  bool get reportsToCrashlytics => this >= LogLevel.warning;
}
