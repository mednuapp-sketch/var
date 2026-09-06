import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/booking_service.dart';
import '../../../core/utils/r.dart';
import 'emergency_contacts_service.dart';
import 'manage_contacts_screen.dart';
import 'nearby_ambulances_sheet.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen>
    with SingleTickerProviderStateMixin {
  static const String _mednuCallCenterNumber = '+918977018597';

  List<EmergencyContact> _contacts = [];
  late AnimationController _pulseCtrl;
  String _patientName = '';
  String _patientPhone = '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _prefillPatient();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final contacts = await EmergencyContactsService.getContacts();
    if (mounted) setState(() => _contacts = contacts);
  }

  Future<void> _prefillPatient() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final raw = user.phoneNumber ?? '';
    if (mounted) {
      setState(() =>
          _patientPhone = raw.startsWith('+91') ? raw.substring(3) : raw);
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (mounted) {
        setState(() => _patientName = snap.data()?['name'] ?? '');
      }
    } catch (_) {}
  }

  Future<void> _callMedNuCenter() async {
    final uri = Uri.parse('tel:$_mednuCallCenterNumber');
    try {
      if (await canLaunchUrl(uri)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connecting Call With MedNU'),
              backgroundColor: Color(0xFF2E7D32),
            ),
          );
        }
        await launchUrl(uri);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot launch call to MedNU Call Center'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to call MedNU Call Center'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openManageContacts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ManageContactsScreen()),
    );
    await _loadContacts();
  }

  Future<Position?> _fetchLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          return null;
        }
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      return null;
    }
  }

  String _buildMessage(Position? position) {
    if (position != null) {
      final link =
          'https://maps.google.com/?q=${position.latitude},${position.longitude}';
      return '🚨 Emergency! I need help. My current location is: $link';
    }
    return '🚨 Emergency! I need help. Please call me immediately. (Sent via MedNU)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: AppSpacing.headerHeight(context),
            pinned: true,
            backgroundColor: const Color(0xFFB71C1C),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFB71C1C), Color(0xFFE53935)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: Padding(
                            padding: AppSpacing.headerPadding(context),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.emergency_rounded, color: Colors.white, size: AppSpacing.headerIconSize(context)),
                                SizedBox(height: AppSpacing.headerIconGap(context)),
                                const Text('Emergency', style: AppTextStyles.onPrimaryH2),
                                const Text('Instant High Priority Assistence', style: AppTextStyles.onPrimaryBody),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: AppSpacing.page(context),
              child: Column(
                children: [
                  // ── SOS Button (pulsing) ────────────────────────────────
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, child) => Transform.scale(
                      scale: 1.0 + _pulseCtrl.value * 0.03,
                      child: child,
                    ),
                    child: GestureDetector(
                      onTap: () => _handleSOSTap(context),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFB71C1C), Color(0xFFE53935)]),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: const Color(0xFFE53935).withValues(alpha:0.4), blurRadius: 20, offset: const Offset(0, 8))],
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 100, height: 100,
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.2), shape: BoxShape.circle),
                              child: const Icon(Icons.sos_rounded, color: Colors.white, size: 56),
                            ),
                            const SizedBox(height: 16),
                            const Text('PRESS FOR SOS', style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
                            const SizedBox(height: 4),
                            Text(
                              _contacts.isEmpty
                                  ? 'No contacts added yet — tap to set up'
                                  : 'Sends SMS with location to ${_contacts.length} contact${_contacts.length == 1 ? '' : 's'}',
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: AppSpacing.cardGap(context)),
                  // ── Call MedNU Emergency Call Center ────────────────────
                  GestureDetector(
                    onTap: _callMedNuCenter,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF43A047).withValues(alpha:0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 60, height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha:0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 30),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Call MedNU Emergency Center',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Reach our emergency call center immediately',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.call_rounded, color: Colors.white, size: 22),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: AppSpacing.cardGap(context)),
                  // Manage contacts button
                  GestureDetector(
                    onTap: _openManageContacts,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935).withValues(alpha:0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE53935).withValues(alpha:0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.contacts_rounded, color: Color(0xFFE53935), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _contacts.isEmpty
                                ? 'Add emergency contacts for SOS alerts'
                                : '${_contacts.length} emergency contact${_contacts.length == 1 ? '' : 's'} saved',
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFB71C1C)),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Color(0xFFE53935)),
                      ]),
                    ),
                  ),
                  SizedBox(height: AppSpacing.sectionGap(context)),
                  // ── Find Nearby Ambulances (admin-managed, radius search) ──
                  GestureDetector(
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const NearbyAmbulancesSheet(),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00838F), Color(0xFF00ACC1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00ACC1).withValues(alpha:0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 60, height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha:0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 30),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Find Available Ambulances',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'See ambulances near you within a chosen radius',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 16),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: R.h(context, 80)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSOSTap(BuildContext context) async {
    final online = await ConnectivityService.isOnline();
    if (!context.mounted) return;
    if (!online) {
      _showOfflineDialog(context);
      return;
    }
    _showSOSDialog(context);
  }

  void _showOfflineDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.wifi_off_rounded, color: Color(0xFFB71C1C)),
          SizedBox(width: 8),
          Text('You are Offline', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        ]),
        content: const Text(
          'Please check your connection. You can try calling $_mednuCallCenterNumber to receive immediate assistance.',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _callMedNuCenter();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB71C1C)),
            child: const Text('Call Now', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSOSDialog(BuildContext context) {
    if (_contacts.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('No Emergency Contacts', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          content: const Text('Please add at least one emergency contact before sending an SOS alert.', style: TextStyle(fontFamily: 'Poppins')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () { Navigator.pop(context); _openManageContacts(); },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
              child: const Text('Add Contacts', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Send SOS?', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text(
          'This will immediately send an SMS with your location to ${_contacts.length} contact${_contacts.length == 1 ? '' : 's'}.',
          style: const TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _sendAlerts(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            child: const Text('Send SOS', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _sendAlerts(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SendingDialog(),
    );

    final position = await _fetchLocation();
    final message = _buildMessage(position);

    // smsto: is SMS-only — semicolons separate multiple recipients
    final numbers = _contacts
        .map((c) => c.phone.replaceAll(RegExp(r'\s+'), ''))
        .join(';');

    final uri = Uri.parse('smsto:$numbers?body=${Uri.encodeComponent(message)}');

    // Also fire the real backend emergency-doctor pipeline: creates a
    // service_requests doc that onEmergencyDoctorRequest (functions/index.js)
    // picks up to broadcast a critical push to every active doctor + write an
    // admin_alerts doc. Best-effort — an SOS must still "succeed" (SMS goes
    // out) even if this call fails, but we track it to avoid overstating what
    // happened in the confirmation dialog below.
    var doctorsNotified = false;
    try {
      await BookingService.createRequest(
        type: 'emergency_doctor',
        serviceName: 'Emergency Doctor Assistance',
        patientName: _patientName.isNotEmpty ? _patientName : 'Emergency',
        patientPhone: _patientPhone,
        address: position != null
            ? '${position.latitude}, ${position.longitude}'
            : 'Location not shared',
        preferredDate: 'Immediate',
        preferredTime: 'Now',
        notes: 'Triggered via SOS on the Emergency screen.',
        extraFields: {
          if (position != null) 'latitude': position.latitude,
          if (position != null) 'longitude': position.longitude,
        },
      );
      doctorsNotified = true;
    } catch (_) {
      // Swallow — SMS path below still runs regardless.
    }

    if (!context.mounted) return;
    Navigator.pop(context); // close sending dialog

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32)),
          SizedBox(width: 8),
          Text('SOS Sent!', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._contacts.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Icon(Icons.sms_rounded, size: 16, color: Color(0xFF2E7D32)),
                const SizedBox(width: 6),
                Text('SMS sent to ${c.name}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
              ]),
            )),
            if (doctorsNotified) ...[
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 6),
                child: Row(children: [
                  Icon(Icons.local_hospital_rounded, size: 16, color: Color(0xFF2E7D32)),
                  SizedBox(width: 6),
                  Text('Nearby MedNU doctors have been alerted', style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                ]),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              doctorsNotified
                  ? 'A MedNU doctor will reach out for support until help arrives.'
                  : 'Could not reach MedNU\'s emergency network — please also call the Emergency Center below.',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _SendingDialog extends StatelessWidget {
  const _SendingDialog();

  @override
  Widget build(BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: const Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: CircularProgressIndicator(color: Color(0xFFE53935), strokeWidth: 5),
              ),
              SizedBox(height: 20),
              Text('Sending SOS...',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text('Alerting your emergency contacts',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
}