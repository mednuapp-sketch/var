import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class CrashReportingService {
  CrashReportingService._();

  static void recordFlutterError(FlutterErrorDetails details) {
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(details);
    } else {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    }
  }

  static void recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) {
    if (kDebugMode) {
      developer.log(
        'Uncaught error [fatal=$fatal]: $error',
        name: 'CrashReporting',
        error: error,
        stackTrace: stack,
        level: 1000,
      );
    } else {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal);
    }
  }

  static void log(String message, {String? tag}) {
    developer.log(message, name: tag ?? 'MedNU');
    if (!kDebugMode) {
      FirebaseCrashlytics.instance.log(message);
    }
  }

  static void setUserId(String userId) {
    if (!kDebugMode) {
      FirebaseCrashlytics.instance.setUserIdentifier(userId);
    }
  }
}
