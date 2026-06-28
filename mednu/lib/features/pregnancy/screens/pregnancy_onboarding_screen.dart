import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
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
  late final AnimationController _progressAnim;

  // ── Page 1 — Basic Info ───────────────────────────────────────────────────
  DateTime? _lmpDate;
  DateTime? _dueDate;
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _ageCtrl    = TextEditingController();
  final _formKey1   = GlobalKey<FormState>();

  // ── Page 2 — Health History ───────────────────────────────────────────────
  int _previousPregnancies = 0;
  int _previousLiveBirths  = 0;
  int _previousAbortions   = 0;
  int _previousCSections   = 0;
  final List<String> _medicalConditions = [];
  final _gynNotesCtrl = TextEditingController();
  final _formKey2     = GlobalKey<FormState>();

  // ── Page 3 — Emergency ────────────────────────────────────────────────────
  final _emergencyNameCtrl  = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();
  final _formKey3           = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _progressAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 0,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _progressAnim.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _ageCtrl.dispose();
    _gynNotesCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    super.dispose();
  }

  DateTime _calcDueDate(DateTime lmp) => lmp.add(const Duration(days: 280));

  void _nextPage() {
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
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
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
    final isHighRisk = _medicalConditions.isNotEmpty ||
        _previousPregnancies >= 3 ||
        _previousCSections >= 2;
    final profile = PregnancyProfile(
      id: '',
      patientId: uid,
      pregnancyStartDate: _lmpDate!,
      lmpDate: _lmpDate!,
      dueDate: _dueDate ?? _calcDueDate(_lmpDate!),
      weightKg: double.tryParse(_weightCtrl.text) ?? 0,
      heightCm: double.tryParse(_heightCtrl.text),
      ageYears: int.tryParse(_ageCtrl.text) ?? 0,
      medicalConditions: List.from(_medicalConditions),
      previousPregnancies: _previousPregnancies,
      previousLiveBirths: _previousLiveBirths,
      previousAbortions: _previousAbortions,
      previousCSections: _previousCSections,
      gynecologyNotes: _gynNotesCtrl.text.trim(),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF0F5),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildProgressIndicator(),
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
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    child: Row(
      children: [
        GestureDetector(
          onTap: () => context.pop(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF880E4F)),
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Pregnancy Profile',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
            Text('Set up your maternity care',
                style: TextStyle(fontSize: 13, color: Color(0xFF616161))),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('${_currentPage + 1}/3',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
        ),
      ],
    ),
  );

  Widget _buildProgressIndicator() {
    const labels = ['Basic Info', 'Health History', 'Emergency'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        children: List.generate(3, (i) {
          final active = i <= _currentPage;
          final isCurrent = i == _currentPage;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        height: isCurrent ? 5 : 4,
                        decoration: BoxDecoration(
                          gradient: active
                              ? const LinearGradient(colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)])
                              : null,
                          color: active ? null : AppColors.border,
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: isCurrent ? [
                            BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 6)
                          ] : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(labels[i],
                          style: TextStyle(
                              fontSize: 10,
                              color: active ? AppColors.primary : AppColors.textHint,
                              fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
                    ],
                  ),
                ),
                if (i < 2) const SizedBox(width: 4),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── Page 1: Basic Info ────────────────────────────────────────────────────

  Widget _buildPage1() => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Form(
      key: _formKey1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionCard(
            icon: Icons.pregnant_woman_rounded,
            title: 'Pregnancy Dates',
            children: [
              _datePicker(
                label: 'Last Menstrual Period (LMP) *',
                value: _lmpDate,
                icon: Icons.calendar_today_rounded,
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
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 4),
                  child: Text('LMP date is required',
                      style: TextStyle(fontSize: 11, color: Colors.red)),
                ),
              const SizedBox(height: 12),
              _datePicker(
                label: 'Expected Due Date (auto-calculated)',
                value: _dueDate,
                icon: Icons.event_rounded,
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
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            icon: Icons.person_outline_rounded,
            title: 'Your Details',
            children: [
              _fieldRow([
                _buildField(
                  controller: _weightCtrl,
                  label: 'Current Weight (kg) *',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if ((double.tryParse(v) ?? 0) <= 0) return 'Enter valid weight';
                    return null;
                  },
                ),
                _buildField(
                  controller: _heightCtrl,
                  label: 'Height (cm)',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ]),
              const SizedBox(height: 12),
              _buildField(
                controller: _ageCtrl,
                label: 'Age (years) *',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  final age = int.tryParse(v) ?? 0;
                  if (age < 10 || age > 60) return 'Enter valid age';
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
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Form(
      key: _formKey2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionCard(
            icon: Icons.history_rounded,
            title: 'Previous Pregnancy History',
            children: [
              _counterRow('Previous Pregnancies', _previousPregnancies,
                  (v) => setState(() => _previousPregnancies = v)),
              const Divider(height: 20, color: AppColors.divider),
              _counterRow('Previous Live Births', _previousLiveBirths,
                  (v) => setState(() => _previousLiveBirths = v)),
              const Divider(height: 20, color: AppColors.divider),
              _counterRow('Abortions / Miscarriages', _previousAbortions,
                  (v) => setState(() => _previousAbortions = v)),
              const Divider(height: 20, color: AppColors.divider),
              _counterRow('Previous C-Sections', _previousCSections,
                  (v) => setState(() => _previousCSections = v)),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            icon: Icons.medical_information_rounded,
            title: 'Known Medical Conditions',
            subtitle: 'Select all that apply',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  'Diabetes', 'Hypertension', 'Thyroid', 'Anemia',
                  'Heart Disease', 'Asthma', 'PCOD/PCOS',
                  'Multiple pregnancy', 'Preeclampsia history',
                ].map((c) {
                  final selected = _medicalConditions.contains(c);
                  return FilterChip(
                    label: Text(c, style: TextStyle(
                      fontSize: 12,
                      color: selected ? Colors.white : AppColors.textPrimary,
                    )),
                    selected: selected,
                    selectedColor: AppColors.primary,
                    backgroundColor: Colors.white,
                    checkmarkColor: Colors.white,
                    side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
                    onSelected: (v) => setState(() {
                      if (v) _medicalConditions.add(c);
                      else _medicalConditions.remove(c);
                    }),
                  );
                }).toList(),
              ),
              if (_medicalConditions.isNotEmpty || _previousCSections >= 2) ...[
                const SizedBox(height: 12),
                _highRiskBanner(),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            icon: Icons.note_alt_rounded,
            title: 'Gynecology & Health Notes',
            subtitle: 'PCOS, thyroid, fibroids, medications, complications…',
            children: [
              TextFormField(
                controller: _gynNotesCtrl,
                maxLines: 5,
                minLines: 3,
                decoration: InputDecoration(
                  hintText: 'E.g. Diagnosed with PCOS, on Metformin 500mg. Had a previous C-section in 2021. No current complications.',
                  hintStyle: const TextStyle(fontSize: 12, color: AppColors.textHint),
                  filled: true,
                  fillColor: const Color(0xFFF7F4F8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(12),
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
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3E0),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.4)),
    ),
    child: const Row(
      children: [
        Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 14),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            'You may be marked as high-risk. Your care team will provide extra monitoring.',
            style: TextStyle(fontSize: 11, color: Color(0xFFE65100)),
          ),
        ),
      ],
    ),
  );

  // ── Page 3: Emergency Contact ─────────────────────────────────────────────

  Widget _buildPage3() => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Form(
      key: _formKey3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionCard(
            icon: Icons.emergency_rounded,
            title: 'Emergency Contact',
            subtitle: 'Who should we contact in an emergency?',
            children: [
              _buildField(
                controller: _emergencyNameCtrl,
                label: 'Contact Name *',
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _emergencyPhoneCtrl,
                label: 'Phone Number *',
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.replaceAll(RegExp(r'\D'), '').length < 10) {
                    return 'Enter valid phone number';
                  }
                  return null;
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFCE4EC), Color(0xFFF3E5F5)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.favorite_rounded, color: AppColors.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text("You're almost ready!",
                          style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF880E4F))),
                      SizedBox(height: 4),
                      Text(
                        'MedNu will guide you through every step of your beautiful journey.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF616161), height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );

  // ── Bottom Bar ────────────────────────────────────────────────────────────

  Widget _buildBottomBar() => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, -2))],
    ),
    child: Row(
      children: [
        if (_currentPage > 0)
          Expanded(
            flex: 1,
            child: OutlinedButton(
              onPressed: () => _pageController.previousPage(
                  duration: const Duration(milliseconds: 350), curve: Curves.easeInOut),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Back',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
          ),
        if (_currentPage > 0) const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Consumer(builder: (ctx, ref, _) {
            final loading = ref.watch(pregnancyProvider).isLoading;
            return ElevatedButton(
              onPressed: loading ? null : _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      _currentPage < 2 ? 'Continue' : 'Start Journey',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1A2E))),
                    if (subtitle != null)
                      Text(subtitle,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF616161))),
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
    DateTime? value,
    required IconData icon,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F4F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: value != null ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value != null ? DateFormat('dd MMM yyyy').format(value) : label,
                style: TextStyle(
                  fontSize: 13,
                  color: value != null ? AppColors.textPrimary : AppColors.textHint,
                  fontWeight: value != null ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 20),
          ]),
        ),
      );

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFF7F4F8),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      );

  Widget _fieldRow(List<Widget> fields) {
    final items = <Widget>[];
    for (int i = 0; i < fields.length; i++) {
      items.add(Expanded(child: fields[i]));
      if (i < fields.length - 1) items.add(const SizedBox(width: 10));
    }
    return Row(children: items);
  }

  Widget _counterRow(String label, int value, void Function(int) onChanged) => Row(
    children: [
      Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
      _counterBtn(Icons.remove_rounded, () { if (value > 0) onChanged(value - 1); }),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('$value',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ),
      _counterBtn(Icons.add_rounded, () => onChanged(value + 1)),
    ],
  );

  Widget _counterBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: AppColors.primary),
    ),
  );
}
