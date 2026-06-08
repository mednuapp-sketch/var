import 'package:cloud_firestore/cloud_firestore.dart';

class SavedAddress {
  final String id;
  final String label;       // 'home' | 'work' | 'other'
  final String customLabel; // used when label == 'other'
  final String plotNo;
  final String building;
  final String street;
  final String landmark;
  final String area;
  final String city;
  final String state;
  final String pincode;
  final double lat;
  final double lng;
  final bool isDefault;

  const SavedAddress({
    required this.id,
    required this.label,
    this.customLabel = '',
    this.plotNo = '',
    this.building = '',
    this.street = '',
    this.landmark = '',
    this.area = '',
    required this.city,
    this.state = '',
    this.pincode = '',
    required this.lat,
    required this.lng,
    this.isDefault = false,
  });

  String get displayLabel {
    if (label == 'other' && customLabel.isNotEmpty) return customLabel;
    return label[0].toUpperCase() + label.substring(1);
  }

  String get formattedAddress {
    final parts = <String>[];
    if (plotNo.isNotEmpty) parts.add(plotNo);
    if (building.isNotEmpty) parts.add(building);
    if (street.isNotEmpty) parts.add(street);
    if (landmark.isNotEmpty) parts.add('Near $landmark');
    if (area.isNotEmpty) parts.add(area);
    if (city.isNotEmpty) parts.add(city);
    if (pincode.isNotEmpty) parts.add(pincode);
    return parts.isEmpty ? city : parts.join(', ');
  }

  String get shortAddress {
    final parts = <String>[];
    if (building.isNotEmpty) parts.add(building);
    else if (area.isNotEmpty) parts.add(area);
    if (city.isNotEmpty) parts.add(city);
    return parts.isEmpty ? city : parts.join(', ');
  }

  Map<String, dynamic> toMap() => {
        'label': label,
        'customLabel': customLabel,
        'plotNo': plotNo,
        'building': building,
        'street': street,
        'landmark': landmark,
        'area': area,
        'city': city,
        'state': state,
        'pincode': pincode,
        'lat': lat,
        'lng': lng,
        'isDefault': isDefault,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory SavedAddress.fromDoc(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return SavedAddress(
      id: doc.id,
      label: d['label'] as String? ?? 'other',
      customLabel: d['customLabel'] as String? ?? '',
      plotNo: d['plotNo'] as String? ?? '',
      building: d['building'] as String? ?? '',
      street: d['street'] as String? ?? '',
      landmark: d['landmark'] as String? ?? '',
      area: d['area'] as String? ?? '',
      city: d['city'] as String? ?? '',
      state: d['state'] as String? ?? '',
      pincode: d['pincode'] as String? ?? '',
      lat: (d['lat'] as num?)?.toDouble() ?? 0,
      lng: (d['lng'] as num?)?.toDouble() ?? 0,
      isDefault: d['isDefault'] as bool? ?? false,
    );
  }

  SavedAddress copyWith({
    String? id,
    String? label,
    String? customLabel,
    String? plotNo,
    String? building,
    String? street,
    String? landmark,
    String? area,
    String? city,
    String? state,
    String? pincode,
    double? lat,
    double? lng,
    bool? isDefault,
  }) =>
      SavedAddress(
        id: id ?? this.id,
        label: label ?? this.label,
        customLabel: customLabel ?? this.customLabel,
        plotNo: plotNo ?? this.plotNo,
        building: building ?? this.building,
        street: street ?? this.street,
        landmark: landmark ?? this.landmark,
        area: area ?? this.area,
        city: city ?? this.city,
        state: state ?? this.state,
        pincode: pincode ?? this.pincode,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        isDefault: isDefault ?? this.isDefault,
      );
}
