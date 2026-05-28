import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../providers/zones_provider.dart';
import '../../../domain/models/zone.dart';
import '../../providers/filters_provider.dart';
import '../../providers/routing_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/time_selector_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/nav_math.dart';
import '../../../core/utils/navigation_deeplink.dart';
import '../../../core/utils/error_snackbar.dart';
import 'widgets/candidates_sheet.dart';
import 'widgets/navigation_overlay.dart' show NavigationTurnCard, NavigationBottomBar;
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
  Timer? _timeDebounce;
  Position? _userPosition;
  Point? _lastCameraTarget;
  double _currentAzimuth = 0;
  Uint8List? _destinationPinBytes;
  Uint8List? _userLocationBytes;
  Uint8List? _navArrowBytes;

  bool _isSelectingOnMap = false;
  bool _isCandidatesSheetOpen = false;
  bool _isRouteSheetOpen = false;
  bool _isParkingCardOpen = false;

  Map<int, Uint8List> _zoneLabelCache = {};
  Map<int, Zone> _zonesById = {};
  int _bitmapGeneration = 0;
  List<Point>? _routePolyline;
  int? _activeRouteZoneId;
  DrivingSession? _drivingSession;
  bool _navBuilding = false;

  @override
  void initState() {
    super.initState();
    _buildDestinationPinBitmap().then((b) {
      if (mounted) setState(() => _destinationPinBytes = b);
    });
    _buildUserLocationBitmap().then((b) {
      if (mounted) setState(() => _userLocationBytes = b);
    });
    _buildNavArrowBitmap().then((b) {
      if (mounted) setState(() => _navArrowBytes = b);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _timeDebounce?.cancel();
    _drivingSession?.close();
    super.dispose();
  }

  Future<Uint8List> _buildDestinationPinBitmap() async {
    const size = 48.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 2,
      Paint()..color = AppColors.primary,
    );
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 2,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _updateZoneBitmaps(List<Zone> zones) async {
    final same = zones.length == _zonesById.length &&
        zones.every((z) {
          final prev = _zonesById[z.zoneId];
          return prev != null &&
              prev.freeCount == z.freeCount &&
              prev.hasForecast == z.hasForecast &&
              prev.isActive == z.isActive;
        });
    if (same) return;
    final generation = ++_bitmapGeneration;
    final newCache = <int, Uint8List>{};
    final newById = <int, Zone>{};
    for (final zone in zones) {
      if (_bitmapGeneration != generation) return;
      if (zone.geometry.length < 3) continue;
      final color = zoneColor(zone);
      newCache[zone.zoneId] = await buildCountBitmap(
        color == AppColors.parkingUnknown ? null : zone.freeCount,
        color,
      );
      newById[zone.zoneId] = zone;
    }
    if (_bitmapGeneration != generation) return;
    if (mounted) {
      setState(() {
        _zoneLabelCache = newCache;
        _zonesById = newById;
      });
    }
  }

  Future<Uint8List> _buildUserLocationBitmap() async {
    const size = 48.0;
    const center = Offset(size / 2, size / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(center, size / 2 - 1, Paint()..color = Colors.white);
    canvas.drawCircle(center, size / 2 - 5, Paint()..color = const Color(0xFF007AFF));
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _buildNavArrowBitmap() async {
    const size = 80.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Drop shadow
    canvas.drawPath(
      Path()
        ..moveTo(size / 2, 4)
        ..lineTo(size * 0.78, size * 0.72)
        ..lineTo(size / 2, size * 0.56)
        ..lineTo(size * 0.22, size * 0.72)
        ..close(),
      Paint()
        ..color = const Color(0x44000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
    );

    // Arrow fill
    final arrowPath = Path()
      ..moveTo(size / 2, 4)
      ..lineTo(size * 0.78, size * 0.72)
      ..lineTo(size / 2, size * 0.56)
      ..lineTo(size * 0.22, size * 0.72)
      ..close();
    canvas.drawPath(arrowPath, Paint()..color = AppColors.primary);

    // White outline for contrast
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = Colors.white
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = ui.StrokeJoin.round,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _onCameraPositionChanged(CameraPosition position, _, __) {
    _lastCameraTarget = position.target;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _fetchZones);
    if ((position.azimuth - _currentAzimuth).abs() > 0.5) {
      setState(() => _currentAzimuth = position.azimuth);
    }
  }

  Future<void> _fetchZones({bool clearCache = false}) async {
    if (_mapController == null) return;
    if (clearCache) {
      _zoneLabelCache.clear();
      _zonesById.clear();
    }
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
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null) {
        _userPosition = cached;
        return cached;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 5),
        ),
      );
      _userPosition = pos;
      return pos;
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось быстро получить геопозицию')),
        );
      }
      return null;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось получить геопозицию')),
        );
      }
      return null;
    }
  }

  Future<void> _goToMyLocation() async {
    final pos = await _getCurrentPosition();
    if (pos == null) return;
    if (mounted) setState(() {});
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

  Future<void> _resetNorth() async {
    if (_mapController == null) return;
    final pos = await _mapController!.getCameraPosition();
    await _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: pos.target,
          zoom: pos.zoom,
          azimuth: 0,
          tilt: 0,
        ),
      ),
      animation: const MapAnimation(duration: 0.4),
    );
  }

  Future<void> _zoomIn() async {
    if (_mapController == null) return;
    final pos = await _mapController!.getCameraPosition();
    await _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: pos.target,
          zoom: pos.zoom + 1,
          azimuth: pos.azimuth,
          tilt: pos.tilt,
        ),
      ),
      animation: const MapAnimation(duration: 0.2),
    );
  }

  Future<void> _zoomOut() async {
    if (_mapController == null) return;
    final pos = await _mapController!.getCameraPosition();
    await _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: pos.target,
          zoom: pos.zoom - 1,
          azimuth: pos.azimuth,
          tilt: pos.tilt,
        ),
      ),
      animation: const MapAnimation(duration: 0.2),
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

  Future<void> _startInAppNavigation({
    required int zoneId,
    required double toLat,
    required double toLon,
  }) async {
    if (!mounted) return;
    setState(() => _navBuilding = true);
    try {
      final pos = await _getCurrentPosition();
      if (pos == null) return;

      await _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(CameraPosition(
          target: Point(latitude: pos.latitude, longitude: pos.longitude),
          zoom: 17,
          tilt: 40,
        )),
        animation: const MapAnimation(duration: 0.8),
      );

      List<Point> route;
      double totalSeconds = 0;
      double totalMeters = 0;

      if (_routePolyline != null && _routePolyline!.length >= 2) {
        route = _routePolyline!;
      } else {
        await _drivingSession?.close();
        final rws = YandexDriving.requestRoutes(
          points: [
            RequestPoint(
              point: Point(latitude: pos.latitude, longitude: pos.longitude),
              requestPointType: RequestPointType.wayPoint,
            ),
            RequestPoint(
              point: Point(latitude: toLat, longitude: toLon),
              requestPointType: RequestPointType.wayPoint,
            ),
          ],
          drivingOptions: const DrivingOptions(routesCount: 1),
        );
        _drivingSession = rws.session;
        final result = await rws.result;
        await rws.session.close();
        _drivingSession = null;
        final dr = result.routes?.firstOrNull;
        if (dr == null || !mounted) return;
        route = dr.geometry;
        totalSeconds = dr.metadata.weight.timeWithTraffic.value ?? 0;
        totalMeters = dr.metadata.weight.distance.value ?? 0;
        setState(() => _routePolyline = route);
      }

      if (totalMeters == 0 && route.length >= 2) {
        for (int i = 0; i < route.length - 1; i++) {
          totalMeters += navDistanceM(route[i], route[i + 1]);
        }
        totalSeconds = totalMeters / 10;
      }

      await ref.read(navigationProvider.notifier).startNavigation(
            zoneId: zoneId,
            route: route,
            totalSeconds: totalSeconds,
            totalMeters: totalMeters,
            destLat: toLat,
            destLon: toLon,
          );

      await _mapController?.toggleUserLayer(visible: false);
      await _mapController?.toggleTrafficLayer(visible: true);
    } catch (e, st) {
      if (mounted) {
        showErrorSnackBar(context, 'Не удалось построить маршрут', error: e, stackTrace: st);
      }
    } finally {
      if (mounted) setState(() => _navBuilding = false);
    }
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
    const bottomInset = 0.0;
    final zones = ref.watch(filteredZonesProvider);
    final zonesAsync = ref.watch(rawZonesProvider);
    final routingState = ref.watch(routingProvider);
    final destination = ref.watch(destinationProvider);
    final navState = ref.watch(navigationProvider);
    final isNavigating = navState != null;
    final isRoutingLoading = routingState.maybeWhen(
      searching: () => true,
      orElse: () => false,
    );

    ref.listen(timeSelectorProvider, (_, __) {
      _timeDebounce?.cancel();
      _timeDebounce = Timer(const Duration(milliseconds: 600), () => _fetchZones(clearCache: true));
    });
    ref.listen(filteredZonesProvider, (_, zones) => _updateZoneBitmaps(zones));

    ref.listen(navigationProvider, (prev, nav) {
      if (nav == null) return;
      if (prev?.route != nav.route) {
        setState(() => _routePolyline = nav.route);
      }
      _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(CameraPosition(
          target: nav.currentPosition,
          zoom: 17,
          azimuth: nav.heading,
          tilt: 40,
        )),
        animation: const MapAnimation(duration: 0.6),
      );
    });

    ref.listen(rawZonesProvider, (_, next) {
      next.whenOrNull(
        error: (e, st) {
          showErrorSnackBar(context, 'Не удалось загрузить парковки', error: e, stackTrace: st);
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
        idle: () async {
          ref.read(navigationProvider.notifier).stop();
          await _mapController?.toggleUserLayer(visible: false);
          await _mapController?.toggleTrafficLayer(visible: false);
          setState(() {
            _routePolyline = null;
            _activeRouteZoneId = null;
          });
        },
        searching: () async {},
        error: (message) async {
          showErrorSnackBar(context, 'Ошибка при построении маршрута', error: message);
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

          final matches = zones.where((z) => z.zoneId == route.selectedZoneId);
          double? zoneLat, zoneLon;
          if (matches.isNotEmpty) {
            final zone = matches.first;
            if (zone.geometry.length >= 3) {
              final c = centroid(zone.geometry);
              zoneLat = c.latitude;
              zoneLon = c.longitude;
              await _mapController?.moveCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(target: c, zoom: 17),
                ),
                animation: const MapAnimation(duration: 0.8),
              );
            }
          }

          setState(() {
            _routePolyline = route.candidates.firstOrNull?.routePolyline;
            _activeRouteZoneId = route.selectedZoneId;
          });

          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => RoutePreviewSheet(
              route: route,
              zoneLat: zoneLat,
              zoneLon: zoneLon,
              onNavigateInApp: (zoneLat != null && zoneLon != null)
                  ? () => _startInAppNavigation(
                        zoneId: route.selectedZoneId,
                        toLat: zoneLat!,
                        toLon: zoneLon!,
                      )
                  : null,
            ),
          );
          _isRouteSheetOpen = false;
        },
      );
    });

    final candidateIds = routingState.maybeWhen(
      candidates: (c) => c.map((e) => e.zoneId).toSet(),
      orElse: () => <int>{},
    );

    final zoneObjects = buildZoneMapObjects(
      zones: zones,
      highlightedIds: candidateIds,
      onTap: (zone) {
        if (_isSelectingOnMap && candidateIds.contains(zone.zoneId)) {
          _buildRouteForZone(zone.zoneId);
          return;
        }
        if (_isParkingCardOpen) return;
        setState(() => _isParkingCardOpen = true);
        showParkingCard(
          context,
          zone,
          onBuildRoute: () => _buildRouteForZone(zone.zoneId),
        ).then((_) {
          if (mounted) setState(() => _isParkingCardOpen = false);
        });
      },
    );

    final mapObjects = <MapObject>[
      ...zoneObjects,
      if (_routePolyline != null && _routePolyline!.length >= 2)
        PolylineMapObject(
          mapId: const MapObjectId('route_polyline'),
          polyline: Polyline(points: _routePolyline!),
          strokeColor: Colors.blue,
          strokeWidth: 5,
        ),
      if (_activeRouteZoneId != null)
        ...buildHighlightZone(zones, _activeRouteZoneId!),
      if (_zoneLabelCache.isNotEmpty)
        buildZoneLabels(
          zones: zones,
          bitmapCache: _zoneLabelCache,
          zonesById: _zonesById,
          onZoneTap: (zone) {
            if (_isSelectingOnMap && candidateIds.contains(zone.zoneId)) {
              _buildRouteForZone(zone.zoneId);
              return;
            }
            if (_isParkingCardOpen) return;
            setState(() => _isParkingCardOpen = true);
            showParkingCard(
              context,
              zone,
              onBuildRoute: () => _buildRouteForZone(zone.zoneId),
            ).then((_) {
              if (mounted) setState(() => _isParkingCardOpen = false);
            });
          },
          onClusterTap: (_, cluster) {
            if (cluster.placemarks.isEmpty) return;
            final lats = cluster.placemarks.map((p) => p.point.latitude);
            final lons = cluster.placemarks.map((p) => p.point.longitude);
            final latMin = lats.reduce(math.min);
            final latMax = lats.reduce(math.max);
            final lonMin = lons.reduce(math.min);
            final lonMax = lons.reduce(math.max);
            final latPad = (latMax - latMin) * 0.6 + 0.003;
            final lonPad = (lonMax - lonMin) * 0.6 + 0.003;
            _mapController?.moveCamera(
              CameraUpdate.newGeometry(Geometry.fromBoundingBox(BoundingBox(
                southWest: Point(
                  latitude: latMin - latPad,
                  longitude: lonMin - lonPad,
                ),
                northEast: Point(
                  latitude: latMax + latPad,
                  longitude: lonMax + lonPad,
                ),
              ))),
              animation: const MapAnimation(duration: 0.5),
            );
          },
        ),
      if (_userPosition != null && _userLocationBytes != null && !isNavigating)
        PlacemarkMapObject(
          mapId: const MapObjectId('user_location'),
          point: Point(
            latitude: _userPosition!.latitude,
            longitude: _userPosition!.longitude,
          ),
          icon: PlacemarkIcon.single(PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(_userLocationBytes!),
            scale: 1.0,
          )),
        ),
      if (isNavigating && _navArrowBytes != null)
        PlacemarkMapObject(
          mapId: const MapObjectId('nav_arrow'),
          point: navState!.currentPosition,
          opacity: 1.0,
          icon: PlacemarkIcon.single(PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(_navArrowBytes!),
            scale: 1.0,
          )),
        ),
      if (destination != null && _destinationPinBytes != null)
        PlacemarkMapObject(
          mapId: const MapObjectId('destination_pin'),
          point: Point(
            latitude: destination.latitude,
            longitude: destination.longitude,
          ),
          icon: PlacemarkIcon.single(PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(_destinationPinBytes!),
            scale: 1.0,
          )),
        ),
    ];

    return Scaffold(
      body: SafeArea(child: Stack(
        children: [
          YandexMap(
            mapObjects: mapObjects,
            onMapCreated: (controller) async {
              _mapController = controller;
              const fallback = Point(latitude: 59.7390, longitude: 30.4020);
              _lastCameraTarget = fallback;
              await controller.moveCamera(
                CameraUpdate.newCameraPosition(
                  const CameraPosition(target: fallback, zoom: 14),
                ),
              );
              _fetchZones();
              final pos = await _getCurrentPosition();
              if (pos != null && mounted) {
                final target = Point(latitude: pos.latitude, longitude: pos.longitude);
                _lastCameraTarget = target;
                await controller.moveCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(target: target, zoom: 15),
                  ),
                  animation: const MapAnimation(duration: 0.8),
                );
                _fetchZones();
              }
            },
            onCameraPositionChanged: _onCameraPositionChanged,
          ),
          // ─── Top bar ───────────────────────────────────────────────
          if (!isNavigating)
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
                            const Icon(Icons.search,
                                color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                destination?.name ?? 'Найти место назначения',
                                style: const TextStyle(
                                    color: AppColors.textSecondary),
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
                  _MapButton(
                      icon: Icons.tune,
                      onTap: () => _showFilters(context)),
                  const SizedBox(width: 4),
                  _MapButton(
                      icon: Icons.person_outlined,
                      onTap: () => context.push('/profile')),
                ],
              ),
            ),
          ),
          // ─── Нижняя строка: FAB слева + кнопки справа ─────────────
          if (destination == null && !isNavigating)
            Positioned(
              bottom: bottomInset + 12,
              left: 12,
              child: FloatingActionButton.extended(
                heroTag: 'find_parking',
                onPressed: isRoutingLoading ? null : _findParking,
                backgroundColor: AppColors.primary,
                icon: const Icon(Icons.local_parking, color: Colors.white),
                label: Text(
                  isRoutingLoading ? 'Ищем...' : 'Где припарковаться?',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MapButton(
                    onTap: _resetNorth,
                    child: Transform.rotate(
                      angle: -_currentAzimuth * math.pi / 180,
                      child: const Icon(Icons.explore,
                          size: 22, color: Color(0xFF424242)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _MapButton(icon: Icons.add, onTap: _zoomIn),
                  const SizedBox(height: 4),
                  _MapButton(icon: Icons.remove, onTap: _zoomOut),
                  const SizedBox(height: 4),
                  _MapButton(icon: Icons.my_location, onTap: _goToMyLocation),
                ],
              ),
            ),
          ),
          // ─── Таймлайн: полная ширина, своя строка выше кнопок ──────
          if (destination == null && !isNavigating)
            Positioned(
              bottom: bottomInset + 76,
              left: 0,
              right: 0,
              child: const TimeSelectorWidget(),
            ),
          // ─── Карточка назначения ────────────────────────────────────
          if (destination != null && !isNavigating)
            Positioned(
              bottom: bottomInset + 76,
              left: 12,
              right: 12,
              child: _DestinationCard(
                destination: destination,
                onFindParking: isRoutingLoading ? null : _findParking,
                onNavigate: () => openYandexNavigator(
                    destination.latitude, destination.longitude),
                onNavigateInApp: () => _startInAppNavigation(
                    zoneId: 0,
                    toLat: destination.latitude,
                    toLon: destination.longitude),
                onClear: () {
                  ref.read(destinationProvider.notifier).state = null;
                  ref.read(routingProvider.notifier).reset();
                },
              ),
            ),
          // ─── Loading indicators ─────────────────────────────────────
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
          if (isNavigating)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: NavigationTurnCard(),
            ),
          if (isNavigating)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: NavigationBottomBar(
                onFinish: () {
                  ref.read(navigationProvider.notifier).stop();
                  ref.read(routingProvider.notifier).reset();
                },
              ),
            ),
          if (_navBuilding)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x55000000),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Строим маршрут...'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (isRoutingLoading)
            Positioned(
              top: 148,
              left: 0,
              right: 0,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Поиск маршрута...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      )),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.destination,
    required this.onFindParking,
    required this.onNavigate,
    required this.onNavigateInApp,
    required this.onClear,
  });

  final Destination destination;
  final VoidCallback? onFindParking;
  final VoidCallback onNavigate;
  final VoidCallback onNavigateInApp;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.place, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  destination.name ?? 'Выбранное место',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              GestureDetector(
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.close,
                      size: 18, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onFindParking,
            icon: const Icon(Icons.local_parking, size: 16),
            label: const Text('Искать парковку рядом'),
            style: FilledButton.styleFrom(
              textStyle: const TextStyle(fontSize: 13),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onNavigateInApp,
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text('В приложении'),
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 13),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: onNavigate,
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 13),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('Яндекс'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  const _MapButton({this.icon, required this.onTap, this.child});

  final IconData? icon;
  final VoidCallback onTap;
  final Widget? child;

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
        child: child ??
            Icon(icon!, size: 22, color: const Color(0xFF424242)),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────

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
          color: Color(0xFFE8F5E9),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.of(context).padding.bottom + 24),
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
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                    onPressed: notifier.reset,
                    child: const Text('Сбросить')),
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
              title: const Text('Скрыть места для инвалидов'),
              value: filters.hideInaccessible,
              onChanged: (_) => notifier.toggleHideInaccessible(),
            ),
            SwitchListTile(
              title: const Text('Скрыть закрытые'),
              value: filters.hideInactive,
              onChanged: (_) => notifier.toggleHideInactive(),
            ),
            const Divider(),
            const Text(
              'Минимальная уверенность',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '${(filters.minConfidence * 100).round()}%',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$payValue ₽/ч',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Slider(
                    value: payValue.toDouble(),
                    min: 0,
                    max: 500,
                    divisions: 20,
                    label: '$payValue ₽/ч',
                    onChanged: (value) =>
                        notifier.setMaxPay(value.round()),
                  ),
                ],
              ),
            const Divider(),
            const Text(
              'Минимум свободных мест',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              filters.minFreeCount == 0 ? 'Любое' : '${filters.minFreeCount}+',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            Slider(
              value: filters.minFreeCount.toDouble(),
              min: 0,
              max: 20,
              divisions: 20,
              label: filters.minFreeCount == 0 ? 'Любое' : '${filters.minFreeCount}+',
              onChanged: (v) => notifier.setMinFreeCount(v.round()),
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
                onChanged: (_) =>
                    notifier.toggleLocationType(entry.key),
                dense: true,
              ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.pop(context),
              child: const Text('Применить', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

