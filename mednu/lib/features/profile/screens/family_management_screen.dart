import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/services/operation_logger.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/widgets/ux_widgets.dart';

// Top-level so it can be called from any screen
void showAddFamilyMemberSheet(
  BuildContext context,
  WidgetRef ref,
  String uid, {
  Map<String, dynamic>? existing,
  String prefillName = '',
  String prefillPhone = '',
  int currentMinorCount = 0,
  int maxMinors = 2,
  int currentAdultCount = 0,
  int maxAdults = 1,
  int currentTotalCount = 0,
  int maxMembers = 3,
}) {
  if (existing == null && currentTotalCount >= maxMembers) {
    FeedbackService.showWarning(context, 'You can only add up to $maxMembers family members.');
    return;
  }

  final nameCtrl       = TextEditingController(text: existing?['name']       ?? prefillName);
  final relationCtrl   = TextEditingController(text: existing?['relation']   ?? '');
  final ageCtrl        = TextEditingController(text: existing?['age']?.toString() ?? '');
  final phoneCtrl      = TextEditingController(text: existing?['phone']      ?? prefillPhone);
  final checkupCtrl    = TextEditingController(text: existing?['lastCheckup'] ?? '');
  final allergiesCtrl  = TextEditingController(text: existing?['allergies']  ?? '');
  final conditionsCtrl = TextEditingController(text: existing?['chronicConditions'] ?? '');
  String gender     = existing?['gender'] ?? 'Female';

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        Future<void> importFromContacts() async {
          final status = await Permission.contacts.request();
          if (!status.isGranted) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: const Text('Contacts permission required'),
                action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
              ));
            }
            return;
          }
          if (!ctx.mounted) return;
          final selected = await showModalBottomSheet<Contact>(
            context: ctx,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const _ContactPickerSheet(),
          );
          if (selected != null && ctx.mounted) {
            nameCtrl.text  = selected.displayName;
            phoneCtrl.text = selected.phones.isNotEmpty ? selected.phones.first.number : '';
            setSheet(() {});
          }
        }

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.9,
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          decoration: BoxDecoration(
            color: ctx.appSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: ctx.appBorder, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text(existing != null ? 'Edit Family Member' : 'Add Family Member', style: AppTextStyles.h3)),
              if (existing == null)
                TextButton.icon(
                  onPressed: importFromContacts,
                  icon: const Icon(Icons.contacts_rounded, size: 16),
                  label: const Text('Contacts', style: TextStyle(fontSize: 12)),
                ),
            ]),
            const SizedBox(height: 16),
            _field(nameCtrl, 'Full Name', capitalWords: true),
            const SizedBox(height: 12),
            _field(relationCtrl, 'Relation (e.g. Mother, Father)', capitalWords: true),
            const SizedBox(height: 12),
            _field(
              ageCtrl,
              existing == null && currentAdultCount >= maxAdults
                  ? 'Age * (must be under 18)'
                  : 'Age *',
              numeric: true,
              maxAge: existing == null && currentAdultCount >= maxAdults ? 17 : 120,
            ),
            const SizedBox(height: 12),
            _field(phoneCtrl, 'Phone Number', phone: true),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: gender,
              decoration: InputDecoration(
                labelText: 'Gender',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              items: ['Female', 'Male', 'Other']
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) { if (v != null) setSheet(() => gender = v); },
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(1940),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  checkupCtrl.text =
                      '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                  setSheet(() {});
                }
              },
              child: AbsorbPointer(
                child: _field(checkupCtrl, 'Last Checkup (DD/MM/YYYY)'),
              ),
            ),
            const SizedBox(height: 12),
            _field(allergiesCtrl, 'Allergies (if any)', capitalWords: true),
            const SizedBox(height: 12),
            _field(conditionsCtrl, 'Chronic Conditions (if any)', capitalWords: true),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty || relationCtrl.text.trim().isEmpty) {
                    FeedbackService.showWarning(ctx, 'Name and relation are required');
                    return;
                  }
                  final parsedAge = int.tryParse(ageCtrl.text.trim());
                  if (parsedAge == null || parsedAge <= 0 || parsedAge > 120) {
                    FeedbackService.showWarning(ctx, 'Please enter a valid age');
                    return;
                  }
                  final isEditing = existing != null;
                  // Minor (age < 18, max 2) / adult (age >= 18, max 1) limit checks — skip when editing the same member
                  if (!isEditing) {
                    final enteredAge = parsedAge;
                    if (enteredAge < 18 && currentMinorCount >= maxMinors) {
                      FeedbackService.showWarning(
                        ctx,
                        'You can only add up to $maxMinors members under 18.',
                      );
                      return;
                    }
                    if (enteredAge >= 18 && currentAdultCount >= maxAdults) {
                      FeedbackService.showWarning(
                        ctx,
                        'You can only add up to $maxAdults adult member. Additional members must be under 18.',
                      );
                      return;
                    }
                  }
                  // Capture these before the async gap so they work even if ctx unmounts
                  final nav = Navigator.of(ctx);
                  final messenger = ScaffoldMessenger.of(ctx);
                  messenger.clearSnackBars();
                  messenger.showSnackBar(SnackBar(
                    content: Row(children: [
                      const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      const SizedBox(width: 10),
                      Text(isEditing ? 'Updating family member...' : 'Adding family member...',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                              fontWeight: FontWeight.w500, color: Colors.white, height: 1.4)),
                    ]),
                    backgroundColor: const Color(0xFF1A1A2E),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    duration: const Duration(seconds: 30),
                    dismissDirection: DismissDirection.none,
                  ));
                  final member = {
                    'name':              nameCtrl.text.trim(),
                    'relation':          relationCtrl.text.trim(),
                    'age':               parsedAge,
                    'gender':            gender,
                    'phone':             phoneCtrl.text.trim(),
                    'lastCheckup':       checkupCtrl.text.trim(),
                    'allergies':         allergiesCtrl.text.trim(),
                    'chronicConditions': conditionsCtrl.text.trim(),
                  };
                  try {
                    if (isEditing) {
                      await ref.read(authProvider.notifier).updateFamilyMember(existing, member);
                    } else {
                      await ref.read(authProvider.notifier).addFamilyMember(member);
                    }
                    messenger.clearSnackBars();
                    if (ctx.mounted) nav.pop();
                    // fire-and-forget — logging must not block the UI
                    OperationLogger.logSuccess(
                      action: isEditing ? OpAction.familyMemberUpdated : OpAction.familyMemberAdded,
                      message: '${isEditing ? 'Updated' : 'Added'} family member: ${member['name']}',
                    );
                  } catch (e) {
                    OperationLogger.logError(
                      action: isEditing ? OpAction.familyMemberUpdated : OpAction.familyMemberAdded,
                      errorDetails: e.toString(),
                    );
                    messenger.clearSnackBars();
                    if (ctx.mounted) {
                      FeedbackService.showError(ctx, 'Failed to save family member. Try again.');
                    }
                  }
                },
                child: Text(existing != null ? 'Save Changes' : 'Add Member'),
              ),
            ),
            const SizedBox(height: 8),
          ]),
          ),
        );
      },
    ),
  ).whenComplete(() {
    nameCtrl.dispose();
    relationCtrl.dispose();
    ageCtrl.dispose();
    phoneCtrl.dispose();
    checkupCtrl.dispose();
    allergiesCtrl.dispose();
    conditionsCtrl.dispose();
  });
}

TextField _field(TextEditingController ctrl, String label, {
  bool capitalWords = false,
  bool allCaps = false,
  bool numeric = false,
  bool phone = false,
  int? maxAge,
}) =>
    TextField(
      controller: ctrl,
      textCapitalization: capitalWords
          ? TextCapitalization.words
          : allCaps
              ? TextCapitalization.characters
              : TextCapitalization.none,
      keyboardType: numeric
          ? TextInputType.number
          : phone
              ? TextInputType.phone
              : TextInputType.text,
      inputFormatters: numeric
          ? [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
              if (maxAge != null) _MaxValueFormatter(maxAge),
            ]
          : null,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

// Rejects a digit-only edit if the resulting number exceeds [maxValue] —
// used to cap the Age field to under-18 once the single adult slot is filled.
class _MaxValueFormatter extends TextInputFormatter {
  final int maxValue;
  const _MaxValueFormatter(this.maxValue);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final parsed = int.tryParse(newValue.text);
    if (parsed == null || parsed > maxValue) return oldValue;
    return newValue;
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class FamilyManagementScreen extends ConsumerStatefulWidget {
  const FamilyManagementScreen({super.key});

  @override
  ConsumerState<FamilyManagementScreen> createState() => _FamilyManagementScreenState();
}

class _FamilyManagementScreenState extends ConsumerState<FamilyManagementScreen> {
  static const _avatarColors = [
    Color(0xFFC2185B), Color(0xFF7B1FA2), Color(0xFF1565C0),
    Color(0xFF2E7D32), Color(0xFF00695C), Color(0xFFE65100),
  ];

  Color _colorFor(String name) =>
      _avatarColors[name.isNotEmpty ? name.codeUnitAt(0) % _avatarColors.length : 0];

  StreamSubscription<DocumentSnapshot>? _sub;
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  String? _uid;

  @override
  void initState() {
    super.initState();
    // Use FirebaseAuth directly so we never miss the uid due to Riverpod timing
    _uid = FirebaseAuth.instance.currentUser?.uid
        ?? ref.read(authProvider).user?.uid;
    _subscribe();
  }

  void _subscribe() {
    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data();
      final raw = data?['familyMembers'];
      final list = raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _members = list;
        _loading = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String get _safeUid =>
      _uid ?? FirebaseAuth.instance.currentUser?.uid ?? ref.read(authProvider).user?.uid ?? '';

  static const _maxMembers = 3;
  static const _maxMinors  = 2;
  static const _maxAdults  = 1;

  bool get _atLimit => _members.length >= _maxMembers;

  int get _minorCount => _members.where((m) {
    final age = m['age'];
    return age is int && age > 0 && age < 18;
  }).length;

  int get _adultCount => _members.where((m) {
    final age = m['age'];
    return age is int && age >= 18;
  }).length;

  bool get _atMinorLimit => _minorCount >= _maxMinors;

  void _tryAdd(BuildContext context) {
    if (_atLimit) {
      FeedbackService.showWarning(context, 'You can only add up to $_maxMembers family members.');
      return;
    }
    showAddFamilyMemberSheet(
      context, ref, _safeUid,
      currentMinorCount: _minorCount,
      maxMinors: _maxMinors,
      currentAdultCount: _adultCount,
      maxAdults: _maxAdults,
      currentTotalCount: _members.length,
      maxMembers: _maxMembers,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 140,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            actions: [
              if (!_atLimit)
                IconButton(
                  icon: const Icon(Icons.person_add_rounded, color: Colors.white),
                  tooltip: 'Add Member',
                  onPressed: () => _tryAdd(context),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -30, right: -30,
                      child: Container(
                        width: 130, height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha:0.06),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: constraints.maxHeight),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(children: [
                                      Container(
                                        width: 46, height: 46,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha:0.15),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white.withValues(alpha:0.3)),
                                        ),
                                        child: const Icon(Icons.family_restroom_rounded,
                                            color: Colors.white, size: 24),
                                      ),
                                      const SizedBox(width: 14),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'Family Members',
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${_members.length} member${_members.length == 1 ? '' : 's'} added',
                                            style: const TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 12,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ]),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_loading)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (_, __) => const _FamilyMemberSkeleton(), childCount: 4)),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: _atLimit
                          ? Colors.orange.withValues(alpha: 0.08)
                          : _atMinorLimit
                              ? Colors.amber.withValues(alpha: 0.08)
                              : AppColors.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _atLimit
                            ? Colors.orange.withValues(alpha: 0.3)
                            : _atMinorLimit
                                ? Colors.amber.withValues(alpha: 0.35)
                                : AppColors.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(children: [
                      Icon(
                        _atLimit
                            ? Icons.group_rounded
                            : _atMinorLimit
                                ? Icons.child_care_rounded
                                : Icons.info_outline_rounded,
                        color: _atLimit
                            ? Colors.orange.shade700
                            : _atMinorLimit
                                ? Colors.amber.shade800
                                : AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _atLimit
                              ? 'Maximum of $_maxMembers members reached. Remove a member to add another.'
                              : _atMinorLimit
                                  ? 'Maximum of $_maxMinors members under 18 reached. You can still add an adult member.'
                                  : 'Add up to $_maxMembers members ($_maxAdults adult, max $_maxMinors under 18) to manage their health records.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: _atLimit
                                ? Colors.orange.shade700
                                : _atMinorLimit
                                    ? Colors.amber.shade800
                                    : AppColors.primary,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ]),
                  ),

                  if (_members.isEmpty)
                    AppEmptyState(
                      icon: Icons.family_restroom_rounded,
                      title: 'No family members yet',
                      message: 'Add up to $_maxMembers family members to manage their health records and book appointments.',
                      actionLabel: 'Add Member',
                      onAction: () => _tryAdd(context),
                    ),

                  ..._members.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final m = entry.value;
                    final name    = m['name']     as String? ?? '';
                    final relation= m['relation'] as String? ?? '';
                    final age     = m['age']?.toString() ?? '';
                    final gender  = m['gender']   as String? ?? '';
                    final blood   = m['blood']    as String? ?? '';
                    final color   = _colorFor(name);
                    final rawAge  = m['age'];
                    final isMinor = rawAge is int && rawAge > 0 && rawAge < 18;

                    return FadeInSlide(
                      key: ValueKey(m['id'] ?? '$name-$relation-$idx'),
                      delay: Duration(milliseconds: idx * 60),
                      child: GestureDetector(
                      onTap: () => context.push(AppRoutes.familyMemberDetail, extra: m),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.appSurface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x08000000),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(children: [
                          Container(
                            width: 54, height: 54,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha:0.12),
                              shape: BoxShape.circle,
                              border: Border.all(color: color.withValues(alpha:0.2)),
                            ),
                            child: Center(
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                                    fontWeight: FontWeight.w700, color: color),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(name, style: AppTextStyles.labelLarge, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(
                                '$relation${age.isNotEmpty ? ' · $age yrs' : ''}${gender.isNotEmpty ? ' · $gender' : ''}',
                                style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
                              ),
                              if (blood.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFB71C1C).withValues(alpha:0.09),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.water_drop_rounded, size: 11, color: Color(0xFFB71C1C)),
                                    const SizedBox(width: 3),
                                    Text(blood, style: const TextStyle(
                                        fontFamily: 'Poppins', fontSize: 11,
                                        fontWeight: FontWeight.w600, color: Color(0xFFB71C1C))),
                                  ]),
                                ),
                              ],
                              if (isMinor) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.escalator_warning_rounded, size: 12, color: Colors.amber.shade800),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text('Adult must accompany for consultations',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontFamily: 'Poppins', fontSize: 10,
                                              fontWeight: FontWeight.w600, color: Colors.amber.shade900)),
                                    ),
                                  ]),
                                ),
                              ],
                            ]),
                          ),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            // Edit button
                            InkWell(
                              onTap: () => showAddFamilyMemberSheet(
                                context, ref, _safeUid,
                                existing: m,
                                currentMinorCount: _minorCount,
                                maxMinors: _maxMinors,
                                currentAdultCount: _adultCount,
                                maxAdults: _maxAdults,
                                currentTotalCount: _members.length,
                                maxMembers: _maxMembers,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(Icons.edit_rounded, size: 18,
                                    color: AppColors.primary.withValues(alpha: 0.75)),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Delete button
                            InkWell(
                              onTap: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogCtx) => AlertDialog(
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20)),
                                    title: const Text('Remove Member',
                                        style: TextStyle(fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w700)),
                                    content: Text('Remove $name from your family?',
                                        style: const TextStyle(fontFamily: 'Poppins')),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(dialogCtx, false),
                                          child: const Text('Cancel')),
                                      TextButton(
                                          onPressed: () => Navigator.pop(dialogCtx, true),
                                          child: const Text('Remove',
                                              style: TextStyle(color: AppColors.error))),
                                    ],
                                  ),
                                );
                                if (confirm == true && context.mounted) {
                                  try {
                                    await ref.read(authProvider.notifier).removeFamilyMember(m);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed to remove: $e')),
                                      );
                                    }
                                  }
                                }
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(Icons.delete_outline_rounded,
                                    size: 18,
                                    color: AppColors.error.withValues(alpha: 0.8)),
                              ),
                            ),
                          ]),
                        ]),
                      ),
                    ));
                  }),

                  const SizedBox(height: 16),

                  if (!_atLimit) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: () => _tryAdd(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.person_add_rounded, color: Colors.white),
                          label: Text(
                            'Add Family Member (${_members.length}/$_maxMembers)',
                            style: const TextStyle(color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: () => _importFromContacts(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
                          foregroundColor: const Color(0xFF1565C0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.contacts_rounded),
                        label: const Text('Import from Contacts',
                            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _importFromContacts(BuildContext context) async {
    if (_atLimit) {
      FeedbackService.showWarning(context, 'You can only add up to $_maxMembers family members.');
      return;
    }
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Contacts permission is required to import contacts.'),
          action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
        ));
      }
      return;
    }
    if (!context.mounted) return;

    final selected = await showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ContactPickerSheet(),
    );

    if (selected != null && context.mounted) {
      final name = selected.displayName;
      final phone = selected.phones.isNotEmpty ? selected.phones.first.number : '';
      showAddFamilyMemberSheet(
        context, ref, _safeUid,
        prefillName: name, prefillPhone: phone,
        currentMinorCount: _minorCount,
        maxMinors: _maxMinors,
        currentAdultCount: _adultCount,
        maxAdults: _maxAdults,
        currentTotalCount: _members.length,
        maxMembers: _maxMembers,
      );
    }
  }
}

// ── Contact Picker ─────────────────────────────────────────────────────────────

class _ContactPickerSheet extends StatefulWidget {
  const _ContactPickerSheet();
  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  List<Contact> _contacts = [];
  List<Contact> _filtered = [];
  bool _loading = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _search.addListener(_filter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final contacts = await FlutterContacts.getContacts(withProperties: true);
    contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
    if (mounted) {
      setState(() {
        _contacts = contacts;
        _filtered = contacts;
        _loading = false;
      });
    }
  }

  void _filter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _contacts
          : _contacts.where((c) => c.displayName.toLowerCase().contains(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(children: [
            Text('Select Contact', style: AppTextStyles.h4),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search contacts...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: context.appBackground,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? ListView(physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(vertical: 8),
                  children: List.generate(5, (_) => const _ContactPickerSkeleton()))
              : _filtered.isEmpty
                  ? Center(child: Text('No contacts found', style: AppTextStyles.bodySmall))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final c = _filtered[i];
                        final initial = c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : '?';
                        final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(alpha:0.12),
                            child: Text(initial,
                                style: const TextStyle(fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700, color: AppColors.primary)),
                          ),
                          title: Text(c.displayName, style: AppTextStyles.labelLarge),
                          subtitle: phone.isNotEmpty ? Text(phone, style: AppTextStyles.bodySmall) : null,
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ── Family member skeleton card ────────────────────────────────────────────────

class _FamilyMemberSkeleton extends StatelessWidget {
  const _FamilyMemberSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: const AppShimmer(
        child: Row(
          children: [
            SkeletonCircle(size: 54),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 140, height: 14, radius: 4),
                  SizedBox(height: 6),
                  SkeletonBox(width: 200, height: 11, radius: 4),
                  SizedBox(height: 8),
                  SkeletonBox(width: 60, height: 20, radius: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactPickerSkeleton extends StatelessWidget {
  const _ContactPickerSkeleton();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: AppShimmer(
        child: Row(children: [
          SkeletonCircle(size: 40),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: double.infinity, height: 13, radius: 4),
            SizedBox(height: 5),
            SkeletonBox(width: 140, height: 11, radius: 4),
          ])),
        ]),
      ),
    );
  }
}
