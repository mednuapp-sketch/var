import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks the active bottom-nav tab index (0=Home, 1=Doctors, 2=My Services, 3=Profile).
/// Child screens can write to this to switch tabs without needing a callback.
final bottomNavIndexProvider = StateProvider<int>((ref) => 0);
