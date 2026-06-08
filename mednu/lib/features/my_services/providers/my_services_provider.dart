import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/unified_booking.dart';
import '../services/my_services_service.dart';

/// Stream of ALL bookings, merged from all collections.
final allBookingsProvider = StreamProvider<List<UnifiedBooking>>((ref) {
  return MyServicesService.allBookingsStream();
});

/// Active bookings (pending → in-progress, not yet done or cancelled).
final activeBookingsProvider = Provider<AsyncValue<List<UnifiedBooking>>>((ref) {
  return ref.watch(allBookingsProvider).whenData(
      (list) => list.where((b) => b.isActive).toList());
});

/// Completed bookings.
final completedBookingsProvider =
    Provider<AsyncValue<List<UnifiedBooking>>>((ref) {
  return ref.watch(allBookingsProvider).whenData(
      (list) => list.where((b) => b.isCompleted).toList());
});

/// Cancelled bookings.
final cancelledBookingsProvider =
    Provider<AsyncValue<List<UnifiedBooking>>>((ref) {
  return ref.watch(allBookingsProvider).whenData(
      (list) => list.where((b) => b.isCancelled).toList());
});

/// Realtime detail stream for a single booking document.
final bookingDetailProvider =
    StreamProvider.family<UnifiedBooking?, UnifiedBooking>((ref, booking) {
  return MyServicesService.bookingDetailStream(booking);
});
