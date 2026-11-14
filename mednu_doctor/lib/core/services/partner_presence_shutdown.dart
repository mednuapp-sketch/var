import '../../features/ambulance/services/ambulance_location_service.dart';
import 'ambulance_presence_service.dart';
import 'counsellor_presence_service.dart';
import 'physio_presence_service.dart';

/// Switches Physio / Counsellor / Ambulance presence off and tears down their
/// timers + foreground services. Their dashboards no longer do this in
/// `dispose()` (so partners stay online across tab changes), so it must run
/// explicitly on sign-out — and before Firebase Auth is cleared, so the
/// Firestore write is still authorised.
class PartnerPresenceShutdown {
  PartnerPresenceShutdown._();

  static Future<void> goOfflineAll() async {
    Future<void> safe(Future<void> Function() f) async {
      try {
        await f();
      } catch (_) {}
    }

    if (PhysioPresenceService.instance.isOnline) {
      await safe(() => PhysioPresenceService.instance.setOnline(false));
    }
    if (CounsellorPresenceService.instance.isOnline) {
      await safe(() => CounsellorPresenceService.instance.setOnline(false));
    }
    if (AmbulancePresenceService.instance.isOnline) {
      await safe(() => AmbulanceLocationService.stopTracking());
      await safe(() => AmbulancePresenceService.instance.setOnline(false));
    }
    await safe(() => PhysioPresenceService.instance.dispose());
    await safe(() => CounsellorPresenceService.instance.dispose());
    await safe(() => AmbulancePresenceService.instance.dispose());
  }
}
