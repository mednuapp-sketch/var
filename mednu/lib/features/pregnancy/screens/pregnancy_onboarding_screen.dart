import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../models/pregnancy_models.dart';
import '../providers/pregnancy_provider.dart';

class PregnancyOnboardingScreen extends ConsumerStatefulWidget {
  const PregnancyOnboardingScreen({super.key});

  @override
  ConsumerState<PregnancyOnboardingScreen> createState() =>
      _PregnancyOnboardingScreenState();
}

class _PregnancyOnboardingScreenState
    extends ConsumerState<PregnancyOnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  int _currentPage = 0;

  // Page 1 — Pregnancy Dates & Basic Info
  DateTime? _lmpDate;
  DateTime? _dueDate;
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _ageCtrl    = TextEditingController();
  final _formKey1   = GlobalKey<FormState>();

  // Page 2 — Health History
  int _previousPregnancies = 0;
  int _previousLiveBirths  = 0;
  int _previousAbortions   = 0;
  int _previousCSections   = 0;
  String _previousBirthType = 'Not specified';
  final List<String> _gynConditions    = [];
  final List<String> _medicalConditions = [];
  final _gynNotesCtrl = TextEditingController();
  final _formKey2     = GlobalKey<FormState>();

  // Page 3 — Emergency Contact & Summary
  final _emergencyNameCtrl  = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();
  final _formKey3           = GlobalKey<FormState>();

  late final AnimationController _progressAnim;

  @override
  void initState() {
    super.initState();
    _progressAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _ageCtrl.dispose();
    _gynNotesCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    _progressAnim.dispose();
    super.dispose();
  }

  DateTime _calcDueDate(DateTime lmp) => lmp.add(const Duration(days: 280));

  int get _weeksPregnant {
    if (_lmpDate == null) return 0;
    return (DateTime.now().difference(_lmpDate!).inDays / 7).floor().clamp(0, 40);
  }

  void _nextPage() {
    FocusScope.of(context).unfocus();
    if (_currentPage == 0) {
      if (_lmpDate == null) {
        _showSnack('Please select your last menstrual period date.');
        return;
      }
      if (!(_formKey1.currentState?.validate() ?? false)) return;
    } else if (_currentPage == 1) {
      if (!(_formKey2.currentState?.validate() ?? false)) return;
    }
    if (_currentPage < 2) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    if (!(_formKey3.currentState?.validate() ?? false)) return;
    if (_lmpDate == null) {
      _showSnack('Please select your last menstrual period date.');
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      _showSnack('Authentication error. Please log in again.');
      return;
    }
    final allConditions = [..._medicalConditions, ..._gynConditions];
    final birthTypeNote = _previousLiveBirths > 0 && _previousBirthType != 'Not specified'
        ? 'Last birth type: $_previousBirthType. '
        : '';
    final combinedNotes = '$birthTypeNote${_gynNotesCtrl.text.trim()}'.trim();
    final isHighRisk = allConditions.isNotEmpty ||
        _gynConditions.isNotEmpty ||
        _previousPregnancies >= 3 ||
        _previousCSections >= 2 ||
        _previousAbortions >= 2;

    final profile = PregnancyProfile(
      id: '',
      patientId: uid,
      pregnancyStartDate: _lmpDate!,
      lmpDate: _lmpDate!,
      dueDate: _dueDate ?? _calcDueDate(_lmpDate!),
      weightKg: double.tryParse(_weightCtrl.text) ?? 0,
      heightCm: double.tryParse(_heightCtrl.text),
      ageYears: int.tryParse(_ageCtrl.text) ?? 0,
      medicalConditions: allConditions,
      previousPregnancies: _previousPregnancies,
      previousLiveBirths: _previousLiveBirths,
      previousAbortions: _previousAbortions,
      previousCSections: _previousCSections,
      gynecologyNotes: combinedNotes,
      emergencyContactName: _emergencyNameCtrl.text.trim(),
      emergencyContactPhone: _emergencyPhoneCtrl.text.trim(),
      isHighRisk: isHighRisk,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final ok = await ref.read(pregnancyProvider.notifier).createProfile(profile);
    if (!mounted) return;
    if (ok) {
      context.go(AppRoutes.pregnancy);
    } else {
      _showSnack('Failed to save profile. Please try again.');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppTextStyles.bodyMedium.copyWith(color: Colors.white)),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _buildPage1(),
                  _buildPage2(),
                  _buildPage3(),
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(
    color: context.appSurface,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
    child: Column(
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pregnancy Profile',
                      style: AppTextStyles.h3.copyWith(color: context.appTextPrimary)),
                  Text('Set up your maternity care',
                      style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                gradient: AppColors.pregnancyGrad,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${_currentPage + 1} of 3',
                  style: AppTextStyles.labelSmall.copyWith(color: Colors.white)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: List.generate(3, (i) {
            const labels = ['Basic Info', 'Health History', 'Emergency'];
            final done = i < _currentPage;
            final active = i == _currentPage;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      height: 5,
                      decoration: BoxDecoration(
                        gradient: (active || done)
                            ? const LinearGradient(colors: [AppColors.primary, AppColors.secondary])
                            : null,
                        color: (active || done) ? null : context.appBorder,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: active
                            ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 8)]
                            : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(labels[i],
                        style: AppTextStyles.labelSmall.copyWith(
                            color: (active || done) ? AppColors.primary : context.appTextHint,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                  ],
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
      ],
    ),
  );

  // ── Page 1: Dates + Basic Info ────────────────────────────────────────────

  Widget _buildPage1() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Form(
      key: _formKey1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFCE4EC), Color(0xFFF3E5F5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                const Text('🤰', style: TextStyle(fontSize: 52)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hello, Mama! 💗',
                          style: AppTextStyles.h3.copyWith(color: AppColors.primaryDark)),
                      const SizedBox(height: 4),
                      Text(
                        _weeksPregnant > 0
                            ? 'Week $_weeksPregnant of your journey'
                            : 'Tell us about your pregnancy',
                        style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.primaryDark.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _sectionCard(
            icon: Icons.calendar_month_rounded,
            iconColor: AppColors.primary,
            title: 'Pregnancy Dates',
            children: [
              _datePicker(
                label: 'Last Menstrual Period (LMP)',
                hint: 'Tap to select date',
                value: _lmpDate,
                icon: Icons.event_available_rounded,
                required: true,
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().subtract(const Duration(days: 30)),
                    firstDate: DateTime.now().subtract(const Duration(days: 280)),
                    lastDate: DateTime.now(),
                    helpText: 'Select LMP Date',
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: const ColorScheme.light(primary: AppColors.primary),
                      ),
                      child: child!,
                    ),
                  );
                  if (d != null) {
                    setState(() {
                      _lmpDate = d;
                      _dueDate = _calcDueDate(d);
                    });
                  }
                },
              ),
              if (_lmpDate == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text('LMP date is required to calculate your week',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
                ),
              const SizedBox(height: 12),
              _datePicker(
                label: 'Expected Due Date',
                hint: _dueDate != null ? DateFormat('dd MMM yyyy').format(_dueDate!) : 'Auto-calculated from LMP',
                value: _dueDate,
                icon: Icons.child_care_rounded,
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 280)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 300)),
                    helpText: 'Adjust Due Date',
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: const ColorScheme.light(primary: AppColors.primary),
                      ),
                      child: child!,
                    ),
                  );
                  if (d != null) setState(() => _dueDate = d);
                },
              ),
              if (_lmpDate != null && _dueDate != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Week $_weeksPregnant · Due ${DateFormat('dd MMM yyyy').format(_dueDate!)}',
                          style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.primary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          _sectionCard(
            icon: Icons.person_rounded,
            iconColor: AppColors.secondary,
            title: 'Your Details',
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _weightCtrl,
                      label: 'Weight (kg)',
                      required: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if ((double.tryParse(v) ?? 0) <= 0) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _heightCtrl,
                      label: 'Height (cm)',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _ageCtrl,
                label: 'Age (years)',
                required: true,
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  final age = int.tryParse(v) ?? 0;
                  if (age < 10 || age > 60) return 'Enter a valid age';
                  return null;
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );

  // ── Page 2: Health History ────────────────────────────────────────────────

  Widget _buildPage2() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Form(
      key: _formKey2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF3E5F5), Color(0xFFEDE7F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.secondary.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                const Text('🏥', style: TextStyle(fontSize: 40)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Your health history helps us provide the best care for you and your baby.',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.secondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _sectionCard(
            icon: Icons.history_rounded,
            iconColor: const Color(0xFF42A5F5),
            title: 'Previous Pregnancy History',
            children: [
              _counterRow('Total Previous Pregnancies', _previousPregnancies,
                  (v) => setState(() => _previousPregnancies = v)),
              Divider(height: 20, color: context.appDivider),
              _counterRow('Previous Live Births', _previousLiveBirths,
                  (v) => setState(() {
                    _previousLiveBirths = v;
                    if (v == 0) _previousBirthType = 'Not specified';
                  })),
              if (_previousLiveBirths > 0) ...[
                const SizedBox(height: 12),
                Text('Birth type (last delivery)',
                    style: AppTextStyles.labelMedium.copyWith(color: context.appTextSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['Normal / Vaginal', 'C-Section', 'Assisted (Forceps/Vacuum)', 'Home Birth']
                      .map((t) {
                    final sel = _previousBirthType == t;
                    return GestureDetector(
                      onTap: () => setState(() => _previousBirthType = t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary : context.appSurface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? AppColors.primary : context.appBorder),
                        ),
                        child: Text(t,
                            style: AppTextStyles.bodySmall.copyWith(
                                color: sel ? Colors.white : context.appTextPrimary,
                                fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
                      ),
                    );
                  }).toList(),
                ),
              ],
              Divider(height: 20, color: context.appDivider),
              _counterRow('Abortions / Miscarriages', _previousAbortions,
                  (v) => setState(() => _previousAbortions = v)),
              Divider(height: 20, color: context.appDivider),
              _counterRow('Previous C-Sections', _previousCSections,
                  (v) => setState(() => _previousCSections = v)),
            ],
          ),
          const SizedBox(height: 14),

          _sectionCard(
            icon: Icons.female_rounded,
            iconColor: AppColors.primary,
            title: 'Gynecological Conditions',
            subtitle: 'Select all that apply',
            children: [
              _chipGrid(
                items: [
                  'PCOD / PCOS', 'Endometriosis', 'Uterine Fibroids',
                  'Ovarian Cysts', 'Cervical Incompetence', 'Ectopic Pregnancy',
                  'Irregular Periods', 'Pelvic Inflammatory Disease',
                  'Uterine Abnormality', 'Placenta Previa History',
                  'Endometrial Polyps', 'Hormonal Imbalance',
                  'Recurrent Miscarriages', 'Infertility Treatment',
                ],
                selected: _gynConditions,
                color: AppColors.primary,
                onToggle: (c, v) => setState(() {
                  if (v) _gynConditions.add(c); else _gynConditions.remove(c);
                }),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _sectionCard(
            icon: Icons.medical_information_rounded,
            iconColor: AppColors.error,
            title: 'General Health Conditions',
            subtitle: 'Select all that apply',
            children: [
              _chipGrid(
                items: [
                  'Diabetes', 'Gestational Diabetes', 'Hypertension', 'Thyroid',
                  'Anemia', 'Heart Disease', 'Asthma', 'Kidney Disease',
                  'Multiple Pregnancy (Twins+)', 'Preeclampsia History',
                ],
                selected: _medicalConditions,
                color: AppColors.error,
                onToggle: (c, v) => setState(() {
                  if (v) _medicalConditions.add(c); else _medicalConditions.remove(c);
                }),
              ),
              if (_medicalConditions.isNotEmpty || _gynConditions.isNotEmpty || _previousCSections >= 2) ...[
                const SizedBox(height: 12),
                _highRiskBanner(),
              ],
            ],
          ),
          const SizedBox(height: 14),

          _sectionCard(
            icon: Icons.note_alt_rounded,
            iconColor: AppColors.success,
            title: 'Additional Notes',
            subtitle: 'Medications, allergies, past surgeries…',
            children: [
              TextFormField(
                controller: _gynNotesCtrl,
                maxLines: 4,
                minLines: 3,
                style: AppTextStyles.bodyMedium,
                decoration: _inputDecoration(
                  hint: 'e.g. On Metformin 500mg. Allergic to penicillin. Previous C-section in 2021.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );

  Widget _highRiskBanner() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFFFC107).withValues(alpha: 0.5)),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'You may be classified as high-risk. Your care team will provide enhanced monitoring.',
            style: AppTextStyles.bodySmall.copyWith(color: const Color(0xFFE65100)),
          ),
        ),
      ],
    ),
  );

  // ── Page 3: Emergency + Summary ───────────────────────────────────────────

  Widget _buildPage3() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Form(
      key: _formKey3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE8F5E9), Color(0xFFF1F8E9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Text('📞', style: TextStyle(fontSize: 40)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Add an emergency contact so we can alert them if you need urgent care.',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.success),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _sectionCard(
            icon: Icons.emergency_rounded,
            iconColor: AppColors.error,
            title: 'Emergency Contact',
            subtitle: 'Who should we contact in an emergency?',
            children: [
              _buildField(
                controller: _emergencyNameCtrl,
                label: 'Contact Name',
                required: true,
                validator: (v) => (v == null || v.isEmpty) ? 'Contact name is required' : null,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _emergencyPhoneCtrl,
                label: 'Phone Number',
                required: true,
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Phone number is required';
                  if (v.replaceAll(RegExp(r'\D'), '').length < 10) {
                    return 'Enter a valid 10-digit phone number';
                  }
                  return null;
                },
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_lmpDate != null)
            _sectionCard(
              icon: Icons.summarize_rounded,
              iconColor: AppColors.secondary,
              title: 'Profile Summary',
              children: [
                _summaryRow('LMP Date', DateFormat('dd MMM yyyy').format(_lmpDate!), Icons.calendar_today_rounded),
                Divider(height: 16, color: context.appDivider),
                _summaryRow('Due Date', DateFormat('dd MMM yyyy').format(_dueDate ?? _calcDueDate(_lmpDate!)), Icons.child_care_rounded),
                Divider(height: 16, color: context.appDivider),
                _summaryRow('Pregnancy Week', 'Week $_weeksPregnant of 40', Icons.timeline_rounded),
                if (_weightCtrl.text.isNotEmpty) ...[
                  Divider(height: 16, color: context.appDivider),
                  _summaryRow('Starting Weight', '${_weightCtrl.text} kg', Icons.monitor_weight_rounded),
                ],
                if (_medicalConditions.isNotEmpty || _gynConditions.isNotEmpty) ...[
                  Divider(height: 16, color: context.appDivider),
                  _summaryRow('Conditions', '${_medicalConditions.length + _gynConditions.length} selected', Icons.medical_information_rounded),
                ],
              ],
            ),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFCE4EC), Color(0xFFF3E5F5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Text('💝', style: TextStyle(fontSize: 36)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("You're almost ready!",
                          style: AppTextStyles.h4.copyWith(color: AppColors.primaryDark)),
                      const SizedBox(height: 4),
                      Text(
                        'MedNU will guide and support you every step of this beautiful journey.',
                        style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primaryDark.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );

  Widget _summaryRow(String label, String value, IconData icon) => Row(
    children: [
      Icon(icon, size: 16, color: AppColors.secondary),
      const SizedBox(width: 8),
      Text(label, style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
      const Spacer(),
      Text(value,
          style: AppTextStyles.labelMedium.copyWith(color: context.appTextPrimary)),
    ],
  );

  // ── Bottom Bar ────────────────────────────────────────────────────────────

  Widget _buildBottomBar() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
    decoration: BoxDecoration(
      color: context.appSurface,
      boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 12,
          offset: const Offset(0, -3))],
    ),
    child: Row(
      children: [
        if (_currentPage > 0) ...[
          OutlinedButton(
            onPressed: () => _pageController.previousPage(
                duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Back',
                style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Consumer(builder: (ctx, ref, _) {
            final loading = ref.watch(pregnancyProvider).isLoading;
            return Container(
              height: 52,
              decoration: BoxDecoration(
                gradient: AppColors.pregnancyGrad,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: ElevatedButton(
                onPressed: loading ? null : _nextPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: loading
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        _currentPage < 2 ? 'Continue →' : '🌸  Start My Journey',
                        style: AppTextStyles.button,
                      ),
              ),
            );
          }),
        ),
      ],
    ),
  );

  // ── Reusable Widgets ──────────────────────────────────────────────────────

  Widget _sectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
                    if (subtitle != null)
                      Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );

  Widget _datePicker({
    required String label,
    required String hint,
    DateTime? value,
    required IconData icon,
    bool required = false,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: context.appBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: value != null ? AppColors.primary.withValues(alpha: 0.5) : context.appBorder),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: value != null ? AppColors.primary : context.appTextHint),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$label${required ? ' *' : ''}',
                      style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
                  const SizedBox(height: 2),
                  Text(
                    value != null ? DateFormat('dd MMM yyyy').format(value) : hint,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: value != null ? context.appTextPrimary : context.appTextHint,
                      fontWeight: value != null ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.appTextHint, size: 20),
          ]),
        ),
      );

  InputDecoration _inputDecoration({String hint = ''}) => InputDecoration(
    hintText: hint,
    hintStyle: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
    filled: true,
    fillColor: context.appBackground,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.appBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.appBorder)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
    contentPadding: const EdgeInsets.all(14),
  );

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    bool required = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: AppTextStyles.bodyMedium,
        decoration: InputDecoration(
          labelText: '$label${required ? ' *' : ''}',
          labelStyle: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
          filled: true,
          fillColor: context.appBackground,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.appBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.appBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      );

  Widget _chipGrid({
    required List<String> items,
    required List<String> selected,
    required Color color,
    required void Function(String, bool) onToggle,
  }) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((c) {
          final sel = selected.contains(c);
          return GestureDetector(
            onTap: () => onToggle(c, !sel),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: sel ? color : context.appSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? color : context.appBorder),
              ),
              child: Text(c,
                  style: AppTextStyles.bodySmall.copyWith(
                      color: sel ? Colors.white : context.appTextPrimary,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
            ),
          );
        }).toList(),
      );

  Widget _counterRow(String label, int value, void Function(int) onChanged) => Row(
    children: [
      Expanded(
          child: Text(label, style: AppTextStyles.bodyMedium.copyWith(color: context.appTextPrimary))),
      _counterBtn(Icons.remove_rounded, () { if (value > 0) onChanged(value - 1); }),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Text('$value',
            style: AppTextStyles.h2.copyWith(color: AppColors.primary)),
      ),
      _counterBtn(Icons.add_rounded, () => onChanged(value + 1)),
    ],
  );

  Widget _counterBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Icon(icon, size: 18, color: AppColors.primary),
    ),
  );
}
