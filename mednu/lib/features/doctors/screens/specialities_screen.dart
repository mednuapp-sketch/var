import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/r.dart';

class SpecialitiesScreen extends StatefulWidget {
  const SpecialitiesScreen({super.key});

  @override
  State<SpecialitiesScreen> createState() => _SpecialitiesScreenState();
}

class _SpecialitiesScreenState extends State<SpecialitiesScreen> {
  String _search = '';

  static const List<_SpecialtyData> _items = [
    _SpecialtyData('General Physician', 'General',
        Icons.medical_services_rounded, Color(0xFF1565C0), Color(0xFFE3F2FD)),
    _SpecialtyData('Cardiologist', 'Cardiology',
        Icons.favorite_rounded, Color(0xFFE53935), Color(0xFFFFEBEE)),
    _SpecialtyData('Dermatologist', 'Dermatology',
        Icons.face_rounded, Color(0xFF6A1B9A), Color(0xFFF3E5F5)),
    _SpecialtyData('Gynecologist', 'Gynaecology',
        Icons.pregnant_woman_rounded, Color(0xFFA36BAC), Color(0xFFFCE4EC)),
    _SpecialtyData('Neurologist', 'Neurology',
        Icons.psychology_rounded, Color(0xFF5E35B1), Color(0xFFEDE7F6)),
    _SpecialtyData('Orthopedic', 'Orthopaedics',
        Icons.accessibility_new_rounded, Color(0xFF795548), Color(0xFFEFEBE9)),
    _SpecialtyData('Pediatrician', 'Paediatrics',
        Icons.child_care_rounded, Color(0xFF2E7D32), Color(0xFFE8F5E9)),
    _SpecialtyData('ENT Specialist', 'ENT',
        Icons.hearing_rounded, Color(0xFF00695C), Color(0xFFE0F2F1)),
    _SpecialtyData('Ophthalmologist', 'Ophthalmology',
        Icons.visibility_rounded, Color(0xFF0277BD), Color(0xFFE1F5FE)),
    _SpecialtyData('Psychiatrist', 'Psychiatry',
        Icons.self_improvement_rounded, Color(0xFF37474F), Color(0xFFECEFF1)),
    _SpecialtyData('Endocrinologist', 'Endocrinology',
        Icons.science_rounded, Color(0xFF558B2F), Color(0xFFF1F8E9)),
    _SpecialtyData('Gastroenterologist', 'Gastroenterology',
        Icons.monitor_heart_rounded, Color(0xFFE65100), Color(0xFFFBE9E7)),
    _SpecialtyData('Nephrologist', 'Nephrology',
        Icons.water_drop_rounded, Color(0xFF283593), Color(0xFFE8EAF6)),
    _SpecialtyData('Urologist', 'Urology',
        Icons.health_and_safety_rounded, Color(0xFF633058), Color(0xFFF3E5F5)),
    _SpecialtyData('Pulmonologist', 'Pulmonology',
        Icons.air_rounded, Color(0xFF006064), Color(0xFFE0F7FA)),
    _SpecialtyData('General Surgeon', 'General Surgery',
        Icons.cut_rounded, Color(0xFF4E342E), Color(0xFFEFEBE9)),
    _SpecialtyData('Dentist', 'Dental',
        Icons.mood_rounded, Color(0xFF00838F), Color(0xFFE0F2F1)),
    _SpecialtyData('Rheumatologist', 'Rheumatology',
        Icons.elderly_rounded, Color(0xFF827717), Color(0xFFF9FBE7)),
    _SpecialtyData('Oncologist', 'Oncology',
        Icons.biotech_rounded, Color(0xFFBF360C), Color(0xFFFBE9E7)),
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? _items
        : _items
            .where((s) => s.label.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: R.h(context, 130),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient),
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              minHeight: constraints.maxHeight),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(R.p(context, 20),
                                R.p(context, 44), R.p(context, 20),
                                R.p(context, 12)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Specialities',
                                    style: AppTextStyles.onPrimaryH2),
                                SizedBox(height: R.h(context, 4)),
                                const Text('Browse doctors by medical specialty',
                                    style: AppTextStyles.onPrimaryBody),
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

          // ── Search bar ────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 14),
                  R.p(context, 16), 0),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'Search specialities…',
                  hintStyle: TextStyle(
                      fontFamily: 'Poppins', fontSize: 13,
                      color: context.appTextHint),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: context.appTextHint, size: 20),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: context.appTextHint, size: 18),
                          onPressed: () => setState(() => _search = ''),
                        )
                      : null,
                  filled: true,
                  fillColor: context.appSurface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.r(context, 14)),
                      borderSide: BorderSide.none),
                  contentPadding:
                      EdgeInsets.symmetric(vertical: R.p(context, 13)),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 12),
                  R.p(context, 16), R.p(context, 8)),
              child: Row(children: [
                Icon(Icons.grid_view_rounded,
                    size: R.w(context, 16), color: context.appTextSecondary),
                SizedBox(width: R.w(context, 6)),
                Text(
                  _search.isEmpty
                      ? '${_items.length} Specialities Available'
                      : '${filtered.length} result${filtered.length == 1 ? '' : 's'} for "$_search"',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: context.appTextSecondary),
                ),
              ]),
            ),
          ),

          filtered.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: R.p(context, 48)),
                    child: Column(
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: R.w(context, 48), color: context.appTextHint),
                        SizedBox(height: R.h(context, 12)),
                        Text('No speciality found for "$_search"',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: context.appTextSecondary)),
                      ],
                    ),
                  ),
                )
              : SliverPadding(
                  padding: EdgeInsets.fromLTRB(R.p(context, 16), 0,
                      R.p(context, 16), R.p(context, 24)),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.82,
                      crossAxisSpacing: R.p(context, 12),
                      mainAxisSpacing: R.p(context, 12),
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _SpecialtyCard(item: filtered[i]),
                      childCount: filtered.length,
                    ),
                  ),
                ),

          SliverToBoxAdapter(
            child: _PopularNowSection(),
          ),

          SliverToBoxAdapter(child: SizedBox(height: R.h(context, 24))),
        ],
      ),
    );
  }
}

class _SpecialtyCard extends StatelessWidget {
  final _SpecialtyData item;
  const _SpecialtyCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/doctors?specialty=${item.firestoreKey}'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(R.r(context, 18)),
          border: Border.all(color: context.appBorder),
          boxShadow: [
            BoxShadow(
              color: item.color.withValues(alpha:0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: R.w(context, 52),
              height: R.h(context, 52),
              decoration: BoxDecoration(
                color: item.bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon, color: item.color, size: R.w(context, 26)),
            ),
            SizedBox(height: R.h(context, 10)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: R.p(context, 6)),
              child: Text(
                item.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.appTextPrimary,
                  height: 1.3,
                ),
              ),
            ),
            SizedBox(height: R.h(context, 6)),
            _DoctorCountBadge(specialty: item.firestoreKey),
          ],
        ),
      ),
    );
  }
}

class _DoctorCountBadge extends StatelessWidget {
  final String specialty;
  const _DoctorCountBadge({required this.specialty});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('doctors')
          .where('specialty', isEqualTo: specialty)
          .snapshots(),
      builder: (_, snap) {
        final count = snap.data?.docs.length ?? 0;
        if (count == 0 && snap.connectionState == ConnectionState.waiting) {
          return SizedBox(height: R.h(context, 14));
        }
        return Container(
          padding: EdgeInsets.symmetric(
              horizontal: R.p(context, 8), vertical: R.p(context, 2)),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha:0.08),
            borderRadius: BorderRadius.circular(R.r(context, 8)),
          ),
          child: Text(
            count == 0 ? 'No doctors' : '$count doctor${count == 1 ? '' : 's'}',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        );
      },
    );
  }
}

class _PopularNowSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('doctors')
          .where('isOnline', isEqualTo: true)
          .limit(6)
          .snapshots(),
      builder: (_, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 8),
                  R.p(context, 16), R.p(context, 12)),
              child: Row(
                children: [
                  const Text('Available Now', style: AppTextStyles.h4),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.push('/doctors'),
                    child: Text(
                      'See all',
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: R.h(context, 112),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: R.p(context, 16)),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final id = docs[i].id;
                  final name = d['name'] as String? ?? 'Doctor';
                  final spec = d['specialty'] as String? ?? '';
                  final photo = d['photoUrl'] as String? ?? '';
                  return GestureDetector(
                    onTap: () => context.push('/doctors/$id'),
                    child: Container(
                      width: R.w(context, 84),
                      margin: EdgeInsets.only(right: R.p(context, 12)),
                      padding: EdgeInsets.all(R.p(context, 8)),
                      decoration: BoxDecoration(
                        color: context.appSurface,
                        borderRadius: BorderRadius.circular(R.r(context, 14)),
                        border: Border.all(color: context.appBorder),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            children: [
                              Container(
                                width: R.w(context, 46),
                                height: R.h(context, 46),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha:0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: photo.isNotEmpty
                                    ? ClipOval(
                                        child: Image.network(
                                          photo,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(Icons.person_rounded,
                                                  size: 26,
                                                  color: AppColors.primary),
                                        ),
                                      )
                                    : const Icon(Icons.person_rounded,
                                        size: 26, color: AppColors.primary),
                              ),
                              Positioned(
                                bottom: 1,
                                right: 1,
                                child: Container(
                                  width: R.w(context, 11),
                                  height: R.h(context, 11),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 1.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: R.h(context, 6)),
                          Text(
                            name.split(' ').take(2).join(' '),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: context.appTextPrimary,
                            ),
                          ),
                          Text(
                            spec,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 9,
                              color: context.appTextHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: R.h(context, 8)),
          ],
        );
      },
    );
  }
}

class _SpecialtyData {
  final String label;
  final String firestoreKey;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _SpecialtyData(
      this.label, this.firestoreKey, this.icon, this.color, this.bgColor);
}
