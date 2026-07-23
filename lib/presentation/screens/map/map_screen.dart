import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../providers/zones_provider.dart';
import '../../../domain/models/route_result.dart';
import '../../../domain/models/zone.dart';
import '../../providers/filters_provider.dart';
import '../../providers/app_providers.dart';
import '../../providers/parking_search_provider.dart';
import '../../providers/routing_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/time_selector_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/navigation_deeplink.dart';
import '../../../core/utils/error_snackbar.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/services/yandex_web_route.dart';
import 'widgets/candidates_sheet.dart';
import 'widgets/navigation_overlay.dart'
    show NavigationTurnCard, NavigationBottomBar;
import 'widgets/parking_zone_layer.dart';
import 'widgets/time_selector_widget.dart';
import 'widgets/web_map_view.dart';
import 'widgets/web_map_types.dart';
import 'widgets/parking_card_sheet.dart';
import 'widgets/route_preview_sheet.dart';
import 'widgets/pwa_install_guide.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.initialParkingId, this.searchQuery});

  final int? initialParkingId;
  final String? searchQuery;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  YandexMapController? _mapController;
  final WebMapController _webMapController = WebMapController();
  bool _webMapReady = false;
  Timer? _debounce;
  Timer? _timeDebounce;
  Position? _userPosition;
  Point? _lastCameraTarget;
  double _currentAzimuth = 0;
  Uint8List? _destinationPinBytes;
  Uint8List? _userLocationBytes;
  Uint8List? _navArrowBytes;

  bool _isRouteSheetOpen = false;
  bool _isParkingCardOpen = false;
  bool _parkingDetailsLoading = false;

  Map<int, Uint8List> _zoneLabelCache = {};
  Map<int, Zone> _zonesById = {};
  final Map<({int? count, int color}), Uint8List> _zoneBitmapCache = {};
  Map<int, ({int? count, int color})> _zoneStylesById = {};
  int _bitmapGeneration = 0;
  List<Point>? _routePolyline;
  double _routeDurationSeconds = 0;
  int? _activeRouteZoneId;
  DrivingSession? _drivingSession;
  bool _navBuilding = false;

  List<Zone>? _cachedMapZones;
  Set<int> _cachedCandidateIds = const {};
  int? _cachedSelectedZoneId;
  List<MapObject> _cachedZoneObjects = const [];
  Map<int, Uint8List>? _cachedLabelBitmaps;
  MapObject? _cachedZoneLabels;
  Set<int> _candidateIds = const {};

  @override
  void initState() {
    super.initState();
    _loadMarkerBitmaps();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialParkingId != null) {
        _loadAndShowParking(widget.initialParkingId!);
      } else if (widget.searchQuery != null) {
        _performSearch(widget.searchQuery!);
      }
    });
  }

  Future<void> _loadMarkerBitmaps() async {
    final bitmaps = await Future.wait<Uint8List>([
      _buildDestinationPinBitmap(),
      _buildUserLocationBitmap(),
      _buildNavArrowBitmap(),
    ]);
    if (!mounted) return;
    setState(() {
      _destinationPinBytes = bitmaps[0];
      _userLocationBytes = bitmaps[1];
      _navArrowBytes = bitmaps[2];
    });
  }

  Future<void> _loadAndShowParking(int id) async {
    try {
      final repo = ref.read(zonesRepositoryProvider);
      final zone = await repo.getZoneDetails(id);
      if (!mounted) return;
      _onZoneTap(zone);
      final center = centroid(zone.geometry);
      if (kIsWeb) {
        _webMapController.move(center.latitude, center.longitude, 17);
      } else {
        _mapController?.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: center, zoom: 17),
          ),
          animation: const MapAnimation(duration: 0.8),
        );
      }
    } catch (e) {
      debugPrint('Failed to load deep-link zone $id: $e');
    }
  }

  void _performSearch(String query) {
    context.push('/search?q=${Uri.encodeComponent(query)}');
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
    final styles = <int, ({int? count, int color})>{};
    for (final zone in zones) {
      final color = zoneColor(zone);
      styles[zone.zoneId] = (
        count: color == AppColors.parkingUnknown ? null : zone.freeCount,
        color: color.toARGB32(),
      );
    }
    final same =
        styles.length == _zoneStylesById.length &&
        styles.entries.every(
          (entry) => _zoneStylesById[entry.key] == entry.value,
        );
    if (same) return;
    final generation = ++_bitmapGeneration;
    final newCache = <int, Uint8List>{};
    final newById = <int, Zone>{};
    final usedStyles = <({int? count, int color})>{};
    for (final zone in zones) {
      if (_bitmapGeneration != generation) return;
      if (zone.geometry.length < 3) continue;
      final style = styles[zone.zoneId]!;
      usedStyles.add(style);
      var bitmap = _zoneBitmapCache[style];
      if (bitmap == null) {
        bitmap = await buildCountBitmap(style.count, Color(style.color));
        if (_bitmapGeneration != generation) return;
        _zoneBitmapCache[style] = bitmap;
      }
      newCache[zone.zoneId] = bitmap;
      newById[zone.zoneId] = zone;
    }
    if (_bitmapGeneration != generation) return;
    if (mounted) {
      setState(() {
        _zoneLabelCache = newCache;
        _zonesById = newById;
        _zoneStylesById = styles;
        _zoneBitmapCache.removeWhere((key, _) => !usedStyles.contains(key));
      });
    }
  }

  Future<Uint8List> _buildUserLocationBitmap() async {
    const size = 48.0;
    const center = Offset(size / 2, size / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(center, size / 2 - 1, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      size / 2 - 5,
      Paint()..color = const Color(0xFF007AFF),
    );
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

  void _onCameraPositionChanged(
    CameraPosition position,
    _,
    bool cameraUpdateFinished,
  ) {
    _lastCameraTarget = position.target;
    if ((position.azimuth - _currentAzimuth).abs() > 2) {
      setState(() => _currentAzimuth = position.azimuth);
    }
    if (!cameraUpdateFinished) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _fetchZones);
  }

  void _onZoneTap(Zone zone) {
    if (_candidateIds.contains(zone.zoneId)) {
      _openCandidateDetails(zone);
      return;
    }
    _openParkingDetails(zone);
  }

  Future<void> _openParkingDetails(Zone zone) async {
    if (_isParkingCardOpen) return;
    setState(() => _isParkingCardOpen = true);
    final result = await showParkingCard(context, zone);
    if (!mounted) return;
    setState(() => _isParkingCardOpen = false);
    if (result == ParkingCardResult.buildRoute) {
      await _buildRouteForZone(zone.zoneId);
    }
  }

  Future<void> _openCandidateById(int zoneId) async {
    if (_isParkingCardOpen || _parkingDetailsLoading) return;
    var zone = _zonesById[zoneId];
    if (zone == null) {
      setState(() => _parkingDetailsLoading = true);
      try {
        zone = await ref.read(zonesRepositoryProvider).getZoneDetails(zoneId);
      } catch (error, stackTrace) {
        if (mounted) {
          ref.read(parkingSearchProvider.notifier).backToResults();
          showErrorSnackBar(
            context,
            ref.read(l10nProvider).errorLoadingZones,
            error: error,
            stackTrace: stackTrace,
            s: ref.read(l10nProvider),
            onRetry: () => _openCandidateById(zoneId),
          );
        }
        return;
      } finally {
        if (mounted) setState(() => _parkingDetailsLoading = false);
      }
    }
    if (!mounted) return;
    await _openCandidateDetails(zone);
  }

  Future<void> _openCandidateDetails(Zone zone) async {
    if (_isParkingCardOpen) return;
    if (!ref.read(parkingSearchProvider.notifier).showDetails(zone.zoneId)) {
      return;
    }
    await _focusZone(zone);
    if (!mounted) return;
    setState(() => _isParkingCardOpen = true);
    final result = await showParkingCard(context, zone, showBackButton: true);
    if (!mounted) return;
    setState(() => _isParkingCardOpen = false);
    if (result == ParkingCardResult.buildRoute) {
      ref.read(parkingSearchProvider.notifier).startRoute(zone.zoneId);
      await _buildRouteForZone(zone.zoneId);
    } else {
      ref.read(parkingSearchProvider.notifier).backToResults();
    }
  }

  Future<void> _focusZone(Zone zone) async {
    if (zone.geometry.isEmpty) return;
    final target = centroid(zone.geometry);
    if (kIsWeb) {
      _webMapController.move(target.latitude, target.longitude, 17);
      return;
    }
    await _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: target, zoom: 17)),
      animation: const MapAnimation(duration: 0.65),
    );
  }

  void _onCandidateAction(
    CandidateAction action,
    RouteCandidate candidate,
    Zone? zone,
  ) {
    switch (action) {
      case CandidateAction.go:
        ref.read(parkingSearchProvider.notifier).startRoute(candidate.zoneId);
        _buildRouteForZone(candidate.zoneId);
      case CandidateAction.openExternal:
        if (zone == null || zone.geometry.isEmpty) return;
        final point = centroid(zone.geometry);
        openYandexNavigator(point.latitude, point.longitude);
    }
  }

  void _onClusterTap(_, Cluster cluster) {
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
      CameraUpdate.newGeometry(
        Geometry.fromBoundingBox(
          BoundingBox(
            southWest: Point(
              latitude: latMin - latPad,
              longitude: lonMin - lonPad,
            ),
            northEast: Point(
              latitude: latMax + latPad,
              longitude: lonMax + lonPad,
            ),
          ),
        ),
      ),
      animation: const MapAnimation(duration: 0.5),
    );
  }

  List<MapObject> _zoneObjectsFor(
    List<Zone> zones,
    Set<int> candidateIds,
    int? selectedZoneId,
  ) {
    if (!identical(_cachedMapZones, zones) ||
        !setEquals(_cachedCandidateIds, candidateIds) ||
        _cachedSelectedZoneId != selectedZoneId) {
      _cachedMapZones = zones;
      _cachedCandidateIds = Set.unmodifiable(candidateIds);
      _cachedSelectedZoneId = selectedZoneId;
      _cachedZoneObjects = buildZoneMapObjects(
        zones: zones,
        resultIds: candidateIds,
        selectedId: selectedZoneId,
        onTap: _onZoneTap,
      );
      _cachedZoneLabels = null;
    }
    return _cachedZoneObjects;
  }

  MapObject? _zoneLabelsFor(
    List<Zone> zones,
    Set<int> candidateIds,
    int? selectedZoneId,
  ) {
    if (_zoneLabelCache.isEmpty) return null;
    if (_cachedZoneLabels == null ||
        !identical(_cachedMapZones, zones) ||
        !identical(_cachedLabelBitmaps, _zoneLabelCache)) {
      _cachedLabelBitmaps = _zoneLabelCache;
      _cachedZoneLabels = buildZoneLabels(
        zones: zones,
        bitmapCache: _zoneLabelCache,
        zonesById: _zonesById,
        resultIds: candidateIds,
        selectedId: selectedZoneId,
        onZoneTap: _onZoneTap,
        onClusterTap: _onClusterTap,
      );
    }
    return _cachedZoneLabels;
  }

  Future<void> _fetchZones({bool clearCache = false}) async {
    if (clearCache) {
      _zoneLabelCache.clear();
      _zonesById.clear();
    }
    if (kIsWeb) {
      final camera = _webMapController.camera;
      if (!_webMapReady || camera == null) return;
      await _fetchWebZones(camera);
      return;
    }
    if (_mapController == null) return;
    try {
      final visibleRegion = await _mapController!.getVisibleRegion();
      final bottomLeft = visibleRegion.bottomLeft;
      final topRight = visibleRegion.topRight;
      final dLon = (topRight.longitude - bottomLeft.longitude) * 0.5;
      final dLat = (topRight.latitude - bottomLeft.latitude) * 0.5;
      final bbox =
          '${bottomLeft.longitude - dLon},${bottomLeft.latitude - dLat},'
          '${topRight.longitude + dLon},${topRight.latitude + dLat}';
      await ref.read(rawZonesProvider.notifier).fetchZones(bbox);
    } catch (e, st) {
      ref.read(rawZonesProvider.notifier).setErrorState(e, st);
    }
  }

  Future<void> _fetchWebZones(WebMapCamera camera) async {
    if ((camera.east - camera.west).abs() < 0.000001 ||
        (camera.north - camera.south).abs() < 0.000001) {
      return;
    }
    final dLon = (camera.east - camera.west) * 0.5;
    final dLat = (camera.north - camera.south) * 0.5;
    final bbox =
        '${camera.west - dLon},${camera.south - dLat},'
        '${camera.east + dLon},${camera.north + dLat}';
    try {
      await ref.read(rawZonesProvider.notifier).fetchZones(bbox);
    } catch (e, st) {
      ref.read(rawZonesProvider.notifier).setErrorState(e, st);
    }
  }

  void _onWebCameraChanged(WebMapCamera camera) {
    _lastCameraTarget = Point(
      latitude: camera.latitude,
      longitude: camera.longitude,
    );
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _fetchWebZones(camera),
    );
  }

  Future<Position?> _getCurrentPosition({bool showDeniedDialog = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const LocationServiceDisabledException();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        if (showDeniedDialog) _showLocationDeniedDialog();
        return null;
      }
      try {
        final cached = await Geolocator.getLastKnownPosition();
        if (cached != null) {
          _userPosition = cached;
          return cached;
        }
      } catch (_) {
        // Browsers may not implement last-known position; request a fresh fix.
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 5),
        ),
      );
      _userPosition = pos;
      return pos;
    } catch (error, stackTrace) {
      if (showDeniedDialog && error is! PermissionDeniedException && mounted) {
        showErrorSnackBar(
          context,
          ref.read(l10nProvider).unknownError,
          error: error,
          stackTrace: stackTrace,
          s: ref.read(l10nProvider),
          onRetry: _goToMyLocation,
        );
      }
      return null;
    }
  }

  Future<Point?> _routingOrigin() async {
    final position = await _getCurrentPosition(showDeniedDialog: !kIsWeb);
    if (position != null) {
      return Point(latitude: position.latitude, longitude: position.longitude);
    }
    if (!kIsWeb) return null;
    return _lastCameraTarget ??
        const Point(latitude: 61.789114, longitude: 34.359757);
  }

  Future<void> _goToMyLocation() async {
    final pos = await _getCurrentPosition();
    if (pos == null) return;
    if (mounted) setState(() {});
    if (kIsWeb) {
      _webMapController.move(pos.latitude, pos.longitude, 16);
      return;
    }
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
    if (kIsWeb) return;
    if (_mapController == null) return;
    final pos = await _mapController!.getCameraPosition();
    await _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: pos.target, zoom: pos.zoom, azimuth: 0, tilt: 0),
      ),
      animation: const MapAnimation(duration: 0.4),
    );
  }

  Future<void> _zoomIn() async {
    if (kIsWeb) {
      _webMapController.zoomBy(1);
      return;
    }
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
    if (kIsWeb) {
      _webMapController.zoomBy(-1);
      return;
    }
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
    final s = ref.read(l10nProvider);
    showDialog(
      context: context,
      builder: (_) => PointerInterceptor(
        intercepting: kIsWeb,
        child: AlertDialog(
          title: Text(s.locationPermissionDenied),
          content: Text(s.locationPermissionReason),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.cancel),
            ),
            if (!kIsWeb)
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Geolocator.openAppSettings();
                },
                child: Text(s.settings),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSearch() async {
    final webCamera = kIsWeb ? _webMapController.camera : null;
    final bias = webCamera != null
        ? SearchBias(
            latitude: webCamera.latitude,
            longitude: webCamera.longitude,
            south: webCamera.south,
            west: webCamera.west,
            north: webCamera.north,
            east: webCamera.east,
          )
        : _userPosition != null
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
    final origin = await _routingOrigin();
    if (origin == null) return;
    await ref
        .read(routingProvider.notifier)
        .searchParking(originLat: origin.latitude, originLon: origin.longitude);
  }

  Future<void> _buildRouteForZone(int zoneId) async {
    final origin = await _routingOrigin();
    if (origin == null) return;
    await ref
        .read(routingProvider.notifier)
        .buildRoute(
          originLat: origin.latitude,
          originLon: origin.longitude,
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
      final origin = await _routingOrigin();
      if (origin == null) return;

      if (kIsWeb) {
        _webMapController.move(origin.latitude, origin.longitude, 17);
      } else {
        await _mapController?.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: origin, zoom: 17, tilt: 40),
          ),
          animation: const MapAnimation(duration: 0.8),
        );
      }

      List<Point> route;
      double totalSeconds = _routeDurationSeconds;
      double totalMeters = 0;

      if (_routePolyline != null && _routePolyline!.length >= 2) {
        route = _routePolyline!;
      } else {
        if (kIsWeb) {
          final webRoute = await requestYandexWebRoute(
            fromLatitude: origin.latitude,
            fromLongitude: origin.longitude,
            toLatitude: toLat,
            toLongitude: toLon,
          );
          if (webRoute == null || webRoute.points.length < 2) {
            if (mounted) {
              showErrorSnackBar(
                context,
                ref.read(l10nProvider).errorCreatingRoute,
                s: ref.read(l10nProvider),
              );
            }
            return;
          }
          if (!mounted) return;
          route = webRoute.points;
          totalSeconds = webRoute.durationSeconds;
          totalMeters = webRoute.distanceMeters;
        } else {
          await _drivingSession?.close();
          final rws = YandexDriving.requestRoutes(
            points: [
              RequestPoint(
                point: origin,
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
          if (dr == null) {
            throw StateError('Yandex MapKit did not return a route');
          }
          if (!mounted) return;
          route = dr.geometry;
          totalSeconds = dr.metadata.weight.timeWithTraffic.value ?? 0;
          totalMeters = dr.metadata.weight.distance.value ?? 0;
        }
        setState(() => _routePolyline = route);
      }

      await ref
          .read(navigationProvider.notifier)
          .startNavigation(
            zoneId: zoneId,
            route: route,
            totalSeconds: totalSeconds,
            totalMeters: totalMeters,
            destLat: toLat,
            destLon: toLon,
            s: ref.read(l10nProvider),
          );

      await _mapController?.toggleUserLayer(visible: false);
      await _mapController?.toggleTrafficLayer(visible: true);
    } catch (e, st) {
      if (mounted) {
        showErrorSnackBar(
          context,
          ref.read(l10nProvider).errorCreatingRoute,
          error: e,
          stackTrace: st,
          s: ref.read(l10nProvider),
          onRetry: () =>
              _startInAppNavigation(zoneId: zoneId, toLat: toLat, toLon: toLon),
        );
      }
    } finally {
      if (mounted) setState(() => _navBuilding = false);
    }
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => PointerInterceptor(
        intercepting: kIsWeb,
        child: const _FiltersSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bottomInset = 0.0;
    final s = ref.watch(l10nProvider);
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

    ref.listen(timeSelectorProvider, (_, _) {
      ref.read(rawZonesProvider.notifier).clearZones();
      _zoneLabelCache.clear();
      _zonesById.clear();
      _timeDebounce?.cancel();
      _timeDebounce = Timer(
        const Duration(milliseconds: 600),
        () => _fetchZones(clearCache: false),
      );
    });
    ref.listen(filteredZonesProvider, (_, zones) => _updateZoneBitmaps(zones));

    ref.listen(navigationProvider, (prev, nav) {
      if (nav == null) return;
      if (prev?.route != nav.route) {
        setState(() => _routePolyline = nav.route);
      }
      if (kIsWeb) {
        _webMapController.move(
          nav.currentPosition.latitude,
          nav.currentPosition.longitude,
          17,
        );
        return;
      }
      _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: nav.currentPosition,
            zoom: 17,
            azimuth: nav.heading,
            tilt: 40,
          ),
        ),
      );
    });

    ref.listen(rawZonesProvider, (_, next) {
      next.whenOrNull(
        error: (e, st) {
          showErrorSnackBar(
            context,
            ref.read(l10nProvider).errorLoadingZones,
            error: e,
            stackTrace: st,
            s: ref.read(l10nProvider),
            onRetry: () => ref.read(rawZonesProvider.notifier).refresh(),
          );
        },
      );
    });

    ref.listen(routingFailureProvider, (_, event) {
      if (event == null) return;
      showErrorSnackBar(
        context,
        ref.read(l10nProvider).errorCreatingRoute,
        error: event.failure,
        s: ref.read(l10nProvider),
        onRetry: event.retry,
      );
    });

    ref.listen(destinationProvider, (_, dest) {
      if (dest == null) return;
      if (kIsWeb) {
        _webMapController.move(dest.latitude, dest.longitude, 15);
        return;
      }
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
            _routeDurationSeconds = 0;
            _activeRouteZoneId = null;
          });
        },
        searching: () async {},
        error: (_) async {},
        candidates: (_) async {},
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
            }
          }

          final selectedCandidates = route.candidates.where(
            (candidate) => candidate.zoneId == route.selectedZoneId,
          );
          final candidate =
              selectedCandidates.firstOrNull ?? route.candidates.firstOrNull;

          if (zoneLat == null &&
              candidate?.routePolyline != null &&
              candidate!.routePolyline!.isNotEmpty) {
            final lastPoint = candidate.routePolyline!.last;
            zoneLat = lastPoint.latitude;
            zoneLon = lastPoint.longitude;
          }

          if (zoneLat != null && zoneLon != null) {
            final target = Point(latitude: zoneLat, longitude: zoneLon);
            final polyline = route.routePolyline ?? candidate?.routePolyline;

            if (polyline != null && polyline.isNotEmpty && kIsWeb) {
              // On web, try to fit bounds for better UX
              final south = polyline.map((p) => p.latitude).reduce(math.min);
              final north = polyline.map((p) => p.latitude).reduce(math.max);
              final west = polyline.map((p) => p.longitude).reduce(math.min);
              final east = polyline.map((p) => p.longitude).reduce(math.max);
              _webMapController.fitBounds(south, west, north, east);
            } else if (kIsWeb) {
              _webMapController.move(zoneLat, zoneLon, 17);
            } else {
              await _mapController?.moveCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(target: target, zoom: 17),
                ),
                animation: const MapAnimation(duration: 0.8),
              );
            }
          }

          setState(() {
            _routePolyline = route.routePolyline ?? candidate?.routePolyline;
            _routeDurationSeconds =
                candidate?.durationFromOriginSeconds?.toDouble() ?? 0;
            _activeRouteZoneId = route.selectedZoneId;
          });

          if (!context.mounted) return;
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => PointerInterceptor(
              intercepting: kIsWeb,
              child: RoutePreviewSheet(
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
            ),
          );
          _isRouteSheetOpen = false;
        },
      );
    });

    final parkingSearchState = ref.watch(parkingSearchProvider);
    final candidateIds = parkingSearchState.resultZoneIds;
    _candidateIds = candidateIds;
    final selectedSearchZoneId =
        parkingSearchState.view == ParkingSearchView.details ||
            parkingSearchState.view == ParkingSearchView.hidden
        ? parkingSearchState.selectedZoneId
        : null;

    final zoneObjects = _zoneObjectsFor(
      zones,
      candidateIds,
      selectedSearchZoneId,
    );
    final zoneLabels = _zoneLabelsFor(
      zones,
      candidateIds,
      selectedSearchZoneId,
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
      if (selectedSearchZoneId != null &&
          selectedSearchZoneId != _activeRouteZoneId)
        ...buildHighlightZone(zones, selectedSearchZoneId),
      ?zoneLabels,
      if (_userPosition != null && _userLocationBytes != null && !isNavigating)
        PlacemarkMapObject(
          mapId: const MapObjectId('user_location'),
          point: Point(
            latitude: _userPosition!.latitude,
            longitude: _userPosition!.longitude,
          ),
          icon: PlacemarkIcon.single(
            PlacemarkIconStyle(
              image: BitmapDescriptor.fromBytes(_userLocationBytes!),
              scale: 1.0,
            ),
          ),
        ),
      if (isNavigating && _navArrowBytes != null)
        PlacemarkMapObject(
          mapId: const MapObjectId('nav_arrow'),
          point: navState.currentPosition,
          opacity: 1.0,
          icon: PlacemarkIcon.single(
            PlacemarkIconStyle(
              image: BitmapDescriptor.fromBytes(_navArrowBytes!),
              scale: 1.0,
            ),
          ),
        ),
      if (destination != null && _destinationPinBytes != null)
        PlacemarkMapObject(
          mapId: const MapObjectId('destination_pin'),
          point: Point(
            latitude: destination.latitude,
            longitude: destination.longitude,
          ),
          icon: PlacemarkIcon.single(
            PlacemarkIconStyle(
              image: BitmapDescriptor.fromBytes(_destinationPinBytes!),
              scale: 1.0,
            ),
          ),
        ),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final searchResultsVisible =
        parkingSearchState.view == ParkingSearchView.results &&
        parkingSearchState.candidates.isNotEmpty &&
        !isNavigating;
    final searchPanelHeight = (MediaQuery.sizeOf(context).height * 0.56).clamp(
      240.0,
      480.0,
    );

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            if (kIsWeb)
              WebMapView(
                controller: _webMapController,
                zones: zones,
                candidateIds: candidateIds,
                selectedZoneId: selectedSearchZoneId,
                onZoneTap: _onZoneTap,
                route: _routePolyline,
                activeRouteZoneId: _activeRouteZoneId,
                userLatitude: isNavigating ? null : _userPosition?.latitude,
                userLongitude: isNavigating ? null : _userPosition?.longitude,
                navigationLatitude: isNavigating
                    ? navState.currentPosition.latitude
                    : null,
                navigationLongitude: isNavigating
                    ? navState.currentPosition.longitude
                    : null,
                navigationHeading: isNavigating ? navState.heading : null,
                destinationLatitude: destination?.latitude,
                destinationLongitude: destination?.longitude,
                onCameraChanged: _onWebCameraChanged,
                onError: (error) {
                  showErrorSnackBar(
                    context,
                    ref.read(l10nProvider).mapLoadError,
                    error: error,
                    s: ref.read(l10nProvider),
                    onRetry: _webMapController.retry,
                  );
                },
                onMapReady: () {
                  _webMapReady = true;
                  final camera = _webMapController.camera;
                  if (camera != null) {
                    _lastCameraTarget = Point(
                      latitude: camera.latitude,
                      longitude: camera.longitude,
                    );
                    _fetchWebZones(camera);
                  }
                },
              )
            else
              YandexMap(
                mapObjects: mapObjects,
                nightModeEnabled: isDark,
                onMapCreated: (controller) async {
                  _mapController = controller;
                  const fallback = Point(
                    latitude: 61.789114,
                    longitude: 34.359757,
                  );
                  _lastCameraTarget = fallback;
                  await controller.moveCamera(
                    CameraUpdate.newCameraPosition(
                      const CameraPosition(target: fallback, zoom: 14),
                    ),
                  );
                  _fetchZones();
                },
                onCameraPositionChanged: _onCameraPositionChanged,
              ),
            if (searchResultsVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: searchPanelHeight,
                child: PointerInterceptor(
                  intercepting: kIsWeb,
                  child: CandidatesSheet(
                    candidates: parkingSearchState.candidates,
                    zones: zones,
                    lastViewedZoneId: parkingSearchState.lastViewedZoneId,
                    initialScrollOffset: parkingSearchState.scrollOffset,
                    onSelect: _openCandidateById,
                    onAction: _onCandidateAction,
                    onScrollOffsetChanged: ref
                        .read(parkingSearchProvider.notifier)
                        .saveScrollOffset,
                    onClose: ref.read(routingProvider.notifier).reset,
                  ),
                ),
              ),
            // ─── Top bar ───────────────────────────────────────────────
            if (!isNavigating)
              PointerInterceptor(
                intercepting: kIsWeb,
                child: SafeArea(
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
                                color: Theme.of(context).colorScheme.surface,
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
                                  Icon(
                                    Icons.search,
                                    color: Theme.of(context).hintColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      destination?.name ?? s.searchPlaceholder,
                                      style: TextStyle(
                                        color: Theme.of(context).hintColor,
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
              ),
            Positioned(
              right: 12,
              top: 0,
              bottom: searchResultsVisible ? searchPanelHeight : 0,
              child: Align(
                alignment: Alignment.center,
                child: PointerInterceptor(
                  intercepting: kIsWeb,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MapButton(
                        onTap: _resetNorth,
                        child: Transform.rotate(
                          angle: -_currentAzimuth * math.pi / 180,
                          child: Icon(
                            Icons.explore,
                            size: 22,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _MapButton(icon: Icons.add, onTap: _zoomIn),
                      const SizedBox(height: 4),
                      _MapButton(icon: Icons.remove, onTap: _zoomOut),
                      const SizedBox(height: 4),
                      _MapButton(
                        icon: Icons.my_location,
                        onTap: _goToMyLocation,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // ─── Селектор времени: всегда левый край ──────────────
            if (destination == null &&
                !isNavigating &&
                parkingSearchState.view != ParkingSearchView.results)
              Positioned(
                bottom: bottomInset + 20,
                left: 16,
                child: PointerInterceptor(
                  intercepting: kIsWeb,
                  child: const TimeSelectorWidget(),
                ),
              ),
            // ─── FAB: всегда правый край ───────────────────────────
            if (destination == null &&
                !isNavigating &&
                parkingSearchState.view != ParkingSearchView.results)
              Positioned(
                bottom: bottomInset + 20,
                right: 16,
                child: PointerInterceptor(
                  intercepting: kIsWeb,
                  child: FloatingActionButton.extended(
                    heroTag: 'find_parking',
                    onPressed: isRoutingLoading ? null : _findParking,
                    backgroundColor: AppColors.primary,
                    icon: const Icon(Icons.local_parking, color: Colors.white),
                    label: Text(
                      isRoutingLoading ? s.searching : s.findParking,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            // ─── Карточка назначения ────────────────────────────────────
            if (destination != null &&
                !isNavigating &&
                parkingSearchState.view != ParkingSearchView.results)
              Positioned(
                bottom: bottomInset + 76,
                left: 12,
                right: 12,
                child: PointerInterceptor(
                  intercepting: kIsWeb,
                  child: _DestinationCard(
                    destination: destination,
                    onFindParking: isRoutingLoading ? null : _findParking,
                    onNavigate: kIsWeb
                        ? () {}
                        : () => openYandexNavigator(
                            destination.latitude,
                            destination.longitude,
                          ),
                    onNavigateInApp: () => _startInAppNavigation(
                      zoneId: 0,
                      toLat: destination.latitude,
                      toLon: destination.longitude,
                    ),
                    onClear: () {
                      ref.read(destinationProvider.notifier).state = null;
                      ref.read(routingProvider.notifier).reset();
                    },
                  ),
                ),
              ),
            // ─── Loading indicators ─────────────────────────────────────
            if (zonesAsync.isLoading && !zonesAsync.hasValue)
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
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: PointerInterceptor(
                  intercepting: kIsWeb,
                  child: const NavigationTurnCard(),
                ),
              ),
            if (isNavigating)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: PointerInterceptor(
                  intercepting: kIsWeb,
                  child: NavigationBottomBar(
                    onFinish: () {
                      ref.read(navigationProvider.notifier).stop();
                      ref.read(routingProvider.notifier).reset();
                    },
                  ),
                ),
              ),
            if (_navBuilding)
              Positioned.fill(
                child: PointerInterceptor(
                  intercepting: kIsWeb,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(s.searching),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_parkingDetailsLoading)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x33000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            if (isRoutingLoading)
              Positioned(
                top: 148,
                left: 0,
                right: 0,
                child: Center(
                  child: PointerInterceptor(
                    intercepting: kIsWeb,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(s.searching),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            const PwaInstallGuide(),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────

class _DestinationCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(l10nProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
                  destination.name ?? s.selectedPlace,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onFindParking,
            icon: const Icon(Icons.local_parking, size: 16),
            label: Text(s.searchParkingNear),
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
                  label: Text(s.inAppRoute),
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 13),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!kIsWeb)
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: onNavigate,
                    style: FilledButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 13),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(s.yandexNavigator),
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
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
            ),
          ],
        ),
        child:
            child ??
            Icon(
              icon!,
              size: 22,
              color: Theme.of(context).colorScheme.onSurface,
            ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────

class _FiltersSheet extends ConsumerWidget {
  const _FiltersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(l10nProvider);
    final filters = ref.watch(filtersProvider);
    final notifier = ref.read(filtersProvider.notifier);
    final hasPayLimit = filters.maxPayPerHour != null;
    final payValue = (filters.maxPayPerHour ?? 200).clamp(0, 500);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).padding.bottom + 24,
          ),
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
                Expanded(
                  child: Text(
                    s.filters,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(onPressed: notifier.reset, child: Text(s.reset)),
              ],
            ),
            SwitchListTile(
              title: Text(s.hideFull),
              value: filters.hideNoFreeSpots,
              onChanged: (_) => notifier.toggleHideNoFreeSpots(),
            ),
            SwitchListTile(
              title: Text(s.hidePrivate),
              value: filters.hidePrivate,
              onChanged: (_) => notifier.toggleHidePrivate(),
            ),
            SwitchListTile(
              title: Text(s.hideInaccessible),
              value: filters.hideInaccessible,
              onChanged: (_) => notifier.toggleHideInaccessible(),
            ),
            SwitchListTile(
              title: Text(s.hideInactive),
              value: filters.hideInactive,
              onChanged: (_) => notifier.toggleHideInactive(),
            ),
            const Divider(),
            Text(
              s.minConfidence,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '${(filters.minConfidence * 100).round()}%',
              style: TextStyle(
                color: Theme.of(context).hintColor,
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
              title: Text(s.limitPrice),
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
                    '$payValue ₽/${s.hourSign}',
                    style: TextStyle(
                      color: Theme.of(context).hintColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Slider(
                    value: payValue.toDouble(),
                    min: 0,
                    max: 500,
                    divisions: 20,
                    label: '$payValue ₽/${s.hourSign}',
                    onChanged: (value) => notifier.setMaxPay(value.round()),
                  ),
                ],
              ),
            const Divider(),
            Text(
              s.minFreeSpots,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              filters.minFreeCount == 0 ? s.any : '${filters.minFreeCount}+',
              style: TextStyle(
                color: Theme.of(context).hintColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            Slider(
              value: filters.minFreeCount.toDouble(),
              min: 0,
              max: 20,
              divisions: 20,
              label: filters.minFreeCount == 0
                  ? s.any
                  : '${filters.minFreeCount}+',
              onChanged: (v) => notifier.setMinFreeCount(v.round()),
            ),
            const Divider(),
            Text(
              s.locationType,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final entry in {
              'street': s.street,
              'yard': s.yard,
              'open_lot': s.openLot,
              'underground': s.underground,
              'multilevel': s.multilevel,
            }.entries)
              CheckboxListTile(
                title: Text(entry.value),
                value: !filters.hiddenLocationTypes.contains(entry.key),
                onChanged: (_) => notifier.toggleLocationType(entry.key),
                dense: true,
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.apply),
            ),
          ],
        ),
      ),
    );
  }
}
