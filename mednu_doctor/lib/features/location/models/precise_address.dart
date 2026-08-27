/// A map-picked address, resolved from either a place search result or a
/// reverse-geocoded pin position. Mirrors the mednu (patient) app's
/// `PreciseAddress` so the same component breakdown/formatting rules apply.
class PreciseAddress {
  final String? plotNo; // subThoroughfare / house / plot number
  final String? building; // building / POI name
  final String? street; // street name
  final String? area; // neighbourhood / sublocality
  final String? city;
  final String? state;
  final String? pincode;
  final double lat;
  final double lng;

  const PreciseAddress({
    this.plotNo,
    this.building,
    this.street,
    this.area,
    this.city,
    this.state,
    this.pincode,
    required this.lat,
    required this.lng,
  });

  /// Full formatted address for display and for storing on a profile.
  String get formatted {
    final parts = <String>[];
    if (plotNo?.isNotEmpty == true) parts.add(plotNo!);
    if (building?.isNotEmpty == true && building != street) parts.add(building!);
    if (street?.isNotEmpty == true) parts.add(street!);
    if (area?.isNotEmpty == true) parts.add(area!);
    if (city?.isNotEmpty == true) parts.add(city!);
    if (pincode?.isNotEmpty == true) parts.add(pincode!);
    return parts.isEmpty ? (city ?? 'Selected location') : parts.join(', ');
  }

  /// Short label — area/city only.
  String get short =>
      area?.isNotEmpty == true
          ? area!
          : city?.isNotEmpty == true
              ? city!
              : 'Selected location';
}
