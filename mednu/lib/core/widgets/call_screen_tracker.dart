import 'package:flutter/foundation.dart';

/// Counts call screens (ringing, lobby, live call) currently on screen so the
/// global ActiveSessionBridge can hide itself over them regardless of how the
/// route was pushed — URL matching alone misses imperatively pushed routes.
class CallScreenTracker {
  CallScreenTracker._();

  static final ValueNotifier<int> open = ValueNotifier<int>(0);

  static bool get isOnCallScreen => open.value > 0;

  // Deferred like leave(): enter() runs from initState, i.e. mid-build, and
  // ActiveSessionBridge's listener calls setState — doing that synchronously
  // threw "setState() called during build". Microtasks keep enter/leave order.
  static void enter() => Future.microtask(() => open.value++);

  // Deferred: leave() runs from State.dispose, mid-teardown, when listeners
  // must not trigger a rebuild.
  static void leave() => Future.microtask(() {
        if (open.value > 0) open.value--;
      });
}
