import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_text_styles.dart';
import 'emergency_contacts_service.dart';
import 'manage_contacts_screen.dart';

class SOSScreen extends StatefulWidget {
  const SOSScreen({super.key});
  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  List<EmergencyContact> _contacts = [];
  bool _sosSent = false;
  bool _sending = false;
  int _countdown = 5;
  List<String> _sentTo = [];

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadContacts();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final contacts = await EmergencyContactsService.getContacts();
    if (mounted) setState(() => _contacts = contacts);
  }

  void _startSOS() {
    if (_contacts.isEmpty) {
      _showNoContactsDialog();
      return;
    }
    setState(() => _countdown = 5);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _countdown--);
      if (_countdown <= 0) {
        await _sendAlerts();
        return false;
      }
      return true;
    });
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

  Future<void> _sendAlerts() async {
    setState(() => _sending = true);

    final position = await _fetchLocation();
    final message = _buildMessage(position);

    // smsto: is SMS-only — Android won't offer WhatsApp as a handler
    // Semicolons separate multiple recipients in the smsto: scheme
    final numbers = _contacts
        .map((c) => c.phone.replaceAll(RegExp(r'\s+'), ''))
        .join(';');

    final uri = Uri.parse('smsto:$numbers?body=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }

    if (mounted) {
      setState(() {
        _sending = false;
        _sosSent = true;
        _sentTo = _contacts.map((c) => c.name).toList();
      });
    }
  }

  void _showNoContactsDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('No Emergency Contacts',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text(
          'Please add at least one emergency contact before sending an SOS alert.',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _openManageContacts();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            child: const Text('Add Contacts', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _openManageContacts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ManageContactsScreen()),
    );
    await _loadContacts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0000),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Header
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                const Expanded(
                  child: Text(
                    'SOS Emergency',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.contacts_rounded, color: Colors.white70),
                  tooltip: 'Manage contacts',
                  onPressed: _openManageContacts,
                ),
              ]),
              const SizedBox(height: 40),

              if (_sending) ...[
                _SendingIndicator(contacts: _contacts),
              ] else if (!_sosSent) ...[
                // Pulse SOS button
                ScaleTransition(
                  scale: _pulseAnim,
                  child: GestureDetector(
                    onTap: _startSOS,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFE53935),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFFE53935).withOpacity(0.6),
                              blurRadius: 40,
                              spreadRadius: 20),
                          BoxShadow(
                              color: const Color(0xFFE53935).withOpacity(0.3),
                              blurRadius: 80,
                              spreadRadius: 40),
                        ],
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.sos_rounded, color: Colors.white, size: 80),
                          Text('PRESS',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 3)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                if (_countdown < 5 && _countdown > 0) ...[
                  Text(
                    'Sending SOS in $_countdown seconds...',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => setState(() => _countdown = 5),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white30),
                        foregroundColor: Colors.white),
                    child: const Text('Cancel'),
                  ),
                ] else ...[
                  Text(
                    _contacts.isEmpty
                        ? 'No contacts added. Tap the contacts icon\nto add emergency numbers first.'
                        : 'Tap to send emergency SMS with location\nto ${_contacts.length} contact${_contacts.length == 1 ? '' : 's'}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        color: _contacts.isEmpty ? Colors.orangeAccent : Colors.white54,
                        height: 1.6),
                  ),
                ],
              ] else ...[
                // SOS Sent state
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2E7D32),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFF2E7D32).withOpacity(0.5),
                          blurRadius: 30,
                          spreadRadius: 10)
                    ],
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 64),
                ),
                const SizedBox(height: 24),
                const Text('SOS Alert Sent!',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 8),
                const Text('Help is on the way',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      ..._sentTo.map((name) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AlertSent('📱', 'SMS sent to $name'),
                          )),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              // Emergency contacts section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Emergency Contacts',
                      style: AppTextStyles.h4.copyWith(color: Colors.white)),
                  GestureDetector(
                    onTap: _openManageContacts,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(children: [
                        Icon(Icons.edit_rounded, color: Colors.white70, size: 14),
                        SizedBox(width: 4),
                        Text('Manage',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Colors.white70)),
                      ]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_contacts.isEmpty)
                GestureDetector(
                  onTap: _openManageContacts,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24, style: BorderStyle.solid),
                    ),
                    child: const Column(children: [
                      Icon(Icons.add_circle_outline_rounded, color: Colors.white54, size: 32),
                      SizedBox(height: 6),
                      Text('Tap to add emergency contacts',
                          style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12, color: Colors.white54)),
                    ]),
                  ),
                )
              else
                SizedBox(
                  height: 90,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _contacts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _ContactChip(contact: _contacts[i]),
                  ),
                ),
              const SizedBox(height: 12),
              // Fixed emergency numbers
              Row(children: [
                _EmergencyContact('108', '🚑', 'Ambulance'),
                const SizedBox(width: 10),
                _EmergencyContact('100', '👮', 'Police'),
                const SizedBox(width: 10),
                _EmergencyContact('101', '🚒', 'Fire'),
                const SizedBox(width: 10),
                _EmergencyContact('112', '🆘', 'Helpline'),
              ]),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendingIndicator extends StatelessWidget {
  final List<EmergencyContact> contacts;
  const _SendingIndicator({required this.contacts});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              color: Color(0xFFE53935),
              strokeWidth: 6,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Sending SOS...',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Alerting ${contacts.length} contact${contacts.length == 1 ? '' : 's'}',
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 13, color: Colors.white54),
          ),
        ],
      );
}

class _AlertSent extends StatelessWidget {
  final String emoji, message;
  const _AlertSent(this.emoji, this.message);

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, color: Colors.white70)),
        ),
        const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 18),
      ]);
}

class _ContactChip extends StatelessWidget {
  final EmergencyContact contact;
  const _ContactChip({required this.contact});

  @override
  Widget build(BuildContext context) => Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFE53935).withOpacity(0.4),
              child: Text(
                contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 14),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              contact.name.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 10, color: Colors.white70),
            ),
          ],
        ),
      );
}

class _EmergencyContact extends StatelessWidget {
  final String number, emoji, label;
  const _EmergencyContact(this.number, this.emoji, this.label);

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: () async {
            final uri = Uri.parse('tel:$number');
            if (await canLaunchUrl(uri)) launchUrl(uri);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Column(children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 10, color: Colors.white70)),
              Text(number,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ]),
          ),
        ),
      );
}
