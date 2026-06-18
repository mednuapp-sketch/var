import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/service_booking_sheet.dart';
import '../../my_services/models/unified_booking.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  static const _themeColor = Color(0xFF0097A7);

  static const _palette = [
    Color(0xFF1565C0), Color(0xFFB71C1C), Color(0xFF6A1B9A),
    Color(0xFFC2185B), Color(0xFF2E7D32), Color(0xFF0097A7),
    Color(0xFFE65100), Color(0xFF37474F), Color(0xFF4527A0),
    Color(0xFF00838F), Color(0xFF283593), Color(0xFF558B2F),
  ];

  static const _icons = [
    Icons.science_rounded, Icons.bloodtype_rounded, Icons.medical_services_rounded,
    Icons.favorite_rounded, Icons.water_drop_rounded, Icons.wb_sunny_rounded,
    Icons.coronavirus_rounded, Icons.biotech_rounded, Icons.local_hospital_rounded,
    Icons.medication_rounded, Icons.vaccines_rounded, Icons.healing_rounded,
  ];

  String _query = '';

  Color _colorAt(int i) => _palette[i % _palette.length];
  IconData _iconAt(int i) => _icons[i % _icons.length];

  void _book(Map<String, dynamic> test) {
    ServiceBookingSheet.show(
      context,
      type: 'diagnostics',
      serviceName: test['name'] as String,
      themeColor: _themeColor,
      priceLabel: '₹${test['price']} • Reports in ${test['duration']}',
      amount: (test['price'] as num?)?.toInt() ?? 0,
      paymentDescription: 'Lab Test: ${test['name']}',
      serviceDetails: {
        'testName': test['name'],
        'price': test['price'],
        'reportTime': test['duration'],
      },
    );
  }

  void _bookHomeCollection() {
    ServiceBookingSheet.show(
      context,
      type: 'diagnostics',
      serviceName: 'Home Sample Collection',
      themeColor: _themeColor,
      priceLabel: 'FREE home collection by certified technician',
      serviceDetails: {'serviceType': 'home_collection', 'price': 0},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 160,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0097A7), Color(0xFF26C6DA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.biotech_rounded, color: Colors.white, size: 36),
                      const SizedBox(height: 8),
                      Text('Diagnostics & Lab Tests', style: AppTextStyles.onPrimaryH2),
                      Text('Home sample collection • Realtime availability', style: AppTextStyles.onPrimaryBody),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('services')
                  .where('type', isEqualTo: 'diagnostics')
                  .where('isEnabled', isEqualTo: true)
                  .snapshots(),
              builder: (ctx, snap) {
                return Column(children: [
                  // ── My Diagnostic Bookings (realtime) ─────────────────────
                  const _MyDiagnosticsBookings(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search tests...',
                        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textHint),
                                onPressed: () => setState(() => _query = ''),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _bookHomeCollection,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF0097A7), Color(0xFF26C6DA)]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(children: [
                        const Icon(Icons.home_rounded, color: Colors.white, size: 32),
                        const SizedBox(width: 12),
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('FREE Home Collection', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
                          Text('Technician visits your home', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
                        ])),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                          child: const Text('Book', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0097A7))),
                        ),
                      ]),
                    ),
                  ),
                  if (snap.connectionState == ConnectionState.waiting)
                    _buildSkeleton()
                  else if (snap.hasError)
                    _buildError()
                  else
                    _buildList(snap.data?.docs ?? []),
                  const SizedBox(height: 40),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          child: Row(children: [
            Container(width: 120, height: 16, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8))),
          ]),
        ),
        ...List.generate(5, (_) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 78,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
        )),
      ]),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text('Could not load tests', style: AppTextStyles.bodyMedium),
        const SizedBox(height: 8),
        TextButton(onPressed: () => setState(() {}), child: const Text('Retry')),
      ]),
    );
  }

  Widget _buildList(List<QueryDocumentSnapshot> docs) {
    final allTests = docs.asMap().entries.map((e) {
      final d = e.value.data() as Map<String, dynamic>;
      return {
        'id': e.value.id,
        'name': (d['name'] as String? ?? '').trim(),
        'price': (d['price'] as num?)?.toInt() ?? 0,
        'duration': (d['duration'] as String? ?? '').trim(),
        'description': (d['description'] as String? ?? '').trim(),
        'color': _colorAt(e.key),
        'icon': _iconAt(e.key),
      };
    }).toList();

    final filtered = _query.isEmpty
        ? allTests
        : allTests.where((t) => (t['name'] as String).toLowerCase().contains(_query.toLowerCase())).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          Text('Available Tests', style: AppTextStyles.h4),
          const Spacer(),
          if (_query.isNotEmpty)
            Text('${filtered.length} result${filtered.length == 1 ? '' : 's'}', style: AppTextStyles.bodySmall),
        ]),
      ),
      if (filtered.isEmpty)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Icon(_query.isNotEmpty ? Icons.search_off_rounded : Icons.biotech_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              _query.isNotEmpty ? 'No tests found for "$_query"' : 'No tests available yet',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (_query.isEmpty) ...[
              const SizedBox(height: 6),
              Text('Tests will appear here once added by the team', style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
            ],
          ]),
        )
      else
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: filtered.length,
          itemBuilder: (_, i) {
            final t = filtered[i];
            final color = t['color'] as Color;
            final duration = (t['duration'] as String);
            final desc = (t['description'] as String);
            final subtitle = duration.isNotEmpty ? 'Reports in $duration' : desc;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(t['icon'] as IconData, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t['name'] as String, style: AppTextStyles.labelLarge),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: AppTextStyles.bodySmall),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('₹${t['price']}', style: AppTextStyles.labelLarge.copyWith(color: _themeColor)),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => _book(t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF0097A7), Color(0xFF26C6DA)]),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Book Now', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ]),
              ]),
            );
          },
        ),
    ]);
  }
}

// ── My Diagnostic Bookings ────────────────────────────────────────────────────

class _MyDiagnosticsBookings extends StatelessWidget {
  const _MyDiagnosticsBookings();

  static const _themeColor = Color(0xFF0097A7);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('service_requests')
          .where('patientId', isEqualTo: uid)
          .where('type', isEqualTo: 'diagnostics')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snap) {
        // Don't render section at all until we know there are bookings
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('My Lab Tests', style: AppTextStyles.h4),
                  TextButton(
                    onPressed: () => context.push(AppRoutes.myServices),
                    child: const Text(
                      'View All',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: _themeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final booking = UnifiedBooking.fromServiceRequest(d, doc.id);
                return _DiagnosticBookingCard(
                  booking: booking,
                  onTap: () => context.push(AppRoutes.serviceDetail, extra: booking),
                );
              }),
              const SizedBox(height: 8),
              const Divider(),
            ],
          ),
        );
      },
    );
  }
}

class _DiagnosticBookingCard extends StatelessWidget {
  final UnifiedBooking booking;
  final VoidCallback onTap;
  const _DiagnosticBookingCard({required this.booking, required this.onTap});

  static const _themeColor = Color(0xFF0097A7);

  @override
  Widget build(BuildContext context) {
    final (statusBg, statusFg) = _statusColors(booking.status);
    final testName = (booking.rawData['serviceDetails']?['testName'] as String?)
        ?? booking.serviceName;
    final date = booking.date.isNotEmpty ? _fmt(booking.date) : '—';
    final time = booking.time.isNotEmpty ? booking.time : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _themeColor.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.biotech_rounded,
                  color: _themeColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(testName,
                      style: AppTextStyles.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 11, color: AppColors.textHint),
                      const SizedBox(width: 3),
                      Text(
                        time.isNotEmpty ? '$date  •  $time' : date,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    booking.status.label,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusFg,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textHint),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(String raw) {
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  (Color, Color) _statusColors(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
      case BookingStatus.requested:
        return (const Color(0xFFFFF3E0), const Color(0xFFE65100));
      case BookingStatus.confirmed:
        return (const Color(0xFFE3F2FD), const Color(0xFF1565C0));
      case BookingStatus.assigned:
        return (const Color(0xFFF3E5F5), const Color(0xFF6A1B9A));
      case BookingStatus.onTheWay:
      case BookingStatus.inProgress:
      case BookingStatus.sampleCollected:
        return (const Color(0xFFE0F7FA), const Color(0xFF00838F));
      case BookingStatus.completed:
      case BookingStatus.delivered:
        return (const Color(0xFFE8F5E9), AppColors.success);
      case BookingStatus.cancelled:
        return (const Color(0xFFFFEBEE), AppColors.error);
      default:
        return (const Color(0xFFF5F5F5), AppColors.textSecondary);
    }
  }
}
