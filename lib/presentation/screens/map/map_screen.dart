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
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/navigation_deeplink.dart';
import 'widgets/candidates_sheet.dart';
import 'widgets/parking_zone_layer.dart';
import 'widgets/time_selector_widget.dart';
import 'widgets/parking_card_sheet.dart';
import 'widgets/route_preview_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  YandexMapController? _mapController;
  Timer? _debounce;
  Position? _userPosition;
  Point? _lastCameraTarget;

  bool _isSelectingOnMap = false;
  bool _isCandidatesSheetOpen = false;
  bool _isRouteSheetOpen = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onCameraPositionChanged(CameraPosition position, _, __) {
    _lastCameraTarget = position.target;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _fetchZones);
  }

  Future<void> _fetchZones() async {
    if (_mapController == null) return;
    try {
      final visibleRegion = await _mapController!.getVisibleRegion();
      final bbox =
          '${visibleRegion.bottomLeft.longitude},${visibleRegion.bottomLeft.latitude},'
          '${visibleRegion.topRight.longitude},${visibleRegion.topRight.latitude}';
      await ref.read(rawZonesProvider.notifier).fetchZones(bbox);
    } catch (e, st) {
      ref.read(rawZonesProvider.notifier).setErrorState(e, st);
    }
  }

  Future<Position?> _getCurrentPosition() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      _showLocationDeniedDialog();
      return null;
    }
    try {
      final pos = await Geolocator.getCurrentPosition();
      _userPosition = pos;
      return pos;
    } catch (_) {
      return null;
    }
  }

  Future<void> _goToMyLocation() async {
    final pos = await _getCurrentPosition();
    if (pos == null) return;
    await _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: Point(latitude: pos.latitude, longitude: pos.longitude),
          zoom: 16,
        ),
      ),
      animation: const MapAnimation(duration: 0.8),
    );
  }

  void _showLocationDeniedDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Нет доступа к геолокации'),
        content: const Text(
          'Для поиска парковок рядом с вами необходим доступ к местоположению.',
        ),
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

  Future<void> _openSearch() async {
    final bias = _userPosition != null
        ? SearchBias(
            latitude: _userPosition!.latitude,
            longitude: _userPosition!.longitude,
          )
        : _lastCameraTarget != null
            ? SearchBias(
                latitude: _lastCameraTarget!.latitude,
                longitude: _lastCameraTarget!.longitude,
              )
            : null;
    ref.read(searchBiasProvider.notifier).state = bias;
    await context.push('/search');

    if (!mounted) return;
    final destination = ref.read(destinationProvider);
    final mode = ref.read(destinationModeProvider);
    if (destination == null) return;

    if (mode == DestinationMode.routeToAddress) {
      await openYandexNavigator(destination.latitude, destination.longitude);
      return;
    }
    await _findParking();
  }

  Future<void> _findParking() async {
    final pos = await _getCurrentPosition();
    if (pos == null) return;
    await ref.read(routingProvider.notifier).searchParking(
          originLat: pos.latitude,
          originLon: pos.longitude,
        );
  }

  Future<void> _buildRouteForZone(int zoneId) async {
    final pos = await _getCurrentPosition();
    if (pos == null) return;
    setState(() => _isSelectingOnMap = false);
    await ref.read(routingProvider.notifier).buildRoute(
          originLat: pos.latitude,
          originLon: pos.longitude,
          selectedZoneId: zoneId,
        );
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FiltersSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(filteredZonesProvider);
    final zonesAsync = ref.watch(rawZonesProvider);
    final routingState = ref.watch(routingProvider);
    final destination = ref.watch(destinationProvider);

    ref.listen(timeSelectorProvider, (_, __) => _fetchZones());

    ref.listen(rawZonesProvider, (_, next) {
      next.whenOrNull(
        error: (e, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка загрузки зон: $e')),
          );
        },
      );
    });

    ref.listen(destinationProvider, (_, dest) {
      if (dest == null) return;
      _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: Point(latitude: dest.latitude, longitude: dest.longitude),
            zoom: 15,
          ),
        ),
        animation: const MapAnimation(duration: 0.8),
      );
    });

    ref.listen(routingProvider, (_, next) async {
      await next.when(
        idle: () async {},
        searching: () async {},
        error: (message) async {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка маршрута: $message')),
          );
        },
        candidates: (candidates) async {
          if (_isCandidatesSheetOpen || candidates.isEmpty) return;
          _isCandidatesSheetOpen = true;
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => CandidatesSheet(
              candidates: candidates,
              onSelectByList: (zoneId) {
                Navigator.pop(context);
                _buildRouteForZone(zoneId);
              },
              onSelectOnMap: () {
                Navigator.pop(context);
                setState(() => _isSelectingOnMap = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Выберите парковочную зону на карте'),
                  ),
                );
              },
            ),
          );
          _isCandidatesSheetOpen = false;
        },
        routePreview: (route) async {
          if (_isRouteSheetOpen) return;
          _isRouteSheetOpen = true;
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => RoutePreviewSheet(route: route),
          );
          _isRouteSheetOpen = false;
        },
      );
    });

    final candidateIds = routingState.maybeWhen(
      candidates: (c) => c.map((e) => e.zoneId).toSet(),
      orElse: () => <int>{},
    );

    final mapObjects = buildZoneMapObjects(
      zones: zones,
      onTap: (zone) {
        if (_isSelectingOnMap && candidateIds.contains(zone.zoneId)) {
          _buildRouteForZone(zone.zoneId);
          return;
        }
        showParkingCard(context, ref, zone);
      },
    );

    return Scaffold(
      body: Stack(
        children: [
          YandexMap(
            mapObjects: mapObjects,
            onMapCreated: (controller) async {
              _mapController = controller;
              const initial = Point(latitude: 55.7558, longitude: 37.6173);
              _lastCameraTarget = initial;
              await controller.moveCamera(
                CameraUpdate.newCameraPosition(
                  const CameraPosition(target: initial, zoom: 13),
                ),
              );
              _fetchZones();
            },
            onCameraPositionChanged: _onCameraPositionChanged,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _openSearch,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                destination?.name ?? 'Найти место назначения',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MapButton(icon: Icons.tune, onTap: () => _showFilters(context)),
                  const SizedBox(width: 4),
                  _MapButton(icon: Icons.person_outlined, onTap: () => context.push('/profile')),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 108,
            left: 0,
            right: 0,
            child: Center(
              child: const TimeSelectorWidget(),
            ),
          ),
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
                  foregroundColor: AppColors.primary,
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 24,
            left: 16,
            child: FloatingActionButton.extended(
              heroTag: 'find_parking',
              onPressed: _findParking,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.local_parking, color: Colors.white),
              label: Text(
                destination == null ? 'Где припарковаться?' : 'Парковка рядом',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
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
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

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
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
            ),
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
    final hasPayLimit = filters.maxPayPerHour != null;
    final payValue = (filters.maxPayPerHour ?? 200).clamp(0, 500);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
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
                  child: Text(
                    'Фильтры',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(onPressed: notifier.reset, child: const Text('Сбросить')),
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
              title: const Text('Скрыть недоступные'),
              value: filters.hideInaccessible,
              onChanged: (_) => notifier.toggleHideInaccessible(),
            ),
            SwitchListTile(
              title: const Text('Скрыть неактивные'),
              value: filters.hideInactive,
              onChanged: (_) => notifier.toggleHideInactive(),
            ),
            const Divider(),
            const Text(
              'Минимальная уверенность',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            Slider(
              value: filters.minConfidence,
              min: 0,
              max: 1,
              divisions: 20,
              label: '${(filters.minConfidence * 100).round()}%',
              onChanged: notifier.setMinConfidence,
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Ограничить стоимость'),
              value: hasPayLimit,
              onChanged: (value) {
                notifier.setMaxPay(value ? 200 : null);
              },
            ),
            if (hasPayLimit)
              Slider(
                value: payValue.toDouble(),
                min: 0,
                max: 500,
                divisions: 20,
                label: '$payValue ₽/ч',
                onChanged: (value) => notifier.setMaxPay(value.round()),
              ),
            const Divider(),
            const Text(
              'Тип парковки',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
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
