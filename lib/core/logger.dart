// Aanchal — Logger
//
// Structured logging wrapper using the logger package.

import 'package:logger/logger.dart';

final log = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 5,
    lineLength: 80,
    colors: true,
    printEmojis: false,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);

/// Scoped log helper for tagged output.
void logInfo(String tag, String message) => log.i('[$tag] $message');
void logWarn(String tag, String message) => log.w('[$tag] $message');
void logError(String tag, String message, [Object? error]) =>
    log.e('[$tag] $message', error: error);
void logDebug(String tag, String message) => log.d('[$tag] $message');
