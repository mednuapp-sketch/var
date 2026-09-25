import 'package:geolocator/geolocator.dart';
import 'hospital_service.dart';

/// A registered [Hospital] with a distance computed from the patient's
/// current position — [NearbyHospitalCard] displays this directly.
///
/// `isMednu` is always true here: this panel now only shows hospitals from
/// our own `hospitals` catalog (see `HospitalsScreen`'s doc comment for
/// why), so every entry is one. `rating`/`userRatingsTotal` no longer come
/// from anywhere (Google Places is gone) — they stay as nullable fields so
/// [NearbyHospitalCard]'s rating chip simply never renders instead of
/// needing its own rewrite.
class NearbyHospital {
  final String id;
  final String name;
  final String address;
  final String phone;
  final String mapsUrl;
  final bool isEmergency;
  final bool isMednu;
  final double? lat;
  final double? lng;
  final double? distanceKm;
  final double? rating;
  final int? userRatingsTotal;

  /// The real `hospitals` Firestore doc id — always equal to [id] here,
  /// kept as a separate field because the booking/pay-bill actions read
  /// this name specifically.
  final String? mednuId;

  const NearbyHospital({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.mapsUrl,
    required this.isEmergency,
    required this.isMednu,
    this.mednuId,
    this.lat,
    this.lng,
    this.distanceKm,
    this.rating,
    this.userRatingsTotal,
  });
}

class NearbyHospitalService {
  /// Builds the patient-facing list directly from our own hospital catalog
  /// — no external API call. Distance is only ever set for a hospital whose
  /// billing-desk registration captured a location (see
  /// `onHospitalProfileApproved` in functions/index.js); every other entry
  /// just has a null [NearbyHospital.distanceKm].
  List<NearbyHospital> fromHospitals({
    required List<Hospital> mednuHospitals,
    double? userLat,
    double? userLng,
  }) {
    return mednuHospitals.map((h) {
      double? distanceKm;
      if (userLat != null && userLng != null && h.latitude != null && h.longitude != null) {
        distanceKm = Geolocator.distanceBetween(userLat, userLng, h.latitude!, h.longitude!) / 1000;
      }
      return NearbyHospital(
        id: h.id,
        name: h.name,
        address: h.address,
        phone: h.phone,
        mapsUrl: h.mapsUrl,
        isEmergency: h.isEmergency,
        isMednu: true,
        mednuId: h.id,
        lat: h.latitude,
        lng: h.longitude,
        distanceKm: distanceKm,
      );
    }).toList();
  }
}

final nearbyHospitalService = NearbyHospitalService();
