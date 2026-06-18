import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../providers/location_provider.dart';
import '../widgets/home_widgets.dart';
import '../../auth/providers/auth_provider.dart';

import '../../banners/providers/banner_provider.dart';
import '../../banners/presentation/banner_popup_widget.dart';
import '../../health/screens/prescription_viewer_screen.dart';
import 'global_search_screen.dart';
import 'location_picker_screen.dart';
import '../../my_services/screens/my_services_screen.dart';
import '../../doctors/screens/doctors_list_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _exitDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Called by the platform (Android back gesture) before GoRouter processes it.
  // Observers are invoked in LIFO order, so this runs before GoRouter's Router widget.
  @override
  Future<bool> didPopRoute() async {
    // If GoRouter has a pushed sub-route (e.g. /consultation), let GoRouter pop it.
    if (GoRouter.of(context).canPop()) {
      GoRouter.of(context).pop();
      return true;
    }
    // Guard against double-open while dialog is awaiting.
    if (_exitDialogOpen) return true;
    // Non-home tab → switch to Home first.
    if (_currentIndex != 0) {
      if (mounted) setState(() => _currentIndex = 0);
      return true;
    }
    // Already on Home tab → ask to exit.
    _exitDialogOpen = true;
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Exit MedNU?',
            style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to exit the app?',
            style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Exit',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: Colors.red)),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (shouldExit == true && mounted) SystemNavigator.pop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _HomeBody(),
          DoctorsListScreen(showBackButton: false),
          MyServicesScreen(),
          _ProfileBody(),
        ],
      ),
      bottomNavigationBar: _MedNUBottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

class _HomeBody extends ConsumerStatefulWidget {
  const _HomeBody();
  @override
  ConsumerState<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends ConsumerState<_HomeBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotCtrl;
  late final Animation<double> _dotAnim;

  // Shown at most once per app session — resets on every cold launch
  static bool _bannerShownThisSession = false;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _dotAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _dotCtrl, curve: Curves.easeInOut),
    );
    // Show promotional banner after the first frame settles
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 900), _checkAndShowBanner);
    });
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAndShowBanner() async {
    if (!mounted || _bannerShownThisSession) return;
    try {
      final banner = await ref.read(activeBannerProvider.future);
      if (banner == null || !mounted) return;

      _bannerShownThisSession = true;
      await showBannerPopup(context, banner);
    } catch (_) {
      // Never crash the home screen because of a banner error
    }
  }

  void _openPicker() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => const LocationPickerScreen(),
        transitionsBuilder: (_, anim, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 320),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locState = ref.watch(locationProvider);
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Location row ──────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _openPicker,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (locState.isDetecting)
                                    AnimatedBuilder(
                                      animation: _dotAnim,
                                      builder: (_, __) => Opacity(
                                        opacity: _dotAnim.value,
                                        child: const Icon(
                                          Icons.gps_fixed_rounded,
                                          size: 14,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    )
                                  else
                                    const Icon(Icons.location_on_outlined,
                                        size: 14, color: AppColors.primary),
                                  const SizedBox(width: 3),
                                  Text('Your Location',
                                      style: AppTextStyles.caption),
                                  const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 14,
                                      color: AppColors.primary),
                                ],
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: locState.isDetecting
                                    ? _DetectingDots(key: const ValueKey('detecting'))
                                    : Text(
                                        locState.displayName,
                                        key: ValueKey(locState.displayName),
                                        style: AppTextStyles.labelLarge,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.account_balance_wallet_outlined,
                            color:
                                Theme.of(context).colorScheme.onSurface),
                        onPressed: () => context.push(AppRoutes.wallet),
                      ),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          IconButton(
                            icon: Icon(Icons.notifications_outlined,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface),
                            onPressed: () =>
                                context.push(AppRoutes.notifications),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // ── Search bar ────────────────────────────
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const GlobalSearchScreen(),
                        fullscreenDialog: true,
                      ),
                    ),
                    child: Builder(builder: (ctx) {
                      final isDark = Theme.of(ctx).brightness == Brightness.dark;
                      return Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkCard
                              : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withOpacity(0.09)
                                : Theme.of(context).colorScheme.outline.withOpacity(0.15),
                          ),
                          boxShadow: isDark
                              ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))]
                              : null,
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            Icon(Icons.search_rounded,
                                size: 20,
                                color: isDark
                                    ? const Color(0xFF4A6080)
                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.45)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Search doctors, specialties, hospitals...',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: isDark
                                      ? const Color(0xFF4A6080)
                                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(isDark ? 0.18 : 0.10),
                                borderRadius: BorderRadius.circular(9),
                                border: isDark
                                    ? Border.all(color: AppColors.primary.withOpacity(0.3), width: 1)
                                    : null,
                              ),
                              child: const Icon(Icons.tune_rounded,
                                  size: 16, color: AppColors.primary),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DoctorConsultBanner(),
                const SizedBox(height: 20),
                const SpecialtiesSection(),
                const SizedBox(height: 16),
                const FamilyRow(),
                const SizedBox(height: 12),
                const NotificationStrip(),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Our Services', style: AppTextStyles.h4),
                ),
                const SizedBox(height: 10),
                const ServiceGrid(),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Upcoming', style: AppTextStyles.h4),
                      TextButton(
                          onPressed: () =>
                              context.push(AppRoutes.appointment),
                          child: const Text('View All')),
                    ],
                  ),
                ),
                const UpcomingAppointmentCard(),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Health Tips', style: AppTextStyles.h4),
                ),
                const SizedBox(height: 12),
                const HealthTipCard(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Animated "Detecting…" dots widget ────────────────────
class _DetectingDots extends StatefulWidget {
  const _DetectingDots({super.key});
  @override
  State<_DetectingDots> createState() => _DetectingDotsState();
}

class _DetectingDotsState extends State<_DetectingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Detecting',
                style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
            const SizedBox(width: 3),
            ...List.generate(3, (i) {
              final opacity = ((t * 3 - i).clamp(0.0, 1.0));
              return Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Opacity(
                  opacity: opacity < 0.5 ? opacity * 2 : (1 - opacity) * 2,
                  child: const Text('.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      )),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// ── Doctors discovery body ───────────────────────────────
class _FindBody extends ConsumerStatefulWidget {
  const _FindBody();
  @override
  ConsumerState<_FindBody> createState() => _FindBodyState();
}

class _FindBodyState extends ConsumerState<_FindBody> {
  final _searchCtrl = TextEditingController();
  String _selectedSpec = 'All';

  static const _specFilters = [
    'All', 'General', 'Cardiology', 'Endocrinology',
    'Gastroenterology', 'Nephrology', 'Urology', 'Neurology',
    'Pulmonology', 'Gynaecology', 'Dermatology', 'General Surgery',
    'Orthopaedics', 'Ophthalmology', 'ENT', 'Paediatrics',
    'Psychiatry', 'Dental', 'Rheumatology', 'Oncology',
  ];


  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final city = ref.watch(locationProvider).displayName;
    return SafeArea(
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (_, anim, __) => const LocationPickerScreen(),
                        transitionsBuilder: (_, anim, __, child) => SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 1),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                          child: child,
                        ),
                        transitionDuration: const Duration(milliseconds: 320),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Find your Doctor', style: AppTextStyles.h3),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 12, color: AppColors.primary),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text('$city  ▾',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const GlobalSearchScreen(),
                      fullscreenDialog: true,
                    ),
                  ),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.09),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.tune_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                ),
              ],
            ),
          ),
          // ── Search bar ──────────────────────────────────
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search doctors, specialties, hospitals…',
                prefixIcon:
                    const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // ── Scrollable body ─────────────────────────────
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Consult Top Doctors banner
                _ConsultTopDoctorsBanner(),
                const SizedBox(height: 20),
                // Specialty filter chips
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Specialties', style: AppTextStyles.h4),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _specFilters.length,
                    itemBuilder: (_, i) {
                      final s = _specFilters[i];
                      final active = s == _selectedSpec;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedSpec = s),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.primary
                                : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: active
                                  ? AppColors.primary
                                  : Theme.of(context).colorScheme.outline.withOpacity(0.4),
                            ),
                          ),
                          child: Text(
                            s,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: active
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Top Doctors list
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Top Doctors Near You',
                          style: AppTextStyles.h4),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('doctors')
                            .where('status', isEqualTo: 'active')
                            .limit(50)
                            .snapshots(),
                        builder: (_, snap) {
                          final count = snap.data?.docs.length ?? 0;
                          return Text(
                            count > 0 ? '$count found' : '',
                            style: AppTextStyles.bodySmall,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _FindDoctorList(
                  spec: _selectedSpec,
                  search: _searchCtrl.text.toLowerCase(),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Consult top doctors banner (teal) ────────────────────
class _ConsultTopDoctorsBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.consultation),
      child: Container(
      // Full-width, no horizontal margin
      margin: const EdgeInsets.only(top: 8),
      height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: AppColors.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -15, top: -15,
            child: Container(width: 80, height: 80,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle))),
          Positioned(
            right: 50, bottom: -25,
            child: Container(width: 60, height: 60,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), shape: BoxShape.circle))),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Consult Top Doctors',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                              fontWeight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(height: 3),
                      const Text('Video & chat with specialists',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
                      const SizedBox(height: 8),
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                              color: Colors.white, borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Quick Connect',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                                      fontWeight: FontWeight.w700, color: AppColors.primary)),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_forward_rounded, size: 12, color: AppColors.primary),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Doctor photo
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                  ),
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: 'https://images.unsplash.com/photo-1559839734-2b71ea197ec2?w=200&h=200&fit=crop&crop=face&q=80',
                      width: 80, height: 80,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Colors.white.withOpacity(0.18),
                        child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 32),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.white.withOpacity(0.18),
                        child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 32),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

// ── Real-time Firestore doctor list for Find tab ─────────
class _FindDoctorList extends StatelessWidget {
  final String spec;
  final String search;
  const _FindDoctorList({required this.spec, required this.search});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('doctors')
          .where('status', isEqualTo: 'active')
          .orderBy('rating', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snap.data?.docs ?? [];
        final filtered = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final docSpec = (data['specialty'] as String? ?? '');
          final name = (data['name'] as String? ?? '').toLowerCase();
          final matchSpec = spec == 'All' || docSpec == spec;
          final matchQ = search.isEmpty ||
              name.contains(search) ||
              docSpec.toLowerCase().contains(search);
          return matchSpec && matchQ;
        }).toList();

        if (filtered.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.person_search_rounded,
                    size: 56, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  docs.isEmpty
                      ? 'No doctors available right now'
                      : 'No doctors match your filter',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textHint),
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
          );
        }

        return Column(
          children: filtered.map((doc) {
            return _DoctorCard(
              data: doc.data() as Map<String, dynamic>,
              docId: doc.id,
            );
          }).toList(),
        );
      },
    );
  }
}

// ── Doctor card ──────────────────────────────────────────
class _DoctorCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  const _DoctorCard({required this.data, required this.docId});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Doctor';
    final spec = data['specialty'] as String? ?? '';
    final qual = data['qualifications'] as String? ?? '';
    final rating = (data['rating'] as num?)?.toStringAsFixed(1) ?? '–';
    final reviews = data['totalConsultations']?.toString() ?? '0';
    final exp = data['experience'] as String? ?? '';
    final fee = data['fee']?.toString() ?? '–';
    final isOnline = data['isOnline'] as bool? ?? false;
    final photoUrl = data['photoUrl'] as String? ?? '';

    return GestureDetector(
      onTap: () => context.push('/doctors/$docId'),
      child: Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadow,
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          // Photo
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: photoUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photoUrl,
                        width: 68, height: 68,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _photoPlaceholder(),
                        errorWidget: (_, __, ___) => _photoPlaceholder(),
                      )
                    : _photoPlaceholder(),
              ),
              if (isOnline)
                Positioned(
                  bottom: 2, right: 2,
                  child: Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(
                  qual.isNotEmpty ? '$spec · $qual' : spec,
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Color(0xFFF57F17), size: 14),
                    const SizedBox(width: 3),
                    Text(rating,
                        style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    Text(' ($reviews)',
                        style: AppTextStyles.caption),
                    if (exp.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.work_outline_rounded,
                          size: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
                      const SizedBox(width: 3),
                      Text(exp.contains('yr') ? exp : '$exp yrs',
                          style: AppTextStyles.caption),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Builder(builder: (ctx) {
                      final isDark = Theme.of(ctx).brightness == Brightness.dark;
                      return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOnline
                            ? const Color(0xFF2E7D32).withOpacity(isDark ? 0.18 : 0.12)
                            : const Color(0xFFE65100).withOpacity(isDark ? 0.18 : 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isOnline
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFF7043),
                        ),
                      ),
                    );
                    }),
                    const SizedBox(width: 8),
                    Text('₹$fee / consult',
                        style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          // Consult button
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => _ConsultConfirmSheet(data: data, docId: docId),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Consult',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  )),
            ),
          ),
        ],
      ),
    ),
    );
  }

  static Widget _photoPlaceholder() => Container(
    width: 68, height: 68,
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFFF8BBD0), Color(0xFFE1BEE7)]),
    ),
    child: const Icon(Icons.person_rounded, color: AppColors.primary, size: 36),
  );
}

class _RecordsBody extends StatefulWidget {
  const _RecordsBody();
  @override
  State<_RecordsBody> createState() => _RecordsBodyState();
}

class _RecordsBodyState extends State<_RecordsBody> with SingleTickerProviderStateMixin {
  late TabController _tab;

  StreamSubscription? _prescSub;
  List<Map<String, dynamic>> _prescriptions = [];
  bool _prescLoading = true;
  String? _sharingRxId;

  StreamSubscription? _consultSub;
  List<Map<String, dynamic>> _consultations = [];
  bool _consultLoading = true;

  // Reports are loaded from Firestore, not hardcoded
  StreamSubscription? _reportsSub;
  List<Map<String, dynamic>> _reports = [];
  bool _reportsLoading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _subscribePrescriptions();
    _subscribeReports();
    _subscribeConsultations();
  }

  void _subscribeReports() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _reportsLoading = false); return; }
    _reportsSub = FirebaseFirestore.instance
        .collection('reports')
        .where('patientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _reports = snap.docs.map((doc) {
          final d = Map<String, dynamic>.from(doc.data());
          d['id'] = doc.id;
          return d;
        }).toList();
        _reportsLoading = false;
      });
    }, onError: (_) { if (mounted) setState(() => _reportsLoading = false); });
  }

  void _subscribePrescriptions() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _prescLoading = false); return; }
    _prescSub = FirebaseFirestore.instance
        .collection('prescriptions')
        .where('patientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _prescriptions = snap.docs.map((doc) {
          final d = Map<String, dynamic>.from(doc.data());
          d['id'] = doc.id;
          return d;
        }).toList();
        _prescLoading = false;
      });
    }, onError: (_) { if (mounted) setState(() => _prescLoading = false); });
  }

  void _subscribeConsultations() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _consultLoading = false); return; }
    _consultSub = FirebaseFirestore.instance
        .collection('consultations')
        .where('patientId', isEqualTo: uid)
        .where('status', isEqualTo: 'ended')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _consultations = snap.docs.map((doc) {
          final d = Map<String, dynamic>.from(doc.data());
          d['id'] = doc.id;
          return d;
        }).toList();
        _consultLoading = false;
      });
    }, onError: (_) { if (mounted) setState(() => _consultLoading = false); });
  }

  Future<void> _sharePrescription(Map<String, dynamic> rx) async {
    final id = rx['id'] as String? ?? '';
    if (_sharingRxId != null) return;
    setState(() => _sharingRxId = id);
    try {
      await sharePrescription(rx);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
    } finally {
      if (mounted) setState(() => _sharingRxId = null);
    }
  }

  String _fmtDate(dynamic ts) {
    if (ts == null) return '';
    final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
    return DateFormat('d MMM yyyy').format(dt);
  }

  String _fmtDateTime(dynamic ts) {
    if (ts == null) return '';
    final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
    return DateFormat('d MMM yyyy, h:mm a').format(dt);
  }

  Color _specColor(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'cardiologist':  return const Color(0xFFC2185B);
      case 'dermatologist': return const Color(0xFF00897B);
      case 'neurologist':   return const Color(0xFF5E35B1);
      case 'pediatrician':  return const Color(0xFFE65100);
      case 'orthopedic':    return const Color(0xFF1565C0);
      default:              return AppColors.primary;
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _prescSub?.cancel();
    _reportsSub?.cancel();
    _consultSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('My Health Records'),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          tabs: const [Tab(text: 'Prescriptions'), Tab(text: 'Reports'), Tab(text: 'Consultations')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildPrescriptions(),
          _buildReports(),
          _buildConsultations(),
        ],
      ),
    );
  }

  Widget _buildPrescriptions() {
    if (_prescLoading) return const Center(child: CircularProgressIndicator());
    if (_prescriptions.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 80, height: 80, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), shape: BoxShape.circle), child: const Icon(Icons.receipt_long_rounded, size: 40, color: AppColors.primary)),
        const SizedBox(height: 16),
        Text('No prescriptions yet', style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text('Prescriptions from your doctors\nwill appear here after consultations', style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _prescriptions.length,
      itemBuilder: (ctx, i) {
        final rx = _prescriptions[i];
        final color = _specColor(rx['doctorSpecialty'] as String?);
        final meds = rx['medicines'] as List<dynamic>? ?? [];
        final isSharingThis = _sharingRxId == (rx['id'] as String? ?? '');
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push(AppRoutes.prescriptionViewer, extra: rx),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(width: 46, height: 46, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.receipt_long_rounded, color: color, size: 24)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(rx['doctorName'] as String? ?? 'Doctor', style: AppTextStyles.labelLarge),
                    if ((rx['doctorSpecialty'] as String? ?? '').isNotEmpty)
                      Text(rx['doctorSpecialty'] as String, style: AppTextStyles.bodySmall.copyWith(color: color)),
                    Text(_fmtDate(rx['createdAt']), style: AppTextStyles.bodySmall),
                    Text('${meds.length} medicine${meds.length == 1 ? '' : 's'} prescribed', style: AppTextStyles.bodySmall),
                  ])),
                  isSharingThis
                      ? const SizedBox(width: 48, height: 48, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))))
                      : IconButton(
                          icon: const Icon(Icons.share_rounded, color: AppColors.textHint),
                          tooltip: 'Share Prescription',
                          onPressed: () => _sharePrescription(rx),
                        ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReports() {
    if (_reportsLoading) return const Center(child: CircularProgressIndicator());
    if (_reports.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 80, height: 80, decoration: BoxDecoration(color: const Color(0xFF0097A7).withValues(alpha: 0.08), shape: BoxShape.circle), child: const Icon(Icons.science_rounded, size: 40, color: Color(0xFF0097A7))),
        const SizedBox(height: 16),
        Text('No reports uploaded yet', style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text('Go to Records to upload your lab reports', style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => context.push(AppRoutes.records, extra: {'tab': 1}),
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Upload Report'),
        ),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _reports.length,
      itemBuilder: (ctx, i) {
        final r = _reports[i];
        final name = r['name'] as String? ?? 'Report';
        final status = r['status'] as String? ?? 'Uploaded';
        final imageUrl = r['imageUrl'] as String? ?? '';
        final dateStr = _fmtDate(r['createdAt']);
        Color statusColor;
        switch (status.toLowerCase()) {
          case 'normal': statusColor = const Color(0xFF2E7D32); break;
          case 'review': statusColor = const Color(0xFFE65100); break;
          case 'high':   statusColor = const Color(0xFFC62828); break;
          default:       statusColor = AppColors.primary;
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push(AppRoutes.records, extra: {'tab': 1}),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrl.isNotEmpty
                        ? Image.network(imageUrl, width: 46, height: 46, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 46, height: 46, decoration: BoxDecoration(color: const Color(0xFF0097A7).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.science_rounded, color: Color(0xFF0097A7), size: 24)))
                        : Container(width: 46, height: 46, decoration: BoxDecoration(color: const Color(0xFF0097A7).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.science_rounded, color: Color(0xFF0097A7), size: 24)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: AppTextStyles.labelLarge),
                    if (dateStr.isNotEmpty) Text(dateStr, style: AppTextStyles.bodySmall),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(status, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 20),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConsultations() {
    if (_consultLoading) return const Center(child: CircularProgressIndicator());
    if (_consultations.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 80, height: 80, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), shape: BoxShape.circle), child: const Icon(Icons.video_call_rounded, size: 40, color: AppColors.primary)),
        const SizedBox(height: 16),
        Text('No consultations yet', style: AppTextStyles.h4.copyWith(color: AppColors.textHint)),
        const SizedBox(height: 4),
        Text('Start a video consultation to see history here', style: AppTextStyles.bodySmall),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _consultations.length,
      itemBuilder: (ctx, i) {
        final c = _consultations[i];
        final color = _specColor(c['doctorSpecialty'] as String?);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.local_hospital_rounded, color: color, size: 24)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c['doctorName'] as String? ?? 'Doctor', style: AppTextStyles.labelLarge),
              if ((c['doctorSpecialty'] as String? ?? '').isNotEmpty)
                Text(c['doctorSpecialty'] as String, style: AppTextStyles.bodySmall.copyWith(color: color)),
              const SizedBox(height: 4),
              Text(_fmtDateTime(c['createdAt']), style: AppTextStyles.bodySmall),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Text('Completed', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
            ),
          ]),
        );
      },
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final uid = user?.uid ?? '';
    final userDoc = uid.isNotEmpty
        ? ref.watch(userDocProvider(uid))
        : const AsyncValue<Map<String, dynamic>?>.data(null);

    final docData = userDoc.valueOrNull;
    final name = docData?['name'] as String? ?? user?.displayName ?? 'MedNU User';
    final email = docData?['email'] as String? ?? user?.email ?? '';
    final phone = docData?['phone'] as String? ?? user?.phoneNumber ?? '';
    final photoUrl = docData?['photoUrl'] as String? ?? user?.photoURL ?? '';
    final walletBalance = (docData?['walletBalance'] ?? 0.0) as num;
    final referralCode = docData?['referralCode'] as String? ?? '—';
    final referralPoints = (docData?['referralPoints'] ?? 0) as num;
    final isPremium = docData?['isPremium'] as bool? ?? false;
    final isMale = (docData?['gender'] as String? ?? '').toLowerCase() == 'male';

    // One-time migration: regenerate legacy referral codes that don't match XXXX#### format
    if (docData != null && uid.isNotEmpty) {
      final validFormat = RegExp(r'^[A-Z]{4}[0-9]{4}$').hasMatch(referralCode);
      if (!validFormat) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final newCode = generateReferralCode(name, uid);
          FirebaseFirestore.instance.collection('users').doc(uid).update({'referralCode': newCode});
        });
      }
    }
    final initials = name.trim().isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : 'M';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Header: gradient bar + floating avatar + name ──
          SliverToBoxAdapter(
            child: _ProfileHeader(
              name: name,
              phone: phone,
              email: email,
              photoUrl: photoUrl,
              initials: initials,
              isPremium: isPremium,
              onEditTap: () => context.push(AppRoutes.profile),
              onSettingsTap: () => context.push(AppRoutes.settings),
            ),
          ),

          // ── Body ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.account_balance_wallet_rounded,
                          iconColor: const Color(0xFF1565C0),
                          iconBg: const Color(0xFFE3F2FD),
                          label: 'Wallet',
                          value: '₹${walletBalance.toStringAsFixed(0)}',
                          onTap: () => context.push(AppRoutes.wallet),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.card_giftcard_rounded,
                          iconColor: const Color(0xFF6A1B9A),
                          iconBg: const Color(0xFFF3E5F5),
                          label: 'Referral Pts',
                          value: '$referralPoints pts',
                          onTap: () => context.push(AppRoutes.referral),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: isPremium
                              ? Icons.workspace_premium_rounded
                              : Icons.star_border_rounded,
                          iconColor: const Color(0xFFE65100),
                          iconBg: const Color(0xFFFFF3E0),
                          label: 'Plan',
                          value: isPremium ? 'Premium' : 'Free',
                          onTap: () => context.push(AppRoutes.premium),
                        ),
                      ),
                    ],
                  ),
                ),

                // Referral banner
                if (referralCode != '—') ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _ReferralBanner(
                      referralCode: referralCode,
                      onShare: () {
                        Share.share(
                          'Join MedNu — your personal health companion! Use my referral code $referralCode to get started.\nDownload: https://mednu.app',
                          subject: 'Join MedNu with my referral code',
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // MY HEALTH section
                _MenuSection(title: 'MY HEALTH', items: [
                  _MenuItem(icon: Icons.calendar_month_rounded, iconColor: const Color(0xFF1565C0), label: 'My Appointments', onTap: () => context.push(AppRoutes.appointment)),
                  _MenuItem(icon: Icons.medical_services_rounded, iconColor: AppColors.primary, label: 'My Services', badge: 'Tracker', onTap: () => context.push(AppRoutes.myServices)),
                  _MenuItem(icon: Icons.favorite_rounded, iconColor: const Color(0xFFE53935), label: 'Favourite Doctors', onTap: () => context.push(AppRoutes.favouriteDoctors)),
                  _MenuItem(icon: Icons.folder_rounded, iconColor: const Color(0xFF2E7D32), label: 'My Health Records', onTap: () => context.push(AppRoutes.records)),
                  _MenuItem(icon: Icons.people_rounded, iconColor: const Color(0xFFC2185B), label: 'Family Members', onTap: () => context.push(AppRoutes.family)),
                  _MenuItem(icon: Icons.medication_rounded, iconColor: const Color(0xFF00695C), label: 'My Medicines', onTap: () => context.push(AppRoutes.medicine)),
                  _MenuItem(icon: Icons.monitor_heart_rounded, iconColor: AppColors.primary, label: 'Health Dashboard', onTap: () => context.push(AppRoutes.healthDashboard)),
                  if (!isMale)
                    _MenuItem(icon: Icons.favorite_rounded, iconColor: const Color(0xFFE91E8C), label: 'Period Tracker', onTap: () => context.push(AppRoutes.periodTracker)),
                  _MenuItem(icon: Icons.water_drop_rounded, iconColor: const Color(0xFF1565C0), label: 'Water Reminder', onTap: () => context.push(AppRoutes.waterReminder)),
                  _MenuItem(icon: Icons.receipt_long_rounded, iconColor: const Color(0xFF2E7D32), label: 'Prescription Viewer', onTap: () => context.push(AppRoutes.prescriptionViewer)),
                  _MenuItem(icon: Icons.local_shipping_rounded, iconColor: const Color(0xFFE65100), label: 'Track Order', onTap: () => context.push(AppRoutes.orderTracking)),
                  _MenuItem(icon: Icons.health_and_safety_rounded, iconColor: const Color(0xFF0097A7), label: 'Post-Consultation', onTap: () => context.push(AppRoutes.postConsultation)),
                ]),

                const SizedBox(height: 12),

                _MenuSection(title: 'ACCOUNT', items: [
                  _MenuItem(icon: Icons.account_balance_wallet_rounded, iconColor: const Color(0xFF1565C0), label: 'Payments & Wallet', trailing: '₹${walletBalance.toStringAsFixed(0)}', onTap: () => context.push(AppRoutes.wallet)),
                  _MenuItem(icon: Icons.workspace_premium_rounded, iconColor: const Color(0xFFE65100), label: 'Upgrade to Premium', onTap: () => context.push(AppRoutes.premium)),
                  _MenuItem(icon: Icons.card_giftcard_rounded, iconColor: const Color(0xFF6A1B9A), label: 'Referral & Rewards', trailing: '$referralPoints pts', onTap: () => context.push(AppRoutes.referral)),
                ]),

                const SizedBox(height: 12),

                _MenuSection(title: 'MORE', items: [
                  _MenuItem(icon: Icons.school_rounded, iconColor: const Color(0xFF0097A7), label: 'Health Education', onTap: () => context.push(AppRoutes.education)),
                  _MenuItem(icon: Icons.language_rounded, iconColor: const Color(0xFF283593), label: 'Language', onTap: () => context.push(AppRoutes.language)),
                  _MenuItem(icon: Icons.help_outline_rounded, iconColor: const Color(0xFF00695C), label: 'Help & Support', onTap: () => context.push(AppRoutes.helpSupport)),
                  _MenuItem(icon: Icons.privacy_tip_outlined, iconColor: AppColors.textSecondary, label: 'Privacy Policy', onTap: () => context.push(AppRoutes.privacyPolicy)),
                  _MenuItem(icon: Icons.info_outline_rounded, iconColor: AppColors.textSecondary, label: 'About MedNU', onTap: () => context.push(AppRoutes.about)),
                ]),

                const SizedBox(height: 20),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: const _SignOutButton(),
                ),

                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'MedNU v1.0.0 · Made with ❤️ in India',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile Header ─────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final String name, phone, email, photoUrl, initials;
  final bool isPremium;
  final VoidCallback onEditTap, onSettingsTap;

  const _ProfileHeader({
    required this.name,
    required this.phone,
    required this.email,
    required this.photoUrl,
    required this.initials,
    required this.isPremium,
    required this.onEditTap,
    required this.onSettingsTap,
  });

  static const double _avatarHalf = 44.0;

  @override
  Widget build(BuildContext context) {
    final contact = phone.isNotEmpty ? phone : email;
    return Column(
      children: [
        // Gradient section — avatar floats at the boundary
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // Gradient background, height driven by content
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: AppColors.heroBannerGradient,
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  // Bottom padding reserves space for the avatar's top half
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, _avatarHalf + 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          'My Profile',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      _HeaderIconButton(icon: Icons.edit_outlined, onTap: onEditTap),
                      const SizedBox(width: 8),
                      _HeaderIconButton(icon: Icons.settings_outlined, onTap: onSettingsTap),
                    ],
                  ),
                ),
              ),
            ),
            // Avatar centred at the gradient/white fold
            Positioned(
              bottom: -_avatarHalf,
              child: _ProfileAvatar(photoUrl: photoUrl, initials: initials),
            ),
          ],
        ),

        // Compensate for avatar overflow + gap before name
        const SizedBox(height: _avatarHalf + 14),

        // Name — centred, handles long names gracefully
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.25,
            ),
          ),
        ),

        // Contact (phone or email)
        if (contact.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            contact,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
        ],

        // Premium badge
        if (isPremium) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFFB300), Color(0xFFFFA000)]),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFFFB300).withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium_rounded, size: 13, color: Colors.white),
                SizedBox(width: 5),
                Text(
                  'PREMIUM',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

// ── Profile Avatar ──────────────────────────────────────────────────────────────

class _ProfileAvatar extends StatelessWidget {
  final String photoUrl;
  final String initials;
  const _ProfileAvatar({required this.photoUrl, required this.initials});

  static const double _size = 88.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3.5),
            boxShadow: [
              BoxShadow(
                  color: AppColors.primary.withOpacity(0.28),
                  blurRadius: 20,
                  offset: const Offset(0, 6)),
              BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: ClipOval(
            child: photoUrl.isNotEmpty
                ? Image.network(photoUrl, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _initialsWidget())
                : _initialsWidget(),
          ),
        ),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: const Icon(Icons.camera_alt_rounded, size: 13, color: Colors.white),
        ),
      ],
    );
  }

  Widget _initialsWidget() => Container(
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        child: Center(
          child: Text(
            initials,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );
}

// ── Stat Card ──────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor, iconBg;
  final String label, value;
  final VoidCallback onTap;
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isDark ? iconColor.withOpacity(0.1) : AppColors.shadow,
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark ? iconColor.withOpacity(0.18) : iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Referral Banner ────────────────────────────────────────────────────────────

class _ReferralBanner extends StatelessWidget {
  final String referralCode;
  final VoidCallback onShare;
  const _ReferralBanner({required this.referralCode, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onShare,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(0.07),
              AppColors.secondary.withOpacity(0.07),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withOpacity(0.22), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.share_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Referral Code',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    referralCode,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Text(
                'Share',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Menu Section ───────────────────────────────────────────────────────────────

class _MenuSection extends StatelessWidget {
  final String title;
  final List<Widget> items;
  const _MenuSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black.withOpacity(0.3) : AppColors.shadow,
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  items[i],
                  if (i < items.length - 1)
                    Divider(
                      height: 1,
                      indent: 66,
                      endIndent: 0,
                      color: isDark
                          ? Colors.white.withOpacity(0.06)
                          : const Color(0xFFF0F0F0),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Menu Item ──────────────────────────────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? trailing;
  final String? badge;
  final VoidCallback onTap;
  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.trailing,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: iconColor.withOpacity(0.08),
        highlightColor: iconColor.withOpacity(0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isDark
                      ? iconColor.withOpacity(0.15)
                      : iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: iconColor, size: 19),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white.withOpacity(0.9) : AppColors.textPrimary,
                  ),
                ),
              ),
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (trailing != null) ...[
                Text(
                  trailing!,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: isDark ? Colors.white30 : AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sign Out Button ────────────────────────────────────────────────────────────

class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Sign Out',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            content: const Text('Are you sure you want to sign out?',
                style: TextStyle(fontFamily: 'Poppins')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sign Out',
                    style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          await ref.read(authProvider.notifier).signOut();
          if (context.mounted) context.go(AppRoutes.login);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.error.withOpacity(0.2)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: AppColors.error, size: 18),
            SizedBox(width: 8),
            Text(
              'Sign Out',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedNUBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _MedNUBottomNav(
      {required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.07)
                : Colors.black.withOpacity(0.06),
            width: 1,
          ),
        ),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 32,
                  offset: const Offset(0, -8),
                ),
                BoxShadow(
                  color: AppColors.primaryGlowDark,
                  blurRadius: 40,
                  offset: const Offset(0, -2),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(icon: Icons.home_rounded, label: 'Home', index: 0, currentIndex: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.person_search_rounded, label: 'Doctors', index: 1, currentIndex: currentIndex, onTap: onTap),
              GestureDetector(
                onTap: () => context.push(AppRoutes.sos),
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(isDark ? 0.5 : 0.3),
                        blurRadius: isDark ? 20 : 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.emergency_rounded, color: Colors.white, size: 22),
                      Text('SOS', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                    ],
                  ),
                ),
              ),
              _NavItem(icon: Icons.calendar_month_rounded, label: 'Services', index: 2, currentIndex: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.person_outline_rounded, label: 'Profile', index: 3, currentIndex: currentIndex, onTap: onTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _NavItem({required this.icon, required this.label, required this.index, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark
        ? const Color(0xFF4A6080)
        : Theme.of(context).colorScheme.onSurface.withOpacity(0.40);

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark
                  ? AppColors.primary.withOpacity(0.14)
                  : AppColors.primary.withOpacity(0.08))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isActive && isDark
              ? Border.all(color: AppColors.primary.withOpacity(0.25), width: 1)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                icon,
                key: ValueKey(isActive),
                size: 24,
                color: isActive ? AppColors.primary : inactiveColor,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: isActive ? AppColors.primary : inactiveColor,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Consult confirmation sheet ───────────────────────────
class _ConsultConfirmSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  const _ConsultConfirmSheet({required this.data, required this.docId});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Doctor';
    final spec = data['specialty'] as String? ?? '';
    final qual = data['qualifications'] as String? ?? '';
    final fee = data['fee']?.toString() ?? '–';
    final isOnline = data['isOnline'] as bool? ?? false;
    final photoUrl = data['photoUrl'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: photoUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: photoUrl, width: 64, height: 64, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _placeholder(),
                  )
                : _placeholder(),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: AppTextStyles.labelLarge),
            Text(qual.isNotEmpty ? '$spec · $qual' : spec, style: AppTextStyles.bodySmall),
            const SizedBox(height: 6),
            Text('₹$fee / consult', style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ])),
          Builder(builder: (ctx) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isOnline
                    ? const Color(0xFF2E7D32).withOpacity(isDark ? 0.18 : 0.12)
                    : const Color(0xFFE65100).withOpacity(isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isOnline ? 'Online' : 'Offline',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600,
                  color: isOnline ? const Color(0xFF4CAF50) : const Color(0xFFFF7043)),
              ),
            );
          }),
        ]),
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _ConsultTypeOption(icon: Icons.video_call_rounded, label: 'Video Call', sublabel: 'Connect online now')),
          const SizedBox(width: 12),
          Expanded(child: _ConsultTypeOption(icon: Icons.calendar_month_rounded, label: 'Book Slot', sublabel: 'Schedule for later')),
        ]),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              context.push(AppRoutes.consultation);
            },
            icon: const Icon(Icons.video_call_rounded, size: 20),
            label: const Text('Consult Now'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/doctors/$docId');
            },
            child: const Text('View Full Profile'),
          ),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }

  static Widget _placeholder() => Container(
    width: 64, height: 64,
    decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFF8BBD0), Color(0xFFE1BEE7)])),
    child: const Icon(Icons.person_rounded, color: AppColors.primary, size: 32),
  );
}

class _ConsultTypeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  const _ConsultTypeOption({required this.icon, required this.label, required this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(children: [
        Icon(icon, color: AppColors.primary, size: 28),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700)),
        Text(sublabel, style: AppTextStyles.caption, textAlign: TextAlign.center),
      ]),
    );
  }
}
