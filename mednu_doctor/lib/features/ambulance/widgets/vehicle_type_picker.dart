import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../services/ambulance_profile_service.dart';

/// Pick-list of the canonical ambulance vehicle types (`basic` | `als` |
/// `icu`), labelled with the names the admin sets in
/// `app_config/ambulance_rates`. Replaces free-text entry so the rate range
/// can be resolved from the stored `vehicleTypeKey` without guessing.
class VehicleTypePicker extends StatefulWidget {
  /// Currently selected canonical key, or null when nothing is picked yet.
  final String? value;

  /// Called with the canonical key and its display label.
  final void Function(String key, String label) onChanged;

  /// Optional helper line (e.g. a prompt for legacy drivers).
  final String? helperText;

  const VehicleTypePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.helperText,
  });

  @override
  State<VehicleTypePicker> createState() => _VehicleTypePickerState();
}

class _VehicleTypePickerState extends State<VehicleTypePicker> {
  late final Future<Map<String, String>> _labels =
      AmbulanceProfileService.fetchVehicleTypeLabels();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _labels,
      initialData: AmbulanceProfileService.defaultVehicleTypeLabels,
      builder: (context, snap) {
        final labels = snap.data ?? AmbulanceProfileService.defaultVehicleTypeLabels;
        final selected = labels.containsKey(widget.value) ? widget.value : null;
        return DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Vehicle Type',
            prefixIcon: const Icon(Icons.airport_shuttle_outlined,
                color: AppColors.textSecondary),
            helperText: widget.helperText,
            helperMaxLines: 3,
          ),
          items: [
            for (final e in labels.entries)
              DropdownMenuItem<String>(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          validator: (v) => v == null ? 'Select a vehicle type' : null,
          onChanged: (k) {
            if (k != null) widget.onChanged(k, labels[k] ?? k);
          },
        );
      },
    );
  }
}
