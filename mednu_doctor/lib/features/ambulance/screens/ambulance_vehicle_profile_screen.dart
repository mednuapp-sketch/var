import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../../core/services/feedback_service.dart';
import '../models/vehicle_profile.dart';
import '../providers/ambulance_providers.dart';
import '../services/ambulance_profile_service.dart';

/// Vehicle + driver identity — a hero plate-number card (the vehicle's
/// equivalent of a profile photo, since what matters here is the vehicle,
/// not a headshot) plus an equipment checklist and document status.
///
/// This screen is also the module's only profile *write* path: creating
/// `ambulance_profiles/{uid}` here is what makes `firestore.rules`'
/// `isAmbulancePartner()` start returning true, i.e. what lets this account
/// see the shared dispatch queue at all. There is no separate onboarding
/// screen for this role, so the edit action lives on the screen that already
/// displays exactly these fields.
class AmbulanceVehicleProfileScreen extends ConsumerWidget {
  const AmbulanceVehicleProfileScreen({super.key});

  Future<void> _edit(BuildContext context, VehicleProfile current) async {
    final uid = AmbulanceProfileService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'You are not signed in.');
      return;
    }

    final plate = TextEditingController(
        text: current.plateNumber == 'Not set' ? '' : current.plateNumber);
    final vehicleType = TextEditingController(
        text: current.vehicleType == 'Unverified' ? '' : current.vehicleType);
    final driverName = TextEditingController(text: current.driverName);
    final driverPhone = TextEditingController(text: current.driverPhone);
    final driverLicense = TextEditingController(text: current.driverLicense);
    final equipment = TextEditingController(text: current.equipment.join(', '));

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vehicle & Driver Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: plate, decoration: const InputDecoration(labelText: 'Plate number')),
              TextField(
                controller: vehicleType,
                decoration: const InputDecoration(
                  labelText: 'Vehicle type',
                  hintText: 'Basic Life Support / Advanced Life Support / ICU on Wheels',
                ),
              ),
              TextField(controller: driverName, decoration: const InputDecoration(labelText: 'Driver name')),
              TextField(
                controller: driverPhone,
                keyboardType: TextInputType.phone,
                readOnly: true,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Driver phone',
                  suffixIcon: Icon(Icons.verified_rounded, color: AppColors.success, size: 18),
                  helperText: 'Verified via OTP — cannot be changed',
                ),
              ),
              TextField(controller: driverLicense, decoration: const InputDecoration(labelText: 'Driver license')),
              TextField(
                controller: equipment,
                decoration: const InputDecoration(
                  labelText: 'Onboard equipment',
                  hintText: 'Comma separated',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;

    final equipmentList = equipment.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    try {
      final exists = await AmbulanceProfileService.profileExists(uid);
      if (exists) {
        // A self-update can't touch status/isVerified/rating/totalTrips —
        // firestore.rules rejects those keys, so they're deliberately absent.
        await AmbulanceProfileService.updateProfile(uid, {
          'plateNumber': plate.text.trim(),
          'vehicleType': vehicleType.text.trim(),
          'driverName': driverName.text.trim(),
          'driverPhone': driverPhone.text.trim(),
          'driverLicense': driverLicense.text.trim(),
          'equipment': equipmentList,
        });
      } else {
        await AmbulanceProfileService.createProfile(
          uid: uid,
          plateNumber: plate.text.trim(),
          vehicleType: vehicleType.text.trim(),
          driverName: driverName.text.trim(),
          driverPhone: driverPhone.text.trim(),
          driverLicense: driverLicense.text.trim(),
          equipment: equipmentList,
        );
      }
      if (context.mounted) FeedbackService.showSuccess(context, 'Vehicle profile saved');
    } catch (_) {
      if (context.mounted) {
        FeedbackService.showError(context, "Couldn't save your profile. Please try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(vehicleProfileProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.ambulanceVehicleProfile,
      title: 'Vehicle Profile',
      extraActions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
          onPressed: () => _edit(context, vehicle),
          tooltip: 'Edit vehicle details',
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
          onPressed: () => context.push(AppRoutes.ambulanceSettings),
          tooltip: 'Settings',
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF37474F), Color(0xFF102027)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: Column(
              children: [
                const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 40),
                const SizedBox(height: 12),
                Text(
                  vehicle.plateNumber,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.5),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: Text(vehicle.vehicleType, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _HeroStat(label: 'Rating', value: vehicle.rating.toStringAsFixed(1), icon: Icons.star_rounded),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'Trips', value: '${vehicle.totalTrips}', icon: Icons.route_rounded),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Driver', style: AppTextStyles.labelMedium),
                    const Spacer(),
                    if (vehicle.documentsVerified) const StatusBadge(label: 'Verified', color: AppColors.success, icon: Icons.verified_rounded),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SharedProfileAvatar(name: vehicle.driverName, size: 46, isVerified: vehicle.documentsVerified),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(vehicle.driverName, style: AppTextStyles.labelLarge),
                          Text(vehicle.driverPhone, style: AppTextStyles.bodySmall),
                          Text('License: ${vehicle.driverLicense}', style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Onboard Equipment', style: AppTextStyles.labelMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: vehicle.equipment
                      .map((e) => InfoChip(icon: Icons.check_circle_outline_rounded, label: e, color: AppColors.success))
                      .toList(),
                ),
              ],
            ),
          ),
          if (AmbulanceProfileService.currentUid != null) ...[
            const SizedBox(height: 16),
            PartnerDocumentsSection(
              role: 'ambulance',
              uid: AmbulanceProfileService.currentUid!,
              documents: vehicle.documents,
              documentVerification: vehicle.documentVerification,
              locked: vehicle.status == 'active',
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _HeroStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.amberAccent, size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
        Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Colors.white60)),
      ],
    );
  }
}
