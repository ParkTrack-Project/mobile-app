import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../providers/zones_provider.dart';
import '../../providers/filters_provider.dart';
import '../../providers/routing_provider.dart';
import '../../providers/time_selector_provider.dart';
import 'widgets/parking_zone_layer.dart';
import 'widgets/time_selector_widget.dart';
import 'widgets/parking_card_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  YandexMapController? _mapController;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onCameraPositionChanged(CameraPosition position, _, __) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _fetchZones();
    });
  }

  Future<void> _fetchZones() async {
    if (_mapController == null) return;
    final visibleRegion = await _mapController!.getVisibleRegion();
    final bbox =
        '${visibleRegion.bottomLeft.longitude},${visibleRegion.bottomLeft.latitude},'
        '${visibleRegion.topRight.longitude},${visibleRegion.topRight.latitude}';
    ref.read(rawZonesProvider.notifier).fetchZones(bbox);
  }

  Future<void> _goToMyLocation() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final result = await Geolocator.requestPermission();
      if (result == LocationPermission.denied ||
          result == LocationPermission.deniedForever) {
        _showLocationDeniedDialog();
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _showLocationDeniedDialog();
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition();
      await _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: Point(latitude: pos.latitude, longitude: pos.longitude),
            zoom: 16,
          ),
        ),
        animation: const MapAnimation(duration: 0.8),
      );
    } catch (_) {}
  }

  void _showLocationDeniedDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Нет доступа к геолокации'),
        content: const Text(
            'Для поиска парковок рядом с вами необходим доступ к местоположению.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openAppSettings();
            },
            child: const Text('Настройки'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(filteredZonesProvider);
    final zonesAsync = ref.watch(rawZonesProvider);

    ref.listen(timeSelectorProvider, (_, __) => _fetchZones());

    final mapObjects = buildZoneMapObjects(
      zones: zones,
      onTap: (zone) => showParkingCard(context, ref, zone),
    );

    return Scaffold(
      body: Stack(
        children: [
          YandexMap(
            mapObjects: mapObjects,
            onMapCreated: (controller) {
              _mapController = controller;
              _fetchZones();
            },
            onCameraPositionChanged: _onCameraPositionChanged,
          ),
          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => context.push('/search'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8),
                          ],
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.search, color: Color(0xFF757575)),
                            SizedBox(width: 8),
                            Text('Найти место назначения',
                                style: TextStyle(color: Color(0xFF757575))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MapButton(
                    icon: Icons.tune,
                    onTap: () => _showFilters(context),
                  ),
                  const SizedBox(width: 4),
                  _MapButton(
                    icon: Icons.person_outlined,
                    onTap: () => context.push('/profile'),
                  ),
                ],
              ),
            ),
          ),
          // Time selector
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Center(child: const TimeSelectorWidget()),
          ),
          // My location + find parking buttons
          Positioned(
            bottom: 24,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'my_location',
                  onPressed: _goToMyLocation,
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF2E7D32),
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
          // Find parking FAB
          Positioned(
            bottom: 24,
            left: 16,
            child: FloatingActionButton.extended(
              heroTag: 'find_parking',
              onPressed: () => _findParking(),
              backgroundColor: const Color(0xFF2E7D32),
              icon: const Icon(Icons.local_parking, color: Colors.white),
              label: const Text('Где припарковаться?',
                  style: TextStyle(color: Colors.white)),
            ),
          ),
          // Loading overlay
          if (zonesAsync is AsyncLoading)
            const Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _findParking() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final result = await Geolocator.requestPermission();
      if (result != LocationPermission.whileInUse &&
          result != LocationPermission.always) {
        _showLocationDeniedDialog();
        return;
      }
    }
    try {
      final pos = await Geolocator.getCurrentPosition();
      await ref.read(routingProvider.notifier).searchParking(
            originLat: pos.latitude,
            originLon: pos.longitude,
          );
    } catch (_) {}
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FiltersSheet(),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8),
          ],
        ),
        child: Icon(icon, size: 22, color: const Color(0xFF424242)),
      ),
    );
  }
}

class _FiltersSheet extends ConsumerWidget {
  const _FiltersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(filtersProvider);
    final notifier = ref.read(filtersProvider.notifier);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                    child: Text('Фильтры',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold))),
                TextButton(
                    onPressed: notifier.reset, child: const Text('Сбросить')),
              ],
            ),
            SwitchListTile(
              title: const Text('Скрыть занятые'),
              value: filters.hideNoFreeSpots,
              onChanged: (_) => notifier.toggleHideNoFreeSpots(),
            ),
            SwitchListTile(
              title: const Text('Скрыть частные'),
              value: filters.hidePrivate,
              onChanged: (_) => notifier.toggleHidePrivate(),
            ),
            SwitchListTile(
              title: const Text('Скрыть неактивные'),
              value: filters.hideInactive,
              onChanged: (_) => notifier.toggleHideInactive(),
            ),
            const Divider(),
            const Text('Тип парковки',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final entry in {
              'street': 'Уличная',
              'yard': 'Дворовая',
              'open_lot': 'Открытая стоянка',
              'underground': 'Подземная',
              'multilevel': 'Многоуровневая',
            }.entries)
              CheckboxListTile(
                title: Text(entry.value),
                value: !filters.hiddenLocationTypes.contains(entry.key),
                onChanged: (_) => notifier.toggleLocationType(entry.key),
                dense: true,
              ),
          ],
        ),
      ),
    );
  }
}
