import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'emergency_contacts_service.dart';

class ManageContactsScreen extends StatefulWidget {
  const ManageContactsScreen({super.key});

  @override
  State<ManageContactsScreen> createState() => _ManageContactsScreenState();
}

class _ManageContactsScreenState extends State<ManageContactsScreen> {
  List<EmergencyContact> _contacts = [];
  bool _loading = true;

  // Controllers for the add/edit contact sheet — created fresh per sheet
  // open and never explicitly disposed there (the sheet isn't awaited, so
  // there's no safe single point after it closes); registered here instead
  // and disposed once, when this screen itself goes away.
  final List<TextEditingController> _transientCtrls = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _transientCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final contacts = await EmergencyContactsService.getContacts();
    if (mounted) setState(() { _contacts = contacts; _loading = false; });
  }

  Future<void> _delete(String id) async {
    await EmergencyContactsService.removeContact(id);
    await _load();
  }

  // Step 1 – show options: pick from contacts OR enter manually.
  // Only used when adding a new contact (not editing).
  void _showAddOptions() {
    if (_contacts.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Maximum of 5 emergency contacts reached. Remove one to add another.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFE65100),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Emergency Contact',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose how you want to add a contact.',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Pick from contacts
            _OptionTile(
              icon: Icons.contacts_rounded,
              color: const Color(0xFFE53935),
              title: 'Pick from Contacts',
              subtitle: 'Import name & number directly from your phone',
              onTap: () {
                Navigator.pop(ctx); // close options sheet first
                // Small delay so the sheet fully closes before the native
                // contacts activity launches — prevents the dismissal bug.
                Future.delayed(const Duration(milliseconds: 350), _pickFromContacts);
              },
            ),
            const SizedBox(height: 12),

            // Enter manually
            _OptionTile(
              icon: Icons.edit_rounded,
              color: const Color(0xFF1565C0),
              title: 'Enter Manually',
              subtitle: 'Type the name and phone number yourself',
              onTap: () {
                Navigator.pop(ctx);
                Future.delayed(const Duration(milliseconds: 200),
                    () => _showAddSheet());
              },
            ),
          ],
        ),
      ),
    );
  }

  // Step 2a – pick a contact from the device, then open the form pre-filled.
  // This must run OUTSIDE any bottom sheet context.
  Future<void> _pickFromContacts() async {
    try {
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null || !mounted) return;

      String phone = '';
      if (contact.phones.isNotEmpty) {
        phone = contact.phones.first.number.replaceAll(RegExp(r'\s+'), '');
      }

      _showAddSheet(prefillName: contact.displayName, prefillPhone: phone);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not open contacts. Please grant contacts permission.')),
        );
      }
    }
  }

  // Step 2b – the form sheet (add new or edit existing).
  void _showAddSheet({
    EmergencyContact? existing,
    String prefillName = '',
    String prefillPhone = '',
  }) {
    final nameCtrl =
        TextEditingController(text: existing?.name ?? prefillName);
    final phoneCtrl =
        TextEditingController(text: existing?.phone ?? prefillPhone);
    _transientCtrls.addAll([nameCtrl, phoneCtrl]);
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                existing == null ? 'Add Emergency Contact' : 'Edit Contact',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'This contact will receive an SOS alert via SMS when you press SOS.',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration:
                    _inputDecoration('Name', Icons.person_outline_rounded),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))
                ],
                decoration: _inputDecoration(
                    'Phone with country code (e.g. +919876543210)',
                    Icons.phone_outlined),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter a phone number';
                  if (v.trim().length < 7) return 'Enter a valid number';
                  final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                  final duplicate = _contacts.any((c) =>
                      c.id != existing?.id &&
                      c.phone.replaceAll(RegExp(r'[^0-9]'), '') == digits);
                  if (duplicate) return 'This number is already an emergency contact';
                  return null;
                },
              ),
              const SizedBox(height: 4),
              const Text(
                'Include country code, e.g. +91 for India',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final contact = EmergencyContact(
                      id: existing?.id ??
                          DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                    );
                    try {
                      if (existing == null) {
                        await EmergencyContactsService.addContact(contact);
                      } else {
                        await EmergencyContactsService.updateContact(contact);
                      }
                    } on StateError catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(e.message),
                            backgroundColor: const Color(0xFFE65100),
                          ),
                        );
                      }
                      return;
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    existing == null ? 'Add Contact' : 'Save Changes',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE53935),
        foregroundColor: Colors.white,
        title: const Text('Emergency Contacts',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add contact',
            onPressed: _contacts.length >= 5 ? null : _showAddOptions,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFE53935)))
          : _contacts.isEmpty
              ? _emptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Max contacts info banner ────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _contacts.length >= 5
                            ? Colors.orange.withValues(alpha: 0.1)
                            : const Color(0xFFE53935).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _contacts.length >= 5
                                ? Colors.orange.withValues(alpha: 0.4)
                                : const Color(0xFFE53935)
                                    .withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        Icon(
                          _contacts.length >= 5
                              ? Icons.warning_amber_rounded
                              : Icons.info_outline_rounded,
                          color: _contacts.length >= 5
                              ? Colors.orange.shade700
                              : const Color(0xFFE53935),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _contacts.length >= 5
                                ? 'Maximum contacts reached. Remove one to add another.'
                                : 'You can add up to 5 emergency contacts. ${5 - _contacts.length} slot${5 - _contacts.length == 1 ? '' : 's'} remaining.',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: _contacts.length >= 5
                                    ? Colors.orange.shade800
                                    : const Color(0xFFB71C1C)),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(children: [
                        Icon(Icons.swipe_left_rounded,
                            color: Color(0xFFE53935), size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Swipe left on a contact to quickly remove it.',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: Color(0xFFB71C1C)),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    ..._contacts.map((c) => Dismissible(
                          key: ValueKey(c.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.delete_rounded,
                                    color: Colors.white, size: 26),
                                SizedBox(height: 4),
                                Text('Remove',
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                          confirmDismiss: (_) async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20)),
                                title: const Text('Remove Contact?',
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w700)),
                                content: Text(
                                    '${c.name} will no longer receive SOS alerts.',
                                    style: const TextStyle(
                                        fontFamily: 'Poppins')),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel')),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFFE53935)),
                                    child: const Text('Remove',
                                        style:
                                            TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );
                            return confirm == true;
                          },
                          onDismissed: (_) => _delete(c.id),
                          child: _ContactTile(
                            contact: c,
                            onEdit: () => _showAddSheet(existing: c),
                            onDelete: () => _confirmDelete(c),
                          ),
                        )),
                  ],
                ),
      floatingActionButton: _contacts.length >= 5
          ? FloatingActionButton.extended(
              onPressed: null,
              backgroundColor: Colors.grey.shade400,
              icon: const Icon(Icons.block_rounded, color: Colors.white),
              label: const Text('Maximum Reached',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            )
          : FloatingActionButton.extended(
              onPressed: _showAddOptions,
              backgroundColor: const Color(0xFFE53935),
              icon: const Icon(Icons.person_add_rounded, color: Colors.white),
              label: const Text('Add Contact',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withValues(alpha:0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.contacts_rounded,
                    size: 48, color: Color(0xFFE53935)),
              ),
              const SizedBox(height: 24),
              const Text('No Emergency Contacts',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                'Add contacts who should receive an SOS alert when you press the emergency button.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _showAddOptions,
                icon: const Icon(Icons.contacts_rounded),
                label: const Text('Add Emergency Contact',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _confirmDelete(EmergencyContact contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Contact?',
            style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text('${contact.name} will no longer receive SOS alerts.',
            style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935)),
            child:
                const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) await _delete(contact.id);
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey.shade400, size: 20),
            ]),
          ),
        ),
      );
}

class _ContactTile extends StatelessWidget {
  final EmergencyContact contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ContactTile(
      {required this.contact, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha:0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE53935).withValues(alpha:0.12),
            child: Text(
              contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE53935)),
            ),
          ),
          title: Text(contact.name,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          subtitle: Text(contact.phone,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, color: Colors.grey)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 20, color: Colors.grey),
                  onPressed: onEdit),
              IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: Color(0xFFE53935)),
                  onPressed: onDelete),
            ],
          ),
        ),
      );
}
