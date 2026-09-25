import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/gradient_button.dart';

// Same defaults the MedNU mobile app falls back to when a doctor hasn't set a schedule.
const _defaultSlots = [
  '09:00 AM', '10:00 AM', '11:00 AM', '12:00 PM',
  '02:00 PM', '03:00 PM', '04:00 PM', '05:00 PM', '06:00 PM',
];
const _durations = [15, 30, 45, 60];
const _types = {
  'Video': Icons.videocam_rounded,
  'Audio': Icons.phone_in_talk_rounded,
  'Chat': Icons.chat_bubble_rounded,
  'In-Person': Icons.local_hospital_rounded,
};

// Fees are the 30-minute rate and scale linearly — identical to the mobile app.
int _feeFor(int base, int minutes) => base <= 0 ? 0 : ((base * minutes) / 30).round();

class _Doctor {
  final String id;
  final String name;
  final String specialty;
  final int fee;
  final String photoUrl;
  final String qualifications;
  final String hospital;
  final bool online;
  final Map<String, dynamic>? availability;

  _Doctor.fromDoc(DocumentSnapshot<Map<String, dynamic>> d)
      : id = d.id,
        name = (d.data()?['name'] as String?) ?? 'Doctor',
        specialty = (d.data()?['specialty'] as String?) ?? '',
        fee = _toInt(d.data()?['fee']),
        photoUrl = (d.data()?['photoUrl'] as String?) ?? '',
        qualifications = (d.data()?['qualifications'] as String?) ?? '',
        hospital = ((d.data()?['hospitalAffiliation'] ?? d.data()?['hospital']) as String?) ?? '',
        online = d.data()?['isOnline'] == true,
        availability = d.data()?['availability'] as Map<String, dynamic>?;

  static int _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  String get initials {
    final parts = name.replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').trim().split(' ');
    return parts.where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
  }

  bool worksOn(DateTime date) {
    final schedule = availability?['schedule'] as Map<String, dynamic>?;
    if (schedule == null) return true;
    return (schedule[DateFormat('EEE').format(date)] as Map<String, dynamic>?)?['enabled'] == true;
  }

  List<String> slotsFor(DateTime date) {
    final avail = availability;
    final schedule = avail?['schedule'] as Map<String, dynamic>?;
    if (avail == null || schedule == null) return _defaultSlots.toList();
    final ds = schedule[DateFormat('EEE').format(date)] as Map<String, dynamic>?;
    if (ds == null || ds['enabled'] != true) return [];
    try {
      final slotMins = (avail['slotDuration'] as num?)?.toInt() ?? 30;
      final sp = (ds['start'] as String? ?? '09:00').split(':');
      final ep = (ds['end'] as String? ?? '17:00').split(':');
      final start = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final end = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      final blocked = ((avail['blockedSlots'] as Map<String, dynamic>?)?[DateFormat('yyyy-MM-dd').format(date)] as List?)
              ?.cast<String>()
              .toSet() ??
          <String>{};
      final out = <String>[];
      for (int m = start; m + slotMins <= end; m += slotMins) {
        final h = m ~/ 60;
        final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
        final s = '${dh.toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
        if (!blocked.contains(s)) out.add(s);
      }
      return out;
    } catch (_) {
      return _defaultSlots.toList();
    }
  }
}

bool _isPast(DateTime day, String slot) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  if (d.isAfter(today)) return false;
  if (d.isBefore(today)) return true;
  try {
    final parts = slot.trim().split(' ');
    final hm = parts[0].split(':');
    var h = int.parse(hm[0]);
    if (parts[1].toUpperCase() == 'PM' && h != 12) h += 12;
    if (parts[1].toUpperCase() == 'AM' && h == 12) h = 0;
    return DateTime(now.year, now.month, now.day, h, int.parse(hm[1])).isBefore(now);
  } catch (_) {
    return false;
  }
}

String _rxId() {
  final n = DateTime.now();
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return 'MN-${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}-'
      '${List.generate(6, (_) => chars[r.nextInt(chars.length)]).join()}';
}

Future<void> showBookAppointmentDialog(BuildContext context) {
  return showDialog(context: context, builder: (_) => const _BookAppointmentDialog());
}

class _BookAppointmentDialog extends StatefulWidget {
  const _BookAppointmentDialog();

  @override
  State<_BookAppointmentDialog> createState() => _BookAppointmentDialogState();
}

class _BookAppointmentDialogState extends State<_BookAppointmentDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _Doctor? _doctor;
  int _dayIndex = 0;
  String? _time;
  int _duration = 30;
  String _type = 'Video';
  bool _saving = false;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _doctors = FirebaseFirestore.instance
      .collection('doctors')
      .where('status', isEqualTo: 'active')
      .snapshots();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<DateTime> _days(_Doctor d) {
    final today = DateTime.now();
    return List.generate(14, (i) => DateTime(today.year, today.month, today.day + i))
        .where(d.worksOn)
        .take(7)
        .toList();
  }

  Stream<Set<String>> _taken(String doctorId, String dateKey) => FirebaseFirestore.instance
      .collection('appointments')
      .where('doctorId', isEqualTo: doctorId)
      .where('date', isEqualTo: dateKey)
      .where('status', isEqualTo: 'booked')
      .snapshots()
      .map((s) => s.docs.map((d) => (d.data()['time'] as String?) ?? '').toSet());

  void _toast(String msg, Color bg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
      ));

  Future<void> _confirm(_Doctor doc, DateTime day) async {
    final user = FirebaseAuth.instance.currentUser;
    final slot = _time;
    if (user == null || slot == null) return;
    if (_isPast(day, slot)) {
      setState(() => _time = null);
      _toast('That slot has just passed. Please pick another time.', AppColors.error);
      return;
    }
    setState(() => _saving = true);
    final db = FirebaseFirestore.instance;
    final dateKey = DateFormat('yyyy-MM-dd').format(day);
    try {
      final clash = await db
          .collection('appointments')
          .where('doctorId', isEqualTo: doc.id)
          .where('date', isEqualTo: dateKey)
          .where('time', isEqualTo: slot)
          .where('status', isEqualTo: 'booked')
          .limit(1)
          .get();
      if (clash.docs.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _time = null;
        });
        _toast('This slot was just taken. Please choose another time.', AppColors.error);
        return;
      }
      final userSnap = await db.collection('users').doc(user.uid).get();
      final name = ((userSnap.data()?['name'] as String?) ?? '').trim();
      final patientName = name.isNotEmpty ? name : (user.phoneNumber ?? 'Patient');
      final ref = db.collection('appointments').doc();
      // Same shape the MedNU app writes while payments are switched off
      // (paymentStatus: not_required), so it shows up for doctors identically.
      await ref.set({
        'doctorId': doc.id,
        'doctorName': doc.name,
        'doctorSpecialty': doc.specialty,
        'patientName': patientName,
        'bookedByName': patientName,
        'date': dateKey,
        'time': slot,
        'consultationType': _type,
        'duration': _duration,
        'fee': _feeFor(doc.fee, _duration),
        'status': 'booked',
        if (_type == 'In-Person') 'rxId': _rxId(),
        'patientId': user.uid,
        'paymentStatus': 'not_required',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Booked with ${doc.name} · ${DateFormat('d MMM').format(day)} at $slot',
            style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not book the appointment. Please try again.', AppColors.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(horizontal: size.width < 600 ? 12 : 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 540, maxHeight: size.height * 0.88),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(_doctor == null ? 'Find a Doctor' : 'Book Appointment',
                    style: GoogleFonts.poppins(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textPrimary),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Flexible(child: SingleChildScrollView(child: _doctor == null ? _picker() : _slotPicker(_doctor!))),
          ]),
        ),
      ),
    );
  }

  Widget _picker() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search doctor or specialty…',
          hintStyle: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
          filled: true,
          fillColor: AppColors.background,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 14),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _doctors,
        builder: (context, snap) {
          if (snap.hasError) return _note(Icons.error_outline_rounded, 'Could not load doctors. Check your connection.');
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            );
          }
          final all = snap.data!.docs.map(_Doctor.fromDoc).toList()
            ..sort((a, b) => (b.online ? 1 : 0).compareTo(a.online ? 1 : 0));
          final list = _query.isEmpty
              ? all
              : all.where((d) => d.name.toLowerCase().contains(_query) || d.specialty.toLowerCase().contains(_query)).toList();
          if (list.isEmpty) {
            return _note(Icons.search_off_rounded,
                all.isEmpty ? 'No doctors are available right now.' : 'No doctors match your search.');
          }
          return Column(
              children: list
                  .map((d) => _DoctorRow(
                      doctor: d,
                      onTap: () => setState(() {
                            _doctor = d;
                            _dayIndex = 0;
                            _time = null;
                          })))
                  .toList());
        },
      ),
    ]);
  }

  Widget _note(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(children: [
            Icon(icon, size: 30, color: AppColors.textSecondary),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13.5, color: AppColors.textSecondary)),
          ]),
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(t, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      );

  Widget _slotPicker(_Doctor doc) {
    final days = _days(doc);
    if (days.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _DoctorHeader(doctor: doc, onChange: () => setState(() => _doctor = null)),
        _note(Icons.event_busy_rounded, 'This doctor has no open days in the next two weeks.'),
      ]);
    }
    final day = days[_dayIndex.clamp(0, days.length - 1)];
    final dateKey = DateFormat('yyyy-MM-dd').format(day);
    final fee = _feeFor(doc.fee, _duration);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _DoctorHeader(doctor: doc, onChange: () => setState(() => _doctor = null)),
      _label('Consultation type'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in _types.entries)
          _Pill(label: e.key, icon: e.value, selected: _type == e.key, onTap: () => setState(() => _type = e.key)),
      ]),
      _label('Session length'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in _durations)
          _Pill(label: '$m min', selected: _duration == m, onTap: () => setState(() => _duration = m)),
      ]),
      _label('Date'),
      SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: days.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _Pill(
            label: days[i].difference(DateTime.now()).inHours < 24 && days[i].day == DateTime.now().day
                ? 'Today'
                : DateFormat('EEE, d MMM').format(days[i]),
            selected: _dayIndex == i,
            onTap: () => setState(() {
              _dayIndex = i;
              _time = null;
            }),
          ),
        ),
      ),
      _label('Time'),
      StreamBuilder<Set<String>>(
        stream: _taken(doc.id, dateKey),
        builder: (context, snap) {
          final taken = snap.data ?? <String>{};
          final open = doc.slotsFor(day).where((s) => !taken.contains(s) && !_isPast(day, s)).toList();
          if (_time != null && !open.contains(_time)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _time = null);
            });
          }
          if (open.isEmpty) {
            return _note(Icons.schedule_rounded, 'No free slots on this day. Try another date.');
          }
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in open) _Pill(label: s, selected: _time == s, onTap: () => setState(() => _time = s)),
          ]);
        },
      ),
      const SizedBox(height: 22),
      Row(children: [
        Text('Consultation fee', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        const Spacer(),
        Text(fee > 0 ? '₹$fee' : 'Free',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
      ]),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: _saving
            ? Container(
                height: 52,
                decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(14)),
                child: const Center(
                    child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
              )
            : GradientButton(
                label: _time == null ? 'Select a time slot' : 'Confirm booking',
                onTap: _time == null ? null : () => _confirm(doc, day),
                icon: Icons.check_circle_outline_rounded,
                colors: _time == null ? const [Color(0xFF857080), Color(0xFF857080)] : null,
              ),
      ),
    ]);
  }
}

class _DoctorAvatar extends StatelessWidget {
  final _Doctor doctor;
  final double size;
  const _DoctorAvatar({required this.doctor, required this.size});

  @override
  Widget build(BuildContext context) {
    final initials = Center(
        child: Text(doctor.initials,
            style: GoogleFonts.poppins(fontSize: size * 0.34, fontWeight: FontWeight.w800, color: Colors.white)));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(size * 0.3)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: doctor.photoUrl.isEmpty
            ? initials
            : CachedNetworkImage(
                imageUrl: doctor.photoUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => initials,
              ),
      ),
    );
  }
}

class _DoctorHeader extends StatelessWidget {
  final _Doctor doctor;
  final VoidCallback onChange;
  const _DoctorHeader({required this.doctor, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _DoctorAvatar(doctor: doctor, size: 52),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(doctor.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          Text(doctor.specialty,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.primary, fontWeight: FontWeight.w600)),
        ]),
      ),
      TextButton(
        onPressed: onChange,
        child: Text('Change', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
      ),
    ]);
  }
}

class _DoctorRow extends StatelessWidget {
  final _Doctor doctor;
  final VoidCallback onTap;
  const _DoctorRow({required this.doctor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sub = [doctor.qualifications, doctor.hospital].where((s) => s.isNotEmpty).join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          _DoctorAvatar(doctor: doctor, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(doctor.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
                if (doctor.online) ...[
                  const SizedBox(width: 6),
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                ],
              ]),
              Text(doctor.specialty,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.primary, fontWeight: FontWeight.w600)),
              if (sub.isNotEmpty)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.textSecondary)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(doctor.fee > 0 ? '₹${doctor.fee}' : 'Free',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            Text('/ 30 min', style: GoogleFonts.poppins(fontSize: 10.5, color: AppColors.textSecondary)),
          ]),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.primaryGradient : null,
          color: selected ? null : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? Colors.transparent : AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: selected ? Colors.white : AppColors.textPrimary),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.textPrimary)),
        ]),
      ),
    );
  }
}
