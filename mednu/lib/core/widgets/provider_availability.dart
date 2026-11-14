import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Partner "accepting orders" switch, as seen by patients.
///
/// A pharmacy / lab / equipment vendor can pause new orders from their own
/// dashboard. Like Zomato, patients still see that partner, but greyed out
/// with a "back soon" banner, and cannot add to cart / book from it. The flag
/// lives on the partner's public listing doc (`pharmacy_profiles.acceptingOrders`,
/// `lab_profiles.acceptingBookings`, `equipment_vendors.acceptingOrders`), so
/// the patient app joins it client-side instead of mirroring it onto every
/// catalogue item.

const String kNotAcceptingChipText = 'Not accepting orders right now · Back soon';

/// Friendly message when the patient taps a disabled action. [kind] is
/// "pharmacy", "lab" or "equipment vendor".
String notAcceptingMessage(String kind) =>
    "This $kind isn't accepting orders right now. It will be back soon.";

void showNotAcceptingSnack(BuildContext context, String kind) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(notAcceptingMessage(kind)),
      behavior: SnackBarBehavior.floating,
    ));
}

/// Ids of ACTIVE partners whose switch is currently off.
Set<String> _notAcceptingIds(QuerySnapshot<Map<String, dynamic>> snap, String field) => {
      for (final d in snap.docs)
        if (d.data()[field] == false) d.id,
    };

final unavailablePharmacyIdsProvider = StreamProvider<Set<String>>((ref) {
  return FirebaseFirestore.instance
      .collection('pharmacy_profiles')
      .where('status', isEqualTo: 'active')
      .snapshots()
      .map((s) => _notAcceptingIds(s, 'acceptingOrders'));
});

final unavailableLabIdsProvider = StreamProvider<Set<String>>((ref) {
  return FirebaseFirestore.instance
      .collection('lab_profiles')
      .where('status', isEqualTo: 'active')
      .snapshots()
      .map((s) => _notAcceptingIds(s, 'acceptingBookings'));
});

final unavailableEquipmentVendorIdsProvider = StreamProvider<Set<String>>((ref) {
  return FirebaseFirestore.instance
      .collection('equipment_vendors')
      .where('isEnabled', isEqualTo: true)
      .snapshots()
      .map((s) => _notAcceptingIds(s, 'acceptingOrders'));
});

/// Renders [child] as a greyscale, dimmed (Zomato-style "closed") card when
/// [unavailable] is true; otherwise returns it untouched. Taps still reach the
/// child, so callers decide what a tap does (usually: open the menu read-only).
class GreyscaleIfUnavailable extends StatelessWidget {
  final bool unavailable;
  final Widget child;
  const GreyscaleIfUnavailable({super.key, required this.unavailable, required this.child});

  static const ColorFilter _grey = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    if (!unavailable) return child;
    return Opacity(opacity: 0.6, child: ColorFiltered(colorFilter: _grey, child: child));
  }
}

/// Full-width banner / compact chip: "Not accepting orders right now · Back soon".
/// Place it OUTSIDE [GreyscaleIfUnavailable] so it keeps its own colour.
class NotAcceptingBanner extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  final bool compact;
  const NotAcceptingBanner({
    super.key,
    this.margin = EdgeInsets.zero,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    const fg = Color(0xFFB45309);
    return Container(
      width: double.infinity,
      margin: margin,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 6 : 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
        border: Border.all(color: const Color(0xFFFFD8A8)),
      ),
      child: Row(
        children: [
          Icon(Icons.pause_circle_outline_rounded, size: compact ? 14 : 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              kNotAcceptingChipText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: fg,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
