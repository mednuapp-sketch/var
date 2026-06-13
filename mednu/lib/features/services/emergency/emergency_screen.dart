import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import 'emergency_contacts_service.dart';
import 'manage_contacts_screen.dart';
import '../../hospitals/services/hospital_service.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  List<EmergencyContact> _contacts = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  bool _requestingDoctor = false;

  Future<void> _loadContacts() async {
    final contacts = await EmergencyContactsService.getContacts();
    if (mounted) setState(() => _contacts = contacts);
  }

  Future<void> _requestEmergencyDoctor() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _requestingDoctor = true);

    try {
      final position = await _fetchLocation();

      await FirebaseFirestore.instance.collection('service_requests').add({
        'type': 'emergency_doctor',
        'priority': 'high',
        'patientId': uid,
        'status': 'pending',
        if (position != null) ...{
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => _requestingDoctor = false);

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.medical_services_rounded, color: Color(0xFF6A1B9A)),
            SizedBox(width: 8),
            Text('Request Sent!', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          ]),
          content: const Text(
            'A doctor will be assigned to your case shortly.\nProceed to consultation to connect when available.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Stay Here')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.push(AppRoutes.consultation);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6A1B9A)),
              child: const Text('Go to Consultation', style: TextStyle(color: Colors.white, fontFamily: 'Poppins', fontSize: 12)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _requestingDoctor = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to request doctor. Please try again.')),
      );
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
            perm == LocationPermission.deniedForever) return null;
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
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
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
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.emergency_rounded, color: Colors.white, size: 40),
                        const SizedBox(height: 8),
                        Text('Emergency Services', style: AppTextStyles.onPrimaryH2),
                        Text('Quick help when you need it most', style: AppTextStyles.onPrimaryBody),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // ── Emergency Doctor Support ────────────────────────────
                  GestureDetector(
                    onTap: _requestingDoctor ? null : _requestEmergencyDoctor,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7B1FA2).withValues(alpha:0.35),
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
                            child: _requestingDoctor
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                  )
                                : const Icon(Icons.medical_services_rounded, color: Colors.white, size: 30),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Emergency Doctor',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _requestingDoctor
                                      ? 'Finding a doctor for you…'
                                      : 'Instant high-priority doctor assignment',
                                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ── SOS Button ──────────────────────────────────────────
                  GestureDetector(
                    onTap: () => _showSOSDialog(context),
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
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 24),
                  Align(alignment: Alignment.centerLeft, child: Text('Quick Emergency Contacts', style: AppTextStyles.h4)),
                  const SizedBox(height: 12),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    childAspectRatio: 1.6,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    children: const [
                      _EmergencyCard('🚑', 'Ambulance', '108', Color(0xFFE53935)),
                      _EmergencyCard('👮', 'Police', '100', Color(0xFF1565C0)),
                      _EmergencyCard('🚒', 'Fire', '101', Color(0xFFE65100)),
                      _EmergencyCard('🏥', 'Hospital', '104', Color(0xFF2E7D32)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Align(alignment: Alignment.centerLeft, child: Text('Nearby Emergency Services', style: AppTextStyles.h4)),
                  const SizedBox(height: 12),
                  StreamBuilder<List<Hospital>>(
                    stream: HospitalService.emergencyStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFE53935), strokeWidth: 3),
                          ),
                        );
                      }
                      final hospitals = snapshot.data ?? [];
                      if (hospitals.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: const Row(children: [
                            Icon(Icons.info_outline_rounded, color: AppColors.textHint),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No emergency hospitals listed yet',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  color: AppColors.textHint,
                                ),
                              ),
                            ),
                          ]),
                        );
                      }
                      return Column(
                        children: [
                          for (int i = 0; i < hospitals.length; i++) ...[
                            if (i > 0) const SizedBox(height: 10),
                            _NearbyCard(
                              hospitals[i].name,
                              hospitals[i].isEmergency
                                  ? 'Emergency Hospital'
                                  : 'Hospital',
                              hospitals[i].address,
                              hospitals[i].phone,
                              Icons.local_hospital_rounded,
                              const Color(0xFF1565C0),
                              mapsUrl: hospitals[i].mapsUrl,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
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
          children: _contacts.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              const Icon(Icons.sms_rounded, size: 16, color: Color(0xFF2E7D32)),
              const SizedBox(width: 6),
              Text('SMS sent to ${c.name}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
            ]),
          )).toList(),
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

class _EmergencyCard extends StatelessWidget {
  final String emoji, label, number;
  final Color color;
  const _EmergencyCard(this.emoji, this.label, this.number, this.color);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () async {
      final uri = Uri.parse('tel:$number');
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    },
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha:0.3))),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: AppTextStyles.labelLarge.copyWith(color: color)),
          Text(number, style: AppTextStyles.h3.copyWith(color: color)),
        ]),
      ]),
    ),
  );
}

class _NearbyCard extends StatelessWidget {
  final String name, type, subtitle, phone, mapsUrl;
  final IconData icon;
  final Color color;
  const _NearbyCard(this.name, this.type, this.subtitle, this.phone, this.icon, this.color, {this.mapsUrl = ''});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
    child: Row(children: [
      Container(width: 48, height: 48, decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 24)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text('$type • $subtitle', style: AppTextStyles.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (phone.isNotEmpty)
          Text(phone, style: AppTextStyles.bodySmall.copyWith(color: color)),
      ])),
      Column(children: [
        IconButton(
          icon: Icon(Icons.call_rounded, color: color),
          onPressed: () async {
            final clean = phone.replaceAll(RegExp(r'\s'), '');
            if (clean.isNotEmpty) await launchUrl(Uri.parse('tel:$clean'));
          },
        ),
        IconButton(
          icon: const Icon(Icons.map_rounded, color: AppColors.textHint),
          onPressed: () async {
            final url = mapsUrl.isNotEmpty
                ? mapsUrl
                : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(name)}';
            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          },
        ),
      ]),
    ]),
  );
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