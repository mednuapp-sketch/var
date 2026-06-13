import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/router/app_router.dart';
import '../providers/nutrition_provider.dart';
import '../models/nutritionist_model.dart';
import '../../../../core/widgets/ux_widgets.dart';

class NutritionistListScreen extends ConsumerStatefulWidget {
  const NutritionistListScreen({super.key});

  @override
  ConsumerState<NutritionistListScreen> createState() => _NutritionistListScreenState();
}

class _NutritionistListScreenState extends ConsumerState<NutritionistListScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  static const _specialties = [
    'All',
    'Weight Loss',
    'Diabetes Diet',
    'Heart Healthy',
    'Pregnancy Nutrition',
    'Sports Nutrition',
    'PCOS Diet',
    'Child Nutrition',
    'Oncology Diet',
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedSpecialty = ref.watch(nutritionistSpecialtyFilterProvider);
    final nutritionists = ref.watch(nutritionistsStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Find Nutritionist', style: AppTextStyles.h3),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
      ),
      body: Column(
        children: [
          _SearchBar(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          ),
          _SpecialtyFilter(
            specialties: _specialties,
            selected: selectedSpecialty ?? 'All',
            onSelect: (s) => ref.read(nutritionistSpecialtyFilterProvider.notifier).state =
                s == 'All' ? null : s,
          ),
          Expanded(
            child: nutritionists.when(
              loading: () => ListView(physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(vertical: 8),
                children: List.generate(6, (_) => const SkeletonListTile())),
              error: (e, _) => const AppErrorState(),
              data: (list) {
                final filtered = _searchQuery.isEmpty
                    ? list
                    : list.where((n) =>
                        n.name.toLowerCase().contains(_searchQuery) ||
                        n.specialization.toLowerCase().contains(_searchQuery) ||
                        n.qualification.toLowerCase().contains(_searchQuery) ||
                        n.city.toLowerCase().contains(_searchQuery)).toList();

                if (filtered.isEmpty) {
                  return _EmptyState(query: _searchQuery);
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  physics: const BouncingScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) => _NutritionistCard(
                    nutritionist: filtered[i],
                    onTap: () => context.push(
                      AppRoutes.nutritionNutritionistProfile.replaceFirst(':id', filtered[i].id),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: AppTextStyles.bodyMedium,
        decoration: InputDecoration(
          hintText: 'Search by name, specialty, city...',
          hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: AppColors.textHint),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.background,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

class _SpecialtyFilter extends StatelessWidget {
  final List<String> specialties;
  final String selected;
  final ValueChanged<String> onSelect;

  const _SpecialtyFilter({required this.specialties, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: specialties.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final s = specialties[i];
          final isSelected = s == selected || (selected == 'All' && s == 'All');
          return GestureDetector(
            onTap: () => onSelect(s),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF2E7D32) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? const Color(0xFF2E7D32) : AppColors.border),
              ),
              child: Text(
                s,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NutritionistCard extends StatelessWidget {
  final NutritionistModel nutritionist;
  final VoidCallback onTap;

  const _NutritionistCard({required this.nutritionist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(name: nutritionist.name, photoUrl: nutritionist.photoUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(nutritionist.name, style: AppTextStyles.labelLarge)),
                          if (nutritionist.isAvailable)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha:0.1), borderRadius: BorderRadius.circular(6)),
                              child: const Text('Available', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(nutritionist.qualification, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                      Text(nutritionist.specialization, style: AppTextStyles.bodySmall.copyWith(color: const Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _InfoChip(icon: Icons.star_rounded, label: '${nutritionist.rating.toStringAsFixed(1)} (${nutritionist.reviewCount})', color: const Color(0xFFF9A825)),
                const SizedBox(width: 8),
                _InfoChip(icon: Icons.work_rounded, label: '${nutritionist.experienceYears} yrs exp', color: AppColors.textSecondary),
                const SizedBox(width: 8),
                _InfoChip(icon: Icons.location_on_rounded, label: nutritionist.city.isNotEmpty ? nutritionist.city : 'Online', color: AppColors.textSecondary),
              ],
            ),
            if (nutritionist.expertiseAreas.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: nutritionist.expertiseAreas.take(4).map((e) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha:0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(e, style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: Color(0xFF2E7D32))),
                )).toList(),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Consultation Fee', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
                      Text('₹${nutritionist.consultationFee.toInt()}', style: AppTextStyles.h4.copyWith(color: const Color(0xFF2E7D32))),
                    ],
                  ),
                ),
                Row(
                  children: [
                    if (nutritionist.isOnlineAvailable)
                      _ModeChip(label: 'Online', icon: Icons.videocam_rounded),
                    if (nutritionist.isInPersonAvailable) ...[
                      const SizedBox(width: 6),
                      _ModeChip(label: 'In-Person', icon: Icons.location_on_rounded),
                    ],
                  ],
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('Book', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String photoUrl;
  const _Avatar({required this.name, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: photoUrl.isNotEmpty
          ? Image.network(photoUrl, width: 64, height: 64, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _Fallback(name: name))
          : _Fallback(name: name),
    );
  }
}

class _Fallback extends StatelessWidget {
  final String name;
  const _Fallback({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'N',
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: color)),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _ModeChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32).withValues(alpha:0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha:0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: const Color(0xFF2E7D32)),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: Color(0xFF2E7D32))),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              query.isNotEmpty ? 'No results for "$query"' : 'No nutritionists available',
              style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              query.isNotEmpty
                  ? 'Try a different search term or filter'
                  : 'Nutritionists will appear here once added by admin',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
