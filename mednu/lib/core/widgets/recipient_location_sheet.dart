import 'dart:async';
import 'package:flutter/material.dart';
import '../../features/home/providers/location_provider.dart';
import '../../features/location/screens/map_location_picker_screen.dart';
import '../constants/app_colors.dart';
import '../services/places_service.dart';

/// A focused "pick a location for someone else" sheet — search-as-you-type
/// or drop a pin on a map, the same building blocks `LocationPickerScreen`
/// uses for the orderer's own location. Deliberately does not touch the
/// app-wide `locationProvider` ("my current location") or the orderer's own
/// saved-address book, since this is explicitly a different person's
/// address (see `MapLocationPickerScreen.updateGlobalLocation`).
class RecipientLocationSheet extends StatefulWidget {
  final String recipientLabel;

  const RecipientLocationSheet({super.key, required this.recipientLabel});

  static Future<PreciseAddress?> show(
    BuildContext context, {
    required String recipientLabel,
  }) {
    return showModalBottomSheet<PreciseAddress>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RecipientLocationSheet(recipientLabel: recipientLabel),
    );
  }

  @override
  State<RecipientLocationSheet> createState() => _RecipientLocationSheetState();
}

class _RecipientLocationSheetState extends State<RecipientLocationSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<PlacesSuggestion> _suggestions = [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    final query = q.trim();
    if (query.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      final results = await placesService.autocomplete(query);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _searching = false;
      });
    });
  }

  Future<void> _pickSuggestion(PlacesSuggestion s) async {
    final details = await placesService.details(s.placeId);
    if (!mounted || details == null) return;
    Navigator.pop(
      context,
      PreciseAddress(
        plotNo: details.plotNo,
        building: details.building,
        street: details.street,
        area: details.area,
        city: details.city,
        state: details.state,
        pincode: details.pincode,
        lat: details.lat,
        lng: details.lng,
      ),
    );
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.push<PreciseAddress>(
      context,
      MaterialPageRoute(
        builder: (_) => const MapLocationPickerScreen(updateGlobalLocation: false),
      ),
    );
    if (result != null && mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(children: [
                Expanded(
                  child: Text(
                    "${widget.recipientLabel}'s location",
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                ),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const Divider(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _onSearchChanged,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search for an address...',
                  hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.grey[400]),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF8F9FA),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: _pickOnMap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(children: [
                    Icon(Icons.map_rounded, color: AppColors.primary, size: 18),
                    SizedBox(width: 10),
                    Text(
                      'Pick on map',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.primary),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _suggestions.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.separated(
                      controller: ctrl,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[100]),
                      itemBuilder: (context, i) {
                        final s = _suggestions[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.location_on_outlined, color: Colors.grey),
                          title: Text(
                            s.mainText.isNotEmpty ? s.mainText : s.fullText,
                            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          subtitle: s.secondaryText.isNotEmpty
                              ? Text(s.secondaryText, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5))
                              : null,
                          onTap: () => _pickSuggestion(s),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
