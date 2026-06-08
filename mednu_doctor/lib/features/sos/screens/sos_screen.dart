import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../models/emergency_contact.dart';
import '../services/sos_service.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  bool _picking = false;

  Future<void> _pickContact() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return;

    setState(() => _picking = true);
    try {
      // ── Step 1: Check current permission status via permission_handler ──
      var status = await Permission.contacts.status;

      if (status.isPermanentlyDenied) {
        // User permanently blocked contacts — must go to Settings
        if (mounted) _showOpenSettingsDialog();
        return;
      }

      if (status.isDenied) {
        // First-time or "Ask again" — request it
        status = await Permission.contacts.request();
      }

      if (!status.isGranted) {
        if (mounted) {
          if (status.isPermanentlyDenied) {
            _showOpenSettingsDialog();
          } else {
            _showSnack('Contacts permission is required. Please allow it.', isError: true);
          }
        }
        return;
      }

      // ── Step 2: Read contacts — wrapped so a SecurityException never crashes ──
      List<Contact> all;
      try {
        all = await FlutterContacts.getContacts(
          withProperties: true,
          withPhoto: false,
        );
      } catch (_) {
        // Permission was revoked mid-flight or ContentProvider denied access
        if (mounted) _showOpenSettingsDialog();
        return;
      }

      final withPhones = all.where((c) => c.phones.isNotEmpty).toList();

      if (!mounted) return;
      setState(() => _picking = false);

      if (withPhones.isEmpty) {
        _showSnack('No contacts with phone numbers found.', isError: true);
        return;
      }

      // ── Step 3: In-app searchable picker (no external activity = no crash) ──
      final picked = await showModalBottomSheet<Contact>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _ContactPickerSheet(contacts: withPhones),
      );

      if (picked == null || !mounted) return;

      final phone = picked.phones.first.number.replaceAll(RegExp(r'\s+'), '');
      await SosService.addContact(
        uid,
        EmergencyContact(
          id: const Uuid().v4(),
          name: picked.displayName,
          phone: phone,
        ),
      );

      if (mounted) _showSnack('${picked.displayName} added as emergency contact.');
    } catch (e) {
      if (mounted) _showSnack('Something went wrong. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _showOpenSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.contacts_rounded, color: AppColors.error, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Contacts Permission', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ]),
        content: const Text(
          'Contacts permission was previously denied.\n\nTo add emergency contacts, please open App Settings and allow "Contacts" access for MedNU Doctor.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textHint)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings_rounded, size: 16),
            label: const Text('Open Settings'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _callContact(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _deleteContact(String contactId, String name) async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Contact', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text('Remove $name from your emergency contacts?', style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textHint)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await SosService.deleteContact(uid, contactId);
      if (mounted) _showSnack('$name removed.');
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final uid = DoctorAuthService.currentUid;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'SOS Emergency',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.error,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _picking ? null : _pickContact,
        backgroundColor: AppColors.error,
        icon: _picking
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.contacts_rounded, color: Colors.white),
        label: Text(
          _picking ? 'Opening...' : 'Add from Contacts',
          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
      body: uid == null
          ? const Center(child: Text('Not signed in'))
          : StreamBuilder<List<EmergencyContact>>(
              stream: SosService.contactsStream(uid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final contacts = snap.data ?? [];

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    // Info banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.error.withOpacity(0.25)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.emergency_rounded, color: AppColors.error, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Emergency Contacts', style: AppTextStyles.labelLarge.copyWith(color: AppColors.error)),
                                const SizedBox(height: 2),
                                Text(
                                  'These contacts will be notified when you trigger an SOS alert.',
                                  style: AppTextStyles.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (contacts.isEmpty) ...[
                      const SizedBox(height: 60),
                      Center(
                        child: Column(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.contacts_outlined, size: 40, color: AppColors.error),
                            ),
                            const SizedBox(height: 16),
                            Text('No Emergency Contacts', style: AppTextStyles.h4),
                            const SizedBox(height: 6),
                            Text(
                              'Tap "Add from Contacts" to select\npeople to notify in an emergency.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Text('${contacts.length} Contact${contacts.length > 1 ? 's' : ''} Added', style: AppTextStyles.h4),
                      const SizedBox(height: 12),
                      ...contacts.map((c) => _ContactCard(
                            contact: c,
                            onCall: () => _callContact(c.phone),
                            onDelete: () => _deleteContact(c.id, c.name),
                          )),
                    ],
                  ],
                );
              },
            ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final EmergencyContact contact;
  final VoidCallback onCall;
  final VoidCallback onDelete;

  const _ContactCard({
    required this.contact,
    required this.onCall,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.error,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name, style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(contact.phone, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Call button
          GestureDetector(
            onTap: onCall,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.call_rounded, color: AppColors.success, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          // Delete button
          GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ── In-app contacts picker bottom sheet ──────────────────────────────────────
class _ContactPickerSheet extends StatefulWidget {
  final List<Contact> contacts;
  const _ContactPickerSheet({required this.contacts});

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<Contact> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.contacts;
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.contacts
          : widget.contacts
              .where((c) =>
                  c.displayName.toLowerCase().contains(q) ||
                  c.phones.any((p) => p.number.contains(q)))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.85;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.contacts_rounded, color: AppColors.error, size: 22),
                const SizedBox(width: 8),
                Text('Select Contact', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by name or number…',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          // Contact count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${_filtered.length} contacts', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint)),
            ),
          ),
          const SizedBox(height: 4),
          // List
          Expanded(
            child: _filtered.isEmpty
                ? const Center(child: Text('No contacts found', style: TextStyle(fontFamily: 'Poppins', color: AppColors.textHint)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final c = _filtered[i];
                      final phone = c.phones.first.number;
                      final initial = c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : '?';
                      return ListTile(
                        onTap: () => Navigator.pop(context, c),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.error.withOpacity(0.1),
                          child: Text(initial, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppColors.error)),
                        ),
                        title: Text(c.displayName, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(phone, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
