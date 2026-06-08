import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum NetworkStatus { online, offline }

/// Watches the device network state and exposes it as a Riverpod stream.
class ConnectivityService {
  ConnectivityService._();

  static final _connectivity = Connectivity();

  /// One-shot check — resolves immediately.
  static Future<bool> isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return _isConnectedSingle(result);
  }

  /// Stream of network status changes.
  static Stream<NetworkStatus> get statusStream =>
      _connectivity.onConnectivityChanged.map(
        (result) => _isConnectedSingle(result) ? NetworkStatus.online : NetworkStatus.offline,
      );

  static bool _isConnectedSingle(ConnectivityResult result) =>
      result == ConnectivityResult.mobile ||
      result == ConnectivityResult.wifi ||
      result == ConnectivityResult.ethernet;
}

// ── Riverpod providers ────────────────────────────────────────────────────

final connectivityStatusProvider = StreamProvider<NetworkStatus>((ref) {
  return ConnectivityService.statusStream;
});

final isOnlineProvider = Provider<bool>((ref) {
  final status = ref.watch(connectivityStatusProvider);
  return status.maybeWhen(
    data: (s) => s == NetworkStatus.online,
    orElse: () => true, // assume online if status unknown — avoids false offline banners
  );
});
