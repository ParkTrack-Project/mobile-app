import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb,
        setEquals,
        visibleForTesting;
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
import '../../../core/utils/app_share.dart';
import '../../../core/utils/error_snackbar.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/services/android_heading_source.dart';
import '../../../core/services/preferred_location_service.dart';
import '../../../core/services/yandex_web_route.dart';
import '../../providers/parking_address_provider.dart';
import 'my_location_camera_state.dart';
import 'route_camera.dart';
import 'widgets/candidates_sheet.dart';
import 'widgets/destination_marker.dart';
import 'widgets/location_follow_icon.dart';
import 'widgets/map_compass_button.dart';
import 'widgets/navigation_overlay.dart'
    show NavigationTurnCard, NavigationBottomBar;
import 'widgets/parking_zone_layer.dart';
import 'widgets/parking_result_formatter.dart';
import 'widgets/time_selector_widget.dart';
import 'widgets/user_location_marker.dart';
import 'widgets/web_map_view.dart';
import 'widgets/web_map_types.dart';
import 'widgets/parking_card_sheet.dart';
import 'widgets/route_preview_sheet.dart';
import 'widgets/pwa_install_guide.dart';

const double _minMapZoom = 3;
const double _maxMapZoom = 21;
const double _myLocationZoom = 17;
const double _tapZoomStep = 1;
const double _holdZoomStep = 0.224;
const double _tapZoomDurationSeconds = 0.18;
const double _holdZoomDurationSeconds = 0.05;
const Duration _userLocationMoveDuration = Duration(milliseconds: 950);
const Duration _userLocationFreshnessDuration = Duration(seconds: 20);
const Duration _androidLocationRetryInitialDelay = Duration(seconds: 2);
const Duration _androidLocationRetryMaxDelay = Duration(seconds: 30);
const double userLocationAccuracyCircleThresholdMeters = 20;

enum UserLocationFreshness { current, stale }

enum _AndroidLocationRefreshResult { updated, unavailable, permissionDenied }

@visibleForTesting
double userLocationMarkerOpacity(UserLocationFreshness freshness) =>
    freshness == UserLocationFreshness.current ? 1 : 0.6;

@visibleForTesting
bool shouldShowUserLocationAccuracyCircle({
  required double accuracy,
  required UserLocationFreshness freshness,
}) =>
    freshness == UserLocationFreshness.current &&
    accuracy.isFinite &&
    accuracy > userLocationAccuracyCircleThresholdMeters;

@visibleForTesting
bool isUserPositionFresh(Position position, DateTime now) {
  final age = now.difference(position.timestamp);
  return !age.isNegative && age <= _userLocationFreshnessDuration;
}

@visibleForTesting
bool isMapNorthUp(double azimuth, {double tolerance = 1.0}) {
  if (!azimuth.isFinite) return false;
  final normalized = ((azimuth % 360) + 360) % 360;
  return math.min(normalized, 360 - normalized) <= tolerance;
}

@visibleForTesting
Point interpolateMapPoint(Point from, Point to, double t) {
  final clamped = t.clamp(0.0, 1.0);
  final longitudeDelta = shortestLongitudeDelta(from.longitude, to.longitude);
  return Point(
    latitude: from.latitude + (to.latitude - from.latitude) * clamped,
    longitude: normalizeLongitude(from.longitude + longitudeDelta * clamped),
  );
}

@visibleForTesting
double shortestLongitudeDelta(double from, double to) {
  final normalizedFrom = normalizeLongitude(from);
  final normalizedTo = normalizeLongitude(to);
  var delta = normalizedTo - normalizedFrom;
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  return delta;
}

@visibleForTesting
double normalizeLongitude(double longitude) {
  if (!longitude.isFinite) return longitude;
  return ((longitude + 180) % 360 + 360) % 360 - 180;
}

@visibleForTesting
double resolveZoomControlsBottom({
  required double viewportHeight,
  required double mapControlsBottom,
}) {
  const zoomControlsHeight = 105.0;
  const lowerControlsHeight = 52.0;
  const controlsGap = 10.0;
  final centeredBottom = viewportHeight / 2 - zoomControlsHeight / 2;
  return math.max(
    centeredBottom,
    mapControlsBottom + lowerControlsHeight + controlsGap,
  );
}

@visibleForTesting
bool shouldShowLowerMapControls({
  required double viewportHeight,
  required double mapControlsBottom,
}) {
  const controlHeight = 52.0;
  const minimumTop = 112.0;
  final controlTop = viewportHeight - mapControlsBottom - controlHeight;
  return controlTop >= minimumTop;
}

@visibleForTesting
bool shouldIgnoreMapBackgroundTap({
  required DateTime? lastZoneTapAt,
  required DateTime now,
}) {
  if (lastZoneTapAt == null) return false;
  final elapsed = now.difference(lastZoneTapAt);
  return !elapsed.isNegative && elapsed < const Duration(milliseconds: 200);
}

@visibleForTesting
bool shouldDismissParkingDetailsForDestination({
  required Destination? destination,
  required bool hasStandaloneParkingDetails,
}) => destination != null && hasStandaloneParkingDetails;

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({
    super.key,
    this.initialParkingId,
    this.initialRouteId,
    this.searchQuery,
    this.initialDestination,
  });

  final int? initialParkingId;
  final int? initialRouteId;
  final String? searchQuery;
  final Destination? initialDestination;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  YandexMapController? _mapController;
  final WebMapController _webMapController = WebMapController();
  bool _webMapReady = false;
  Timer? _debounce;
  Timer? _timeDebounce;
  final ValueNotifier<double> _compassAzimuth = ValueNotifier(0);
  Position? _userPosition;
  Point? _displayedUserPoint;
  AnimationController? _userLocationAnimation;
  Point? _userLocationAnimationStart;
  Point? _userLocationAnimationEnd;
  UserLocationFreshness _userLocationFreshness = UserLocationFreshness.stale;
  StreamSubscription<Position>? _userPositionSubscription;
  StreamSubscription<double>? _headingSubscription;
  Timer? _userLocationStaleTimer;
  Timer? _locationRetryTimer;
  bool _locationRefreshInFlight = false;
  int? _locationRefreshInFlightGeneration;
  int _locationTrackingGeneration = 0;
  int _locationRetryAttempt = 0;
  DateTime? _lastLiveLocationAt;
  double? _deviceHeading;
  bool _androidLocationTrackingStarted = false;
  Point? _lastCameraTarget;
  double _currentZoom = 14;
  double _currentAzimuth = 0;
  double _currentTilt = 0;
  bool _showCompass = false;
  MyLocationCameraMode _myLocationCameraMode = MyLocationCameraMode.free;
  double? _queuedZoomTarget;
  int _zoomMoveGeneration = 0;
  ({double west, double south, double east, double north})?
  _nativeVisibleBounds;
  List<Zone>? _cachedViewportZonesSource;
  ({double west, double south, double east, double north})?
  _cachedViewportBounds;
  List<Zone> _cachedViewportZones = const [];
  Uint8List? _destinationPinBytes;
  Uint8List? _navArrowBytes;
  UserLocationMarkerBitmaps? _userLocationMarkerBitmaps;
  double? _userLocationMarkerDpr;
  bool _markerBitmapsLoading = false;
  Future<void>? _markerBitmapsFuture;

  bool _parkingDetailsLoading = false;
  Zone? _standaloneSelectedZone;
  final Map<int, Zone> _resultZonesById = {};
  String? _preparedResultSignature;
  double _searchPanelHeight = 360;
  double _detailsPanelHeight = 300;
  double _routePreviewPanelHeight = 260;
  double _destinationPanelHeight = 168;
  Brightness? _markerBrightness;

  Map<int, Uint8List> _zoneLabelCache = {};
  Map<int, Zone> _zonesById = {};
  final Map<({int? count, int color, int textColor}), Uint8List>
  _zoneBitmapCache = {};
  Map<int, ({int? count, int color, int textColor})> _zoneStylesById = {};
  int _bitmapGeneration = 0;
  List<Point>? _routePolyline;
  double _routeDurationSeconds = 0;
  double _routeDistanceMeters = 0;
  int? _activeRouteZoneId;
  DrivingSession? _drivingSession;
  bool _routeBuilding = false;
  bool _navBuilding = false;
  bool _nativeUserLayerVisible = false;
  String? _lastShownZonesErrorSignature;
  DateTime? _lastZoneTapAt;

  List<Zone>? _cachedMapZones;
  Set<int> _cachedCandidateIds = const {};
  Set<int> _cachedTappableZoneIds = const {};
  int? _cachedSelectedZoneId;
  Brightness? _cachedZoneObjectBrightness;
  List<MapObject> _cachedZoneObjects = const [];
  Map<int, Uint8List>? _cachedLabelBitmaps;
  List<MapObject>? _cachedZoneLabels;
  Brightness? _cachedZoneLabelBrightness;
  List<Zone>? _cachedClusteringZones;
  double? _cachedClusteringZoom;
  ParkingClusteringResult? _cachedClustering;
  final Map<ParkingClusterBitmapKey, Uint8List> _clusterLabelCache = {};
  final Set<ParkingClusterBitmapKey> _clusterBitmapRequests = {};
  Set<int> _candidateIds = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialDestination != null) {
        ref.read(routingProvider.notifier).reset();
        ref.read(destinationProvider.notifier).state =
            widget.initialDestination;
      } else if (widget.initialRouteId != null) {
        ref.read(routingProvider.notifier).loadRoute(widget.initialRouteId!);
      } else if (widget.initialParkingId != null) {
        _loadAndShowParking(widget.initialParkingId!);
      } else if (widget.searchQuery != null) {
        _performSearch(widget.searchQuery!);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (!_markerBitmapsLoading && _userLocationMarkerDpr != dpr) {
      _userLocationMarkerDpr = dpr;
      _markerBitmapsFuture = _loadMarkerBitmaps(dpr);
      unawaited(_markerBitmapsFuture);
    }
  }

  Future<void> _loadMarkerBitmaps(double devicePixelRatio) async {
    _markerBitmapsLoading = true;
    try {
      final bitmaps = await Future.wait<Object>([
        buildDestinationPinBitmap(),
        _buildNavArrowBitmap(),
        buildUserLocationMarkerBitmaps(devicePixelRatio: devicePixelRatio),
      ]);
      if (!mounted) return;
      setState(() {
        _destinationPinBytes = bitmaps[0] as Uint8List;
        _navArrowBytes = bitmaps[1] as Uint8List;
        _userLocationMarkerBitmaps = bitmaps[2] as UserLocationMarkerBitmaps;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to prepare map marker bitmaps: $error\n$stackTrace');
    } finally {
      _markerBitmapsLoading = false;
    }
  }

  Future<void> _loadAndShowParking(int id) async {
    try {
      final repo = ref.read(zonesRepositoryProvider);
      final zone = await repo.getZoneDetails(id);
      if (!mounted) return;
      await _openParkingDetails(zone);
    } catch (e) {
      debugPrint('Failed to load deep-link zone $id: $e');
    }
  }

  void _performSearch(String query) {
    context.push('/search?q=${Uri.encodeComponent(query)}');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _timeDebounce?.cancel();
    _userLocationStaleTimer?.cancel();
    _locationRetryTimer?.cancel();
    _locationTrackingGeneration++;
    _userPositionSubscription?.cancel();
    _headingSubscription?.cancel();
    _userLocationAnimation?.dispose();
    _compassAzimuth.dispose();
    _drivingSession?.close();
    super.dispose();
  }

  Future<void> _updateZoneBitmaps(
    List<Zone> zones, {
    Brightness brightness = Brightness.light,
  }) async {
    final styles = <int, ({int? count, int color, int textColor})>{};
    final textColor = brightness == Brightness.dark
        ? const Color(0xFF09090B)
        : Colors.white;
    for (final zone in zones) {
      final color = zoneColor(zone, brightness: brightness);
      styles[zone.zoneId] = (
        count: zone.freeCount,
        color: color.toARGB32(),
        textColor: textColor.toARGB32(),
      );
    }
    final same =
        styles.length == _zoneStylesById.length &&
        styles.entries.every(
          (entry) => _zoneStylesById[entry.key] == entry.value,
        );
    if (same) return;
    final generation = ++_bitmapGeneration;
    final newById = <int, Zone>{};
    final usedStyles = <({int? count, int color, int textColor})>{};
    for (final zone in zones) {
      if (zone.geometry.length < 3) continue;
      final style = styles[zone.zoneId]!;
      usedStyles.add(style);
      newById[zone.zoneId] = zone;
    }

    final missingStyles = usedStyles
        .where((style) => !_zoneBitmapCache.containsKey(style))
        .toList(growable: false);
    final generated = await Future.wait(
      missingStyles.map(
        (style) async => MapEntry(
          style,
          await buildCountBitmap(
            style.count,
            Color(style.color),
            textColor: Color(style.textColor),
          ),
        ),
      ),
    );
    if (_bitmapGeneration != generation) return;
    _zoneBitmapCache.addEntries(generated);

    final newCache = <int, Uint8List>{
      for (final entry in newById.entries)
        entry.key: _zoneBitmapCache[styles[entry.key]!]!,
    };
    if (mounted) {
      setState(() {
        _markerBrightness = brightness;
        _zoneLabelCache = newCache;
        _zonesById = newById;
        _zoneStylesById = styles;
        _zoneBitmapCache.removeWhere((key, _) => !usedStyles.contains(key));
      });
    }
  }

  bool get _usesManagedAndroidLocation =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _usesManagedAndroidLocation) {
      unawaited(_startAndroidLocationTracking(restart: true));
      unawaited(_startAndroidHeadingTracking(restart: true));
    }
  }

  Future<void> _startAndroidLocationTracking({bool restart = false}) async {
    if (!_usesManagedAndroidLocation ||
        (_androidLocationTrackingStarted && !restart)) {
      return;
    }
    _androidLocationTrackingStarted = true;
    final generation = ++_locationTrackingGeneration;
    await _userPositionSubscription?.cancel();
    _userPositionSubscription = null;
    _locationRetryTimer?.cancel();
    _locationRetryTimer = null;
    _locationRetryAttempt = 0;

    final service = ref.read(preferredLocationServiceProvider);
    try {
      final cached = await service.getLastKnownPosition();
      if (!mounted || generation != _locationTrackingGeneration) return;
      if (cached != null && _shouldApplyCachedUserPosition(cached)) {
        _applyUserPosition(cached, freshness: UserLocationFreshness.stale);
      }
    } catch (_) {
      // Cached lookup is best-effort; the displayed marker must stay as-is.
    }

    final refreshResult = await _refreshAndroidLocation(generation);
    if (!mounted || generation != _locationTrackingGeneration) return;
    if (refreshResult == _AndroidLocationRefreshResult.permissionDenied) {
      _androidLocationTrackingStarted = false;
      return;
    }

    _subscribeAndroidLocationStream(service, generation);
  }

  bool _shouldApplyCachedUserPosition(Position position) {
    final current = _userPosition;
    if (current == null) return true;
    if (_userLocationFreshness == UserLocationFreshness.current) return false;
    return position.timestamp.isAfter(current.timestamp);
  }

  Future<_AndroidLocationRefreshResult> _refreshAndroidLocation(
    int generation, {
    bool showDeniedDialog = false,
    bool showError = false,
  }) async {
    if (!_usesManagedAndroidLocation ||
        !mounted ||
        generation != _locationTrackingGeneration) {
      return _AndroidLocationRefreshResult.unavailable;
    }
    if (_locationRefreshInFlight) {
      return _AndroidLocationRefreshResult.unavailable;
    }
    _locationRefreshInFlight = true;
    _locationRefreshInFlightGeneration = generation;
    try {
      final position = await ref
          .read(preferredLocationServiceProvider)
          .getCurrentPosition();
      if (!mounted || generation != _locationTrackingGeneration) {
        return _AndroidLocationRefreshResult.unavailable;
      }
      _locationRetryAttempt = 0;
      _applyUserPosition(
        position,
        freshness: isUserPositionFresh(position, DateTime.now())
            ? UserLocationFreshness.current
            : UserLocationFreshness.stale,
      );
      return _AndroidLocationRefreshResult.updated;
    } on PermissionDeniedException {
      if (mounted && generation == _locationTrackingGeneration) {
        _markUserPositionStale();
        _pauseAndroidLocationTrackingForPermissionDenied(generation);
        if (showDeniedDialog) _showLocationDeniedDialog();
      }
      return _AndroidLocationRefreshResult.permissionDenied;
    } catch (error, stackTrace) {
      if (mounted && generation == _locationTrackingGeneration) {
        _markUserPositionStale();
        if (showError) {
          showErrorSnackBar(
            context,
            ref.read(l10nProvider).unknownError,
            error: error,
            stackTrace: stackTrace,
            s: ref.read(l10nProvider),
            onRetry: _goToMyLocation,
          );
        }
      }
      return _AndroidLocationRefreshResult.unavailable;
    } finally {
      if (_locationRefreshInFlightGeneration == generation) {
        _locationRefreshInFlight = false;
        _locationRefreshInFlightGeneration = null;
      }
    }
  }

  void _subscribeAndroidLocationStream(
    PreferredLocationService service,
    int generation,
  ) {
    if (!mounted || generation != _locationTrackingGeneration) return;
    _userPositionSubscription = service.watchCurrentPosition().listen(
      (position) {
        if (!mounted || generation != _locationTrackingGeneration) return;
        _locationRetryAttempt = 0;
        _applyUserPosition(position, freshness: UserLocationFreshness.current);
      },
      onError: (Object error) {
        if (!mounted || generation != _locationTrackingGeneration) return;
        _markUserPositionStale();
        unawaited(_userPositionSubscription?.cancel());
        _userPositionSubscription = null;
        if (error is PermissionDeniedException) {
          _pauseAndroidLocationTrackingForPermissionDenied(generation);
          return;
        }
        _scheduleAndroidLocationRetry(generation);
      },
      onDone: () {
        if (!mounted || generation != _locationTrackingGeneration) return;
        _markUserPositionStale();
        _userPositionSubscription = null;
        _scheduleAndroidLocationRetry(generation);
      },
      cancelOnError: true,
    );
  }

  void _scheduleAndroidLocationRetry(int generation) {
    if (!mounted ||
        generation != _locationTrackingGeneration ||
        (_locationRetryTimer?.isActive ?? false)) {
      return;
    }
    final delay = _nextAndroidLocationRetryDelay();
    _locationRetryTimer = Timer(delay, () {
      if (!mounted || generation != _locationTrackingGeneration) return;
      unawaited(_startAndroidLocationTracking(restart: true));
    });
  }

  Duration _nextAndroidLocationRetryDelay() {
    final multiplier = 1 << math.min(_locationRetryAttempt, 4);
    final seconds = math.min(
      _androidLocationRetryMaxDelay.inSeconds,
      _androidLocationRetryInitialDelay.inSeconds * multiplier,
    );
    _locationRetryAttempt++;
    return Duration(seconds: seconds);
  }

  void _pauseAndroidLocationTrackingForPermissionDenied(int generation) {
    if (generation != _locationTrackingGeneration) return;
    _androidLocationTrackingStarted = false;
    _locationRetryTimer?.cancel();
    _locationRetryTimer = null;
    unawaited(_userPositionSubscription?.cancel());
    _userPositionSubscription = null;
  }

  Future<void> _startAndroidHeadingTracking({bool restart = false}) async {
    if (!_usesManagedAndroidLocation ||
        (_headingSubscription != null && !restart)) {
      return;
    }
    await _headingSubscription?.cancel();
    _headingSubscription = ref.read(headingSourceProvider).headings.listen((
      heading,
    ) {
      if (!mounted) return;
      final nextHeading =
          _myLocationCameraMode == MyLocationCameraMode.following
          ? heading
          : smoothCircularHeading(heading, _deviceHeading);
      setState(() => _deviceHeading = nextHeading);
      unawaited(_syncFollowingCamera(durationSeconds: 0));
    }, onError: (_) {});
  }

  void _applyUserPosition(
    Position position, {
    required UserLocationFreshness freshness,
  }) {
    if (!mounted) return;
    if (!_shouldApplyUserPosition(position, freshness: freshness)) return;
    _userLocationStaleTimer?.cancel();
    final point = Point(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    setState(() {
      _userPosition = position;
      _userLocationFreshness = freshness;
    });
    if (_usesManagedAndroidLocation) {
      _animateDisplayedUserPoint(point);
    } else if (_displayedUserPoint != point) {
      setState(() => _displayedUserPoint = point);
      unawaited(_syncFollowingCamera(target: point, durationSeconds: 0));
    }
    if (freshness == UserLocationFreshness.current) {
      _lastLiveLocationAt = DateTime.now();
      if (_usesManagedAndroidLocation) {
        if (kDebugMode) {
          debugPrint(
            '[ParkTrackLocation] marker freshness=current '
            'reason=live_android_fix opacity=${userLocationMarkerOpacity(freshness)}',
          );
        }
      } else {
        _userLocationStaleTimer = Timer(
          _userLocationFreshnessDuration,
          _markUserPositionStale,
        );
      }
    }
  }

  void _animateDisplayedUserPoint(Point target) {
    final start = _displayedUserPoint;
    if (start == null) {
      setState(() => _displayedUserPoint = target);
      unawaited(_syncFollowingCamera(target: target, durationSeconds: 0.3));
      return;
    }
    if ((start.latitude - target.latitude).abs() < 0.000001 &&
        (start.longitude - target.longitude).abs() < 0.000001) {
      return;
    }
    _userLocationAnimation?.dispose();
    _userLocationAnimationStart = start;
    _userLocationAnimationEnd = target;
    _userLocationAnimation =
        AnimationController(vsync: this, duration: _userLocationMoveDuration)
          ..addListener(_tickDisplayedUserPoint)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed ||
                status == AnimationStatus.dismissed) {
              _userLocationAnimation?.dispose();
              _userLocationAnimation = null;
              _userLocationAnimationStart = null;
              _userLocationAnimationEnd = null;
            }
          })
          ..forward();
  }

  void _tickDisplayedUserPoint() {
    final animation = _userLocationAnimation;
    final start = _userLocationAnimationStart;
    final end = _userLocationAnimationEnd;
    if (animation == null || start == null || end == null || !mounted) return;
    final eased = Curves.easeInOutCubic.transform(animation.value);
    final point = interpolateMapPoint(start, end, eased);
    setState(() => _displayedUserPoint = point);
    unawaited(_syncFollowingCamera(target: point, durationSeconds: 0));
  }

  bool _shouldApplyUserPosition(
    Position position, {
    required UserLocationFreshness freshness,
  }) {
    final current = _userPosition;
    if (current == null) return true;
    if (freshness == UserLocationFreshness.current) return true;
    return position.timestamp.isAfter(current.timestamp);
  }

  void _markUserPositionStale() {
    if (!mounted ||
        _userPosition == null ||
        _userLocationFreshness == UserLocationFreshness.stale) {
      return;
    }
    final lastLiveLocationAt = _lastLiveLocationAt;
    if (lastLiveLocationAt != null) {
      final liveAge = DateTime.now().difference(lastLiveLocationAt);
      if (!liveAge.isNegative && liveAge < _userLocationFreshnessDuration) {
        _userLocationStaleTimer?.cancel();
        _userLocationStaleTimer = Timer(
          _userLocationFreshnessDuration - liveAge,
          _markUserPositionStale,
        );
        return;
      }
    }
    if (kDebugMode) {
      debugPrint(
        '[ParkTrackLocation] marker freshness=stale '
        'reason=timer_or_provider_error opacity=${userLocationMarkerOpacity(UserLocationFreshness.stale)}',
      );
    }
    setState(() => _userLocationFreshness = UserLocationFreshness.stale);
  }

  Future<void> _syncNativeUserLayer({required bool visible}) async {
    if (kIsWeb) return;
    final controller = _mapController;
    if (_usesManagedAndroidLocation) {
      if (controller != null) {
        await controller.toggleUserLayer(
          visible: false,
          headingEnabled: false,
          autoZoomEnabled: false,
        );
      }
      _nativeUserLayerVisible = false;
      return;
    }
    if (controller == null || _nativeUserLayerVisible == visible) return;
    _nativeUserLayerVisible = visible;
    await controller.toggleUserLayer(
      visible: visible,
      headingEnabled: true,
      autoZoomEnabled: false,
    );
  }

  Future<UserLocationView> _onUserLocationAdded(UserLocationView view) async {
    final marker = _userLocationMarkerBitmaps;
    if (marker == null) return view;
    return view.copyWith(
      arrow: view.arrow.copyWith(
        opacity: 1,
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(marker.arrow),
            anchor: const Offset(0.5, 0.5),
            scale: marker.scale,
            rotationType: RotationType.rotate,
          ),
        ),
      ),
      pin: view.pin.copyWith(
        opacity: 1,
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(marker.pin),
            anchor: const Offset(0.5, 0.5),
            scale: marker.scale,
          ),
        ),
      ),
      accuracyCircle: view.accuracyCircle.copyWith(
        isVisible: true,
        fillColor: userLocationAccuracyFillColor,
        strokeColor: userLocationAccuracyStrokeColor,
        strokeWidth: userLocationAccuracyStrokeWidth,
      ),
    );
  }

  double? _validUserHeading(Position? position) {
    if (position == null) return null;
    final heading = position.heading;
    if (!heading.isFinite || heading < 0) return null;
    return heading;
  }

  double? _currentUserHeading() =>
      _deviceHeading ?? _validUserHeading(_userPosition);

  Future<void> _syncFollowingCamera({
    Point? target,
    double durationSeconds = 0.25,
    double? zoom,
  }) async {
    if (_myLocationCameraMode != MyLocationCameraMode.following) return;
    final point =
        target ??
        _displayedUserPoint ??
        (_userPosition == null
            ? null
            : Point(
                latitude: _userPosition!.latitude,
                longitude: _userPosition!.longitude,
              ));
    if (point == null) return;
    final heading = _currentUserHeading();
    final azimuth = heading != null && heading.isFinite
        ? heading
        : _currentAzimuth;
    final targetZoom = zoom ?? _currentZoom;
    if (kIsWeb) {
      final margins = _getCurrentMapMargins();
      _webMapController.follow(
        point.latitude,
        point.longitude,
        targetZoom,
        azimuth,
        top: margins.top,
        right: margins.right,
        bottom: margins.bottom,
        left: margins.left,
      );
      return;
    }
    await _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: point,
          zoom: targetZoom,
          azimuth: azimuth,
          tilt: _currentTilt,
        ),
      ),
      animation: MapAnimation(duration: durationSeconds),
    );
  }

  void _resetMyLocationCameraMode() {
    if (_myLocationCameraMode == MyLocationCameraMode.free || !mounted) return;
    setState(() => _myLocationCameraMode = MyLocationCameraMode.free);
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
    CameraUpdateReason reason,
    bool cameraUpdateFinished,
  ) {
    final previousZoomBucket = parkingClusterZoomBucket(_currentZoom);
    final nextZoomBucket = parkingClusterZoomBucket(position.zoom);
    final previousAzimuth = _currentAzimuth;
    _lastCameraTarget = position.target;
    _currentZoom = position.zoom;
    _currentTilt = position.tilt;
    _currentAzimuth = position.azimuth;
    _compassAzimuth.value = position.azimuth;
    final nextLocationMode = locationCameraModeAfterMapCameraUpdate(
      mode: _myLocationCameraMode,
      userGesture: reason == CameraUpdateReason.gestures,
    );
    final showCompass =
        !isMapNorthUp(position.azimuth) ||
        (!cameraUpdateFinished && _showCompass);
    final followingAzimuthChanged =
        nextLocationMode == MyLocationCameraMode.following &&
        (position.azimuth - previousAzimuth).abs() > 0.01;
    if (previousZoomBucket != nextZoomBucket ||
        showCompass != _showCompass ||
        nextLocationMode != _myLocationCameraMode ||
        followingAzimuthChanged) {
      setState(() {
        _showCompass = showCompass;
        _myLocationCameraMode = nextLocationMode;
      });
    }
    if (!cameraUpdateFinished) {
      if (previousZoomBucket != nextZoomBucket) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 80), _fetchZones);
      }
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _fetchZones);
  }

  void _onZoneTap(Zone zone) {
    _lastZoneTapAt = DateTime.now();
    final searchState = ref.read(parkingSearchProvider);
    if (searchState.view == ParkingSearchView.routeBuilding ||
        ref.read(navigationProvider) != null) {
      return;
    }
    final searchIsActive = searchState.view != ParkingSearchView.hidden;
    if (searchIsActive) {
      if (_candidateIds.contains(zone.zoneId)) {
        _selectSearchCandidate(zone.zoneId, knownZone: zone);
        return;
      }
      ref
          .read(parkingSearchProvider.notifier)
          .hidePanel(lastViewedZoneId: zone.zoneId);
    }
    _openParkingDetails(zone);
  }

  void _onMapBackgroundTap() {
    if (shouldIgnoreMapBackgroundTap(
      lastZoneTapAt: _lastZoneTapAt,
      now: DateTime.now(),
    )) {
      return;
    }
    final search = ref.read(parkingSearchProvider);
    if (search.view == ParkingSearchView.details) {
      ref.read(parkingSearchProvider.notifier).backToResults();
      return;
    }
    if (_standaloneSelectedZone != null) {
      _closeStandaloneParkingDetails();
    }
  }

  void _closeStandaloneParkingDetails() {
    setState(() => _standaloneSelectedZone = null);
    final search = ref.read(parkingSearchProvider);
    if (search.view == ParkingSearchView.hidden &&
        search.candidates.isNotEmpty) {
      ref.read(parkingSearchProvider.notifier).backToResults();
    }
  }

  Future<void> _openParkingDetails(Zone zone) async {
    setState(() => _standaloneSelectedZone = zone);
    await _focusZone(zone);
  }

  Future<void> _openCandidateById(int zoneId) async {
    await _selectSearchCandidate(zoneId);
  }

  Future<void> _openAdjacentCandidate(int delta) async {
    final zoneId = ref.read(parkingSearchProvider.notifier).showAdjacent(delta);
    if (zoneId != null) await _selectSearchCandidate(zoneId);
  }

  Future<Zone?> _selectSearchCandidate(int zoneId, {Zone? knownZone}) async {
    if (_parkingDetailsLoading) return null;
    var zone = knownZone ?? _resultZonesById[zoneId] ?? _zonesById[zoneId];
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
        return null;
      } finally {
        if (mounted) setState(() => _parkingDetailsLoading = false);
      }
    }
    if (!mounted) return null;
    _resultZonesById[zone.zoneId] = zone;
    await _openCandidateDetails(zone);
    return zone;
  }

  Future<void> _openCandidateDetails(Zone zone) async {
    if (!ref.read(parkingSearchProvider.notifier).showDetails(zone.zoneId)) {
      return;
    }
    await _focusZone(zone);
  }

  Future<void> _focusZone(Zone zone) async {
    if (zone.geometry.isEmpty) return;
    _resetMyLocationCameraMode();
    final target = centroid(zone.geometry);
    final knownZones = _mergeResultZones(ref.read(filteredZonesProvider));
    final otherCenters = knownZones
        .where((item) => item.zoneId != zone.zoneId && item.geometry.isNotEmpty)
        .map((item) => centroid(item.geometry));
    final targetZoom = math
        .max(
          _currentZoom,
          parkingIsolationZoom(
            target,
            otherCenters,
            currentZoom: _currentZoom,
            minimumZoom: _myLocationZoom,
          ),
        )
        .clamp(_minMapZoom, _maxMapZoom)
        .toDouble();
    _queuedZoomTarget = targetZoom;
    if (kIsWeb) {
      _webMapController.focus(
        target.latitude,
        target.longitude,
        targetZoom,
        top: 88,
        right: 24,
        bottom: _detailsPanelHeight + 20,
        left: 24,
      );
      return;
    }
    await _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: targetZoom,
          azimuth: _currentAzimuth,
          tilt: _currentTilt,
        ),
      ),
      animation: const MapAnimation(duration: 0.65),
    );
    _queuedZoomTarget = null;
  }

  Future<void> _onCandidateAction(
    CandidateAction action,
    RouteCandidate candidate,
    Zone? zone,
  ) async {
    switch (action) {
      case CandidateAction.go:
        ref.read(parkingSearchProvider.notifier).startRoute(candidate.zoneId);
        await _buildRouteForZone(
          candidate.zoneId,
          candidate: candidate,
          knownZone: zone,
        );
      case CandidateAction.openExternal:
        if (zone == null || zone.geometry.isEmpty) return;
        final point = centroid(zone.geometry);
        await _openExternalMap(point.latitude, point.longitude);
    }
  }

  Future<void> _buildRouteFromSearchCard(
    Zone zone,
    RouteCandidate? candidate,
  ) async {
    ref.read(parkingSearchProvider.notifier).startRoute(zone.zoneId);
    await _buildRouteForZone(
      zone.zoneId,
      candidate: candidate,
      knownZone: zone,
    );
  }

  Future<void> _openExternalMap(double latitude, double longitude) async {
    try {
      await openYandexMapsRoute(latitude, longitude);
    } catch (error, stackTrace) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        ref.read(l10nProvider).externalMapOpenError,
        error: error,
        stackTrace: stackTrace,
        s: ref.read(l10nProvider),
      );
    }
  }

  Future<void> _shareLink(Uri uri, String title, {String? text}) async {
    try {
      await shareParkTrackLink(context, uri: uri, title: title, text: text);
    } catch (error, stackTrace) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        ref.read(l10nProvider).unknownError,
        error: error,
        stackTrace: stackTrace,
        s: ref.read(l10nProvider),
      );
    }
  }

  String _parkingShareText(Zone zone, String? address) {
    final title = '${ref.read(l10nProvider).parkingNumber}${zone.zoneId}';
    final cleanAddress = address?.trim();
    if (cleanAddress == null || cleanAddress.isEmpty) return title;
    return '$title\n$cleanAddress';
  }

  Future<void> _shareRouteLink(ActiveRoute route, Point? target) async {
    String? address;
    if (target != null) {
      try {
        address = await ref.read(
          parkingAddressProvider((
            latitude: target.latitude,
            longitude: target.longitude,
          )).future,
        );
      } catch (_) {
        address = null;
      }
    }
    if (!mounted) return;
    final s = ref.read(l10nProvider);
    final cleanAddress = address?.trim();
    final ruText = cleanAddress == null || cleanAddress.isEmpty
        ? 'Маршрут до парковки №${route.selectedZoneId}'
        : 'Маршрут до парковки №${route.selectedZoneId} ($cleanAddress)';
    final enText = cleanAddress == null || cleanAddress.isEmpty
        ? 'Route to parking #${route.selectedZoneId}'
        : 'Route to parking #${route.selectedZoneId} ($cleanAddress)';
    await _shareLink(
      routeShareUri(route.routeId),
      s.routeReady,
      text: identical(s, AppStrings.ru) ? ruText : enText,
    );
  }

  Future<void> _onClusterTap(ParkingCluster cluster) async {
    final controller = _mapController;
    if (controller == null) return;
    final camera = await controller.getCameraPosition();
    final targetZoom = parkingClusterExpansionZoom(
      _cachedMapZones ?? const [],
      cluster.zoneIds,
      camera.zoom,
    );
    await controller.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: cluster.center,
          zoom: targetZoom,
          azimuth: camera.azimuth,
          tilt: camera.tilt,
        ),
      ),
      animation: const MapAnimation(duration: 0.3),
    );
  }

  ParkingClusteringResult _clusteringFor(List<Zone> zones) {
    final zoom = parkingClusterZoomBucket(_currentZoom);
    if (!identical(_cachedClusteringZones, zones) ||
        _cachedClusteringZoom != zoom ||
        _cachedClustering == null) {
      _cachedClusteringZones = zones;
      _cachedClusteringZoom = zoom;
      _cachedClustering = clusterParkingZones(zones, zoom);
      _cachedMapZones = null;
      _cachedZoneLabels = null;
    }
    return _cachedClustering!;
  }

  Future<void> _updateClusterBitmaps(
    ParkingClusteringResult clustering, {
    required Brightness brightness,
  }) async {
    final requiredClusters = clustering.clusters
        .where((cluster) {
          final key = parkingClusterBitmapKey(cluster, brightness: brightness);
          return !_clusterLabelCache.containsKey(key) &&
              !_clusterBitmapRequests.contains(key);
        })
        .toList(growable: false);
    if (requiredClusters.isEmpty) return;
    final requestedKeys = requiredClusters
        .map(
          (cluster) => parkingClusterBitmapKey(cluster, brightness: brightness),
        )
        .toSet();
    _clusterBitmapRequests.addAll(requestedKeys);
    try {
      final entries = await Future.wait(
        requiredClusters.map((cluster) async {
          final key = parkingClusterBitmapKey(cluster, brightness: brightness);
          final bytes = await buildParkingClusterBitmap(
            cluster,
            brightness: brightness,
          );
          return MapEntry(key, bytes);
        }),
      );
      if (!mounted) return;
      setState(() {
        _clusterLabelCache.addEntries(entries);
        _cachedZoneLabels = null;
        if (_clusterLabelCache.length > 128) {
          final requiredKeys = clustering.clusters
              .map(
                (cluster) =>
                    parkingClusterBitmapKey(cluster, brightness: brightness),
              )
              .toSet();
          _clusterLabelCache.removeWhere(
            (key, _) => !requiredKeys.contains(key),
          );
        }
      });
    } finally {
      _clusterBitmapRequests.removeAll(requestedKeys);
    }
  }

  List<MapObject> _zoneObjectsFor(
    List<Zone> zones,
    Set<int> tappableZoneIds,
    Set<int> candidateIds,
    int? selectedZoneId,
    Brightness brightness,
  ) {
    if (!identical(_cachedMapZones, zones) ||
        !setEquals(_cachedTappableZoneIds, tappableZoneIds) ||
        !setEquals(_cachedCandidateIds, candidateIds) ||
        _cachedSelectedZoneId != selectedZoneId ||
        _cachedZoneObjectBrightness != brightness) {
      _cachedMapZones = zones;
      _cachedTappableZoneIds = Set.unmodifiable(tappableZoneIds);
      _cachedCandidateIds = Set.unmodifiable(candidateIds);
      _cachedSelectedZoneId = selectedZoneId;
      _cachedZoneObjectBrightness = brightness;
      _cachedZoneObjects = buildZoneMapObjects(
        zones: zones,
        tappableIds: tappableZoneIds,
        resultIds: candidateIds,
        selectedId: selectedZoneId,
        brightness: brightness,
        onTap: _onZoneTap,
      );
      _cachedZoneLabels = null;
    }
    return _cachedZoneObjects;
  }

  List<MapObject> _zoneLabelsFor(
    List<Zone> zones,
    ParkingClusteringResult clustering,
    Set<int> candidateIds,
    int? selectedZoneId,
    Brightness brightness,
  ) {
    if (_zoneLabelCache.isEmpty && clustering.clusters.isEmpty) {
      return const [];
    }
    if (_cachedZoneLabels == null ||
        !identical(_cachedMapZones, zones) ||
        !identical(_cachedLabelBitmaps, _zoneLabelCache) ||
        _cachedZoneLabelBrightness != brightness) {
      _cachedLabelBitmaps = _zoneLabelCache;
      _cachedZoneLabelBrightness = brightness;
      _cachedZoneLabels = buildZoneLabels(
        zones: zones,
        clustering: clustering,
        zoom: _currentZoom,
        bitmapCache: _zoneLabelCache,
        clusterBitmapCache: _clusterLabelCache,
        zonesById: _zonesById,
        resultIds: candidateIds,
        selectedId: selectedZoneId,
        brightness: brightness,
        onZoneTap: _onZoneTap,
        onClusterTap: _onClusterTap,
      );
    }
    return _cachedZoneLabels!;
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
      final nextBounds = (
        west: bottomLeft.longitude,
        south: bottomLeft.latitude,
        east: topRight.longitude,
        north: topRight.latitude,
      );
      if (_nativeVisibleBounds != nextBounds && mounted) {
        setState(() => _nativeVisibleBounds = nextBounds);
      }
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

  List<Zone> _zonesInsideNativeViewport(List<Zone> zones) {
    final bounds = _nativeVisibleBounds;
    if (bounds == null) return zones;
    if (identical(_cachedViewportZonesSource, zones) &&
        _cachedViewportBounds == bounds) {
      return _cachedViewportZones;
    }
    _cachedViewportZonesSource = zones;
    _cachedViewportBounds = bounds;
    _cachedViewportZones = zones;
    return _cachedViewportZones;
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
    final previousZoomBucket = parkingClusterZoomBucket(_currentZoom);
    final nextZoomBucket = parkingClusterZoomBucket(camera.zoom);
    final previousAzimuth = _currentAzimuth;
    _lastCameraTarget = Point(
      latitude: camera.latitude,
      longitude: camera.longitude,
    );
    _currentZoom = camera.zoom;
    _currentAzimuth = camera.azimuth;
    _compassAzimuth.value = camera.azimuth;
    final nextLocationMode = locationCameraModeAfterMapCameraUpdate(
      mode: _myLocationCameraMode,
      userGesture: camera.userGesture,
    );
    final showCompass =
        !isMapNorthUp(camera.azimuth) ||
        (!camera.cameraUpdateFinished && _showCompass);
    final followingAzimuthChanged =
        nextLocationMode == MyLocationCameraMode.following &&
        (camera.azimuth - previousAzimuth).abs() > 0.01;
    if (previousZoomBucket != nextZoomBucket ||
        showCompass != _showCompass ||
        nextLocationMode != _myLocationCameraMode ||
        followingAzimuthChanged) {
      setState(() {
        _showCompass = showCompass;
        _myLocationCameraMode = nextLocationMode;
      });
    }
    _debounce?.cancel();
    _debounce = Timer(
      previousZoomBucket != nextZoomBucket
          ? const Duration(milliseconds: 80)
          : const Duration(milliseconds: 400),
      () => _fetchWebZones(camera),
    );
  }

  Future<Position?> _getCurrentPosition({bool showDeniedDialog = true}) async {
    try {
      final pos = await ref
          .read(preferredLocationServiceProvider)
          .getCurrentPosition();
      _applyUserPosition(
        pos,
        freshness: isUserPositionFresh(pos, DateTime.now())
            ? UserLocationFreshness.current
            : UserLocationFreshness.stale,
      );
      return pos;
    } catch (error, stackTrace) {
      _markUserPositionStale();
      if (error is PermissionDeniedException) {
        if (showDeniedDialog) _showLocationDeniedDialog();
      } else if (showDeniedDialog && mounted) {
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

  EdgeInsets _getCurrentMapMargins() {
    final search = ref.read(parkingSearchProvider);
    final routingState = ref.read(routingProvider);
    final navState = ref.read(navigationProvider);
    final isNavigating = navState != null;

    final routePreview = routingState.maybeWhen(
      routePreview: (route) => route,
      orElse: () => null,
    );

    final searchResultsVisible =
        {
          ParkingSearchView.loading,
          ParkingSearchView.results,
          ParkingSearchView.routeBuilding,
          ParkingSearchView.error,
        }.contains(search.view) &&
        !isNavigating &&
        routePreview == null;

    final searchDetailsVisible =
        search.view == ParkingSearchView.details &&
        !isNavigating &&
        routePreview == null;

    final standaloneDetailsVisible =
        _standaloneSelectedZone != null &&
        search.view == ParkingSearchView.hidden &&
        !isNavigating &&
        routePreview == null;

    final routePreviewVisible = routePreview != null && !isNavigating;

    final bottomHeight = isNavigating
        ? 0.0
        : routePreviewVisible
        ? _routePreviewPanelHeight
        : searchResultsVisible
        ? _searchPanelHeight
        : searchDetailsVisible
        ? _detailsPanelHeight
        : standaloneDetailsVisible
        ? _detailsPanelHeight
        : 0.0;

    return EdgeInsets.only(
      top: 88, // Search bar
      bottom: bottomHeight > 0 ? bottomHeight + 20 : 0,
      left: 24,
      right: 24,
    );
  }

  Future<void> _goToMyLocation() async {
    Position? pos;
    if (_usesManagedAndroidLocation) {
      pos = _userPosition;
      if (pos != null) {
        final generation = _locationTrackingGeneration;
        if (generation == 0 || !_androidLocationTrackingStarted) {
          unawaited(_startAndroidLocationTracking(restart: true));
        }
      } else {
        if (!_androidLocationTrackingStarted) {
          await _startAndroidLocationTracking(restart: true);
          pos = _userPosition;
        }
        pos ??= await _getCurrentPosition();
      }
    } else {
      pos = await _getCurrentPosition();
    }
    if (pos == null) return;

    final margins = _getCurrentMapMargins();
    final target =
        _displayedUserPoint ??
        Point(latitude: pos.latitude, longitude: pos.longitude);
    final action = nextMyLocationButtonAction(
      mode: _myLocationCameraMode,
      currentZoom: _currentZoom,
      targetZoom: _myLocationZoom,
    );
    final nextMode = switch (action) {
      MyLocationButtonAction.centerWithoutZoom => MyLocationCameraMode.centered,
      MyLocationButtonAction.enableFollowing => MyLocationCameraMode.following,
      MyLocationButtonAction.disableFollowing => MyLocationCameraMode.centered,
      MyLocationButtonAction.disableFollowingAndZoom =>
        MyLocationCameraMode.centered,
    };
    if (mounted) setState(() => _myLocationCameraMode = nextMode);

    if (action == MyLocationButtonAction.enableFollowing) {
      if (kIsWeb) _webMapController.requestHeading();
      await _syncFollowingCamera(target: target, durationSeconds: 0);
      return;
    }

    if (kIsWeb) {
      _webMapController.focus(
        target.latitude,
        target.longitude,
        action == MyLocationButtonAction.disableFollowingAndZoom
            ? _myLocationZoom
            : _currentZoom,
        top: margins.top,
        right: margins.right,
        bottom: margins.bottom,
        left: margins.left,
      );
      return;
    }

    if (!mounted) return;

    await _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: action == MyLocationButtonAction.disableFollowingAndZoom
              ? _myLocationZoom
              : _currentZoom,
          azimuth: _currentAzimuth,
          tilt: _currentTilt,
        ),
      ),
      animation: const MapAnimation(duration: 0.8),
    );
  }

  Future<void> _resetNorth() async {
    if (kIsWeb) {
      _webMapController.resetNorth();
      return;
    }
    if (_mapController == null) return;
    final pos = await _mapController!.getCameraPosition();
    await _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: pos.target, zoom: pos.zoom, azimuth: 0, tilt: 0),
      ),
      animation: const MapAnimation(duration: 0.4),
    );
  }

  Future<void> _changeZoom(
    double delta, {
    required double durationSeconds,
  }) async {
    final baseZoom = _queuedZoomTarget ?? _currentZoom;
    final targetZoom = (baseZoom + delta).clamp(_minMapZoom, _maxMapZoom);
    if ((targetZoom - baseZoom).abs() < 0.001) return;
    _queuedZoomTarget = targetZoom;
    _currentZoom = targetZoom;
    final generation = ++_zoomMoveGeneration;
    if (_myLocationCameraMode == MyLocationCameraMode.following) {
      await _syncFollowingCamera(
        zoom: targetZoom,
        durationSeconds: durationSeconds,
      );
      if (generation == _zoomMoveGeneration) _queuedZoomTarget = null;
      return;
    }
    if (kIsWeb) {
      _webMapController.setZoom(targetZoom);
      if (generation == _zoomMoveGeneration) _queuedZoomTarget = null;
      return;
    }
    if (_mapController == null) return;
    try {
      final target = _lastCameraTarget;
      if (target == null) return;
      await _mapController!.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: targetZoom,
            azimuth: _currentAzimuth,
            tilt: _currentTilt,
          ),
        ),
        animation: MapAnimation(duration: durationSeconds),
      );
    } finally {
      if (generation == _zoomMoveGeneration) _queuedZoomTarget = null;
    }
  }

  Future<void> _zoomIn() async {
    await _changeZoom(_tapZoomStep, durationSeconds: _tapZoomDurationSeconds);
  }

  Future<void> _zoomOut() async {
    await _changeZoom(-_tapZoomStep, durationSeconds: _tapZoomDurationSeconds);
  }

  Future<void> _zoomInContinuously() async {
    await _changeZoom(_holdZoomStep, durationSeconds: _holdZoomDurationSeconds);
  }

  Future<void> _zoomOutContinuously() async {
    await _changeZoom(
      -_holdZoomStep,
      durationSeconds: _holdZoomDurationSeconds,
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
    setState(() {
      _routePolyline = null;
      _routeDurationSeconds = 0;
      _routeDistanceMeters = 0;
      _activeRouteZoneId = null;
    });
    await ref
        .read(routingProvider.notifier)
        .searchParking(originLat: origin.latitude, originLon: origin.longitude);
  }

  List<Zone> _mergeResultZones(List<Zone> zones) {
    if (_resultZonesById.isEmpty) return zones;
    final visibleIds = zones.map((zone) => zone.zoneId).toSet();
    return [
      ...zones,
      ..._resultZonesById.values.where(
        (zone) => !visibleIds.contains(zone.zoneId),
      ),
    ];
  }

  Future<void> _prepareSearchResults(
    ParkingSearchState searchState,
    List<Zone> visibleZones, {
    bool fitCamera = true,
  }) async {
    if (searchState.candidates.isEmpty) return;
    final signature = searchState.candidates
        .map((candidate) => candidate.zoneId)
        .join(',');
    final visibleById = {for (final zone in visibleZones) zone.zoneId: zone};
    for (final candidate in searchState.candidates) {
      final zone = visibleById[candidate.zoneId];
      if (zone != null) _resultZonesById[candidate.zoneId] = zone;
    }

    if (_preparedResultSignature != signature) {
      _preparedResultSignature = signature;
      _resultZonesById.removeWhere(
        (zoneId, _) => !searchState.resultZoneIds.contains(zoneId),
      );
      final missing = searchState.candidates
          .where((candidate) => !_resultZonesById.containsKey(candidate.zoneId))
          .map((candidate) => candidate.zoneId)
          .toList(growable: false);
      final loaded = await Future.wait(
        missing.map((zoneId) async {
          try {
            return await ref
                .read(zonesRepositoryProvider)
                .getZoneDetails(zoneId);
          } catch (_) {
            return null;
          }
        }),
      );
      if (!mounted || _preparedResultSignature != signature) return;
      for (final zone in loaded.whereType<Zone>()) {
        _resultZonesById[zone.zoneId] = zone;
      }
      setState(() {});
      await _updateZoneBitmaps(
        _mergeResultZones(visibleZones),
        brightness: Theme.of(context).brightness,
      );
    }
    if (fitCamera && mounted) {
      await _fitSearchResults(searchState);
    }
  }

  Future<void> _fitSearchResults(ParkingSearchState searchState) async {
    final points = <Point>[];
    for (final candidate in searchState.candidates) {
      final zone = _resultZonesById[candidate.zoneId];
      if (zone != null && zone.geometry.isNotEmpty) {
        points.add(centroid(zone.geometry));
      } else if (candidate.routePolyline?.lastOrNull case final point?) {
        points.add(point);
      }
    }
    if (points.isEmpty) return;
    if (points.length == 1) {
      final point = points.single;
      points
        ..add(
          Point(
            latitude: point.latitude - 0.001,
            longitude: point.longitude - 0.001,
          ),
        )
        ..add(
          Point(
            latitude: point.latitude + 0.001,
            longitude: point.longitude + 0.001,
          ),
        );
    }
    final bounds = calculateRouteBounds(points);
    if (bounds == null) return;
    _resetMyLocationCameraMode();
    if (kIsWeb) {
      _webMapController.fitBounds(
        bounds.south,
        bounds.west,
        bounds.north,
        bounds.east,
        top: 88,
        right: 24,
        bottom: _searchPanelHeight + 20,
        left: 24,
      );
      return;
    }
    final mediaQuery = MediaQuery.of(context);
    await _mapController?.moveCamera(
      CameraUpdate.newGeometry(
        Geometry.fromBoundingBox(bounds.boundingBox),
        focusRect: routeFocusRect(
          viewport: mediaQuery.size,
          safePadding: mediaQuery.padding,
          bottomPanelHeight: _searchPanelHeight,
          devicePixelRatio: mediaQuery.devicePixelRatio,
        ),
      ),
      animation: const MapAnimation(duration: 0.8),
    );
  }

  Future<void> _fitRoutePreview(List<Point>? polyline) async {
    final routePoints = validRoutePoints(polyline);
    final bounds = calculateRouteBounds(routePoints);
    if (bounds == null) return;
    final azimuth = calculateRouteAzimuth(polyline) ?? 0;
    _resetMyLocationCameraMode();
    if (kIsWeb) {
      _webMapController.fitBounds(
        bounds.south,
        bounds.west,
        bounds.north,
        bounds.east,
        top: 112,
        right: 32,
        bottom: _routePreviewPanelHeight + 32,
        left: 32,
        azimuth: azimuth,
      );
      return;
    }
    final mediaQuery = MediaQuery.of(context);
    final mapViewport = Size(
      math.max(1, mediaQuery.size.width - mediaQuery.padding.horizontal),
      math.max(1, mediaQuery.size.height - mediaQuery.padding.vertical),
    );
    await _mapController?.moveCamera(
      CameraUpdate.newTiltAzimuthGeometry(
        Geometry.fromPolyline(Polyline(points: routePoints)),
        azimuth: azimuth,
        focusRect: routeFocusRect(
          viewport: mapViewport,
          safePadding: EdgeInsets.zero,
          bottomPanelHeight: _routePreviewPanelHeight,
          devicePixelRatio: mediaQuery.devicePixelRatio,
        ),
      ),
      animation: const MapAnimation(duration: 0.8),
    );
  }

  Future<Zone?> _resolveRouteZone(int zoneId) async {
    final cached =
        _resultZonesById[zoneId] ??
        _zonesById[zoneId] ??
        (_standaloneSelectedZone?.zoneId == zoneId
            ? _standaloneSelectedZone
            : null);
    if (cached != null) return cached;
    try {
      return await ref.read(zonesRepositoryProvider).getZoneDetails(zoneId);
    } catch (_) {
      return null;
    }
  }

  Future<RouteGeometry?> _requestRouteGeometry(
    Point origin,
    Point target,
  ) async {
    if (kIsWeb) {
      final route = await requestYandexWebRoute(
        fromLatitude: origin.latitude,
        fromLongitude: origin.longitude,
        toLatitude: target.latitude,
        toLongitude: target.longitude,
      );
      if (route == null || route.points.length < 2) return null;
      return (
        points: route.points,
        distanceMeters: route.distanceMeters.round(),
        durationSeconds: route.durationSeconds.round(),
      );
    }
    await _drivingSession?.close();
    final request = YandexDriving.requestRoutes(
      points: [
        RequestPoint(
          point: origin,
          requestPointType: RequestPointType.wayPoint,
        ),
        RequestPoint(
          point: target,
          requestPointType: RequestPointType.wayPoint,
        ),
      ],
      drivingOptions: const DrivingOptions(routesCount: 1),
    );
    _drivingSession = request.session;
    try {
      final response = await request.result;
      final route = response.routes?.firstOrNull;
      if (route == null || route.geometry.length < 2) return null;
      return (
        points: route.geometry,
        distanceMeters: (route.metadata.weight.distance.value ?? 0).round(),
        durationSeconds: (route.metadata.weight.timeWithTraffic.value ?? 0)
            .round(),
      );
    } finally {
      await request.session.close();
      if (identical(_drivingSession, request.session)) {
        _drivingSession = null;
      }
    }
  }

  Future<void> _buildRouteForZone(
    int zoneId, {
    RouteCandidate? candidate,
    Zone? knownZone,
  }) async {
    if (mounted) setState(() => _routeBuilding = true);
    try {
      final origin = await _routingOrigin();
      if (origin == null) {
        ref.read(parkingSearchProvider.notifier).backToResults();
        return;
      }
      final zone = knownZone ?? await _resolveRouteZone(zoneId);
      if (!mounted) return;
      if (zone == null || zone.geometry.isEmpty) {
        ref.read(parkingSearchProvider.notifier).backToResults();
        showErrorSnackBar(
          context,
          ref.read(l10nProvider).pointLookupError,
          s: ref.read(l10nProvider),
        );
        return;
      }
      try {
        final candidatePolyline = candidate?.routePolyline;
        final RouteGeometry? geometry =
            candidatePolyline != null && candidatePolyline.length >= 2
            ? (
                points: candidatePolyline,
                distanceMeters:
                    parkingPolylineLengthMeters(candidatePolyline) ?? 0,
                durationSeconds: candidate?.durationFromOriginSeconds ?? 0,
              )
            : kIsWeb
            ? null
            : await _requestRouteGeometry(origin, centroid(zone.geometry));
        if (!mounted) return;
        await ref
            .read(routingProvider.notifier)
            .buildRoute(
              originLat: origin.latitude,
              originLon: origin.longitude,
              selectedZoneId: zoneId,
              routePolyline: geometry?.points,
              routeDistanceMeters: geometry?.distanceMeters,
              routeDurationSeconds: geometry?.durationSeconds,
              routeGeometryFallback: kIsWeb && geometry == null
                  ? () => _requestRouteGeometry(origin, centroid(zone.geometry))
                  : null,
            );
      } catch (error, stackTrace) {
        if (!mounted) return;
        ref.read(parkingSearchProvider.notifier).backToResults();
        showErrorSnackBar(
          context,
          ref.read(l10nProvider).errorCreatingRoute,
          error: error,
          stackTrace: stackTrace,
          s: ref.read(l10nProvider),
          onRetry: () =>
              _buildRouteForZone(zoneId, candidate: candidate, knownZone: zone),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _routeBuilding = false);
      }
    }
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
      double totalMeters = _routeDistanceMeters;

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
            initialPosition: origin,
            totalSeconds: totalSeconds,
            totalMeters: totalMeters,
            destLat: toLat,
            destLon: toLon,
            s: ref.read(l10nProvider),
          );

      await _syncNativeUserLayer(visible: false);
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
    final visibleZones = ref.watch(filteredZonesProvider);
    final zones = _mergeResultZones(visibleZones);
    final zonesAsync = ref.watch(rawZonesProvider);
    final routingState = ref.watch(routingProvider);
    final destination = ref.watch(destinationProvider);
    final navState = ref.watch(navigationProvider);
    final isNavigating = navState != null;
    final isRoutingLoading = routingState.maybeWhen(
      searching: () => true,
      orElse: () => false,
    );
    final routePreview = routingState.maybeWhen(
      routePreview: (route) => route,
      orElse: () => null,
    );
    Point? routePreviewTarget;
    if (routePreview != null) {
      final matches = zones.where(
        (zone) =>
            zone.zoneId == routePreview.selectedZoneId &&
            zone.geometry.isNotEmpty,
      );
      if (matches.isNotEmpty) {
        routePreviewTarget = centroid(matches.first.geometry);
      } else {
        final selectedCandidates = routePreview.candidates.where(
          (candidate) => candidate.zoneId == routePreview.selectedZoneId,
        );
        final candidate =
            selectedCandidates.firstOrNull ??
            routePreview.candidates.firstOrNull;
        routePreviewTarget = candidate?.routePolyline?.lastOrNull;
      }
    }

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
    ref.listen(
      filteredZonesProvider,
      (_, next) => _updateZoneBitmaps(
        _mergeResultZones(next),
        brightness: Theme.of(context).brightness,
      ),
    );

    ref.listen(parkingSearchProvider, (previous, next) {
      if (next.view == ParkingSearchView.results &&
          next.candidates.isNotEmpty) {
        final shouldFit =
            previous?.view != ParkingSearchView.results ||
            previous?.candidates != next.candidates;
        unawaited(
          _prepareSearchResults(next, visibleZones, fitCamera: shouldFit),
        );
      }
      if (next.view == ParkingSearchView.hidden &&
          previous?.view != ParkingSearchView.hidden &&
          next.candidates.isEmpty) {
        _preparedResultSignature = null;
        _resultZonesById.clear();
      }
    });

    ref.listen(navigationProvider, (prev, nav) {
      if (nav == null) {
        if (prev != null && mounted) {
          setState(() {
            _routePolyline = null;
            _routeDurationSeconds = 0;
            _routeDistanceMeters = 0;
            _activeRouteZoneId = null;
          });
        }
        unawaited(_syncNativeUserLayer(visible: true));
        return;
      }
      unawaited(_syncNativeUserLayer(visible: false));
      if (prev?.route != nav.route) {
        setState(() => _routePolyline = nav.route);
      }
      _resetMyLocationCameraMode();
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
      if (next.hasValue) {
        _lastShownZonesErrorSignature = null;
        return;
      }
      next.whenOrNull(
        error: (e, st) {
          final signature = e.toString();
          if (_lastShownZonesErrorSignature == signature) return;
          _lastShownZonesErrorSignature = signature;
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
      _resetMyLocationCameraMode();
      if (shouldDismissParkingDetailsForDestination(
        destination: dest,
        hasStandaloneParkingDetails: _standaloneSelectedZone != null,
      )) {
        setState(() => _standaloneSelectedZone = null);
      }
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
          await _syncNativeUserLayer(visible: true);
          await _mapController?.toggleTrafficLayer(visible: false);
          setState(() {
            _routePolyline = null;
            _routeDurationSeconds = 0;
            _routeDistanceMeters = 0;
            _activeRouteZoneId = null;
          });
        },
        searching: () async {},
        error: (_) async {},
        candidates: (_) async {},
        routePreview: (route) async {
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

          final polyline = route.routePolyline ?? candidate?.routePolyline;
          setState(() {
            _routePolyline = polyline;
            _routeDurationSeconds =
                route.routeDurationSeconds?.toDouble() ??
                candidate?.durationFromOriginSeconds?.toDouble() ??
                0;
            _routeDistanceMeters = route.routeDistanceMeters?.toDouble() ?? 0;
            _activeRouteZoneId = route.selectedZoneId;
            _standaloneSelectedZone = null;
          });

          if (calculateRouteBounds(polyline) != null) {
            await _fitRoutePreview(polyline);
          } else if (zoneLat != null && zoneLon != null) {
            final target = Point(latitude: zoneLat, longitude: zoneLon);
            if (kIsWeb) {
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
        },
      );
    });

    final parkingSearchState = ref.watch(parkingSearchProvider);
    final candidateIds = parkingSearchState.resultZoneIds;
    _candidateIds = candidateIds;
    final selectedSearchZoneId =
        parkingSearchState.view == ParkingSearchView.details
        ? parkingSearchState.selectedZoneId
        : null;
    final selectedMapZoneId =
        selectedSearchZoneId ?? _standaloneSelectedZone?.zoneId;
    final selectedMarkerZoneId =
        selectedMapZoneId ?? (routePreview != null ? _activeRouteZoneId : null);

    final renderedZones = kIsWeb ? zones : _zonesInsideNativeViewport(zones);
    final clustering = kIsWeb
        ? ParkingClusteringResult(
            zoom: parkingClusterZoomBucket(_currentZoom),
            clusters: const [],
            singletonIds: Set.unmodifiable(
              renderedZones.map((zone) => zone.zoneId).toSet(),
            ),
          )
        : _clusteringFor(renderedZones);
    final zoneObjects = _zoneObjectsFor(
      renderedZones,
      clustering.singletonIds,
      candidateIds,
      selectedMarkerZoneId,
      Theme.of(context).brightness,
    );
    final zoneLabels = _zoneLabelsFor(
      renderedZones,
      clustering,
      candidateIds,
      selectedMarkerZoneId,
      Theme.of(context).brightness,
    );
    final markerBrightness = Theme.of(context).brightness;
    final missingClusterBitmap = clustering.clusters.any(
      (cluster) => !_clusterLabelCache.containsKey(
        parkingClusterBitmapKey(cluster, brightness: markerBrightness),
      ),
    );
    if (missingClusterBitmap) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            _updateClusterBitmaps(clustering, brightness: markerBrightness),
          );
        }
      });
    }

    final managedAndroidPosition = _usesManagedAndroidLocation && !isNavigating
        ? _userPosition
        : null;
    final managedAndroidPoint = managedAndroidPosition == null
        ? null
        : _displayedUserPoint ??
              Point(
                latitude: managedAndroidPosition.latitude,
                longitude: managedAndroidPosition.longitude,
              );
    final managedAndroidAccuracy = managedAndroidPosition?.accuracy;
    final managedAndroidHeading =
        _myLocationCameraMode == MyLocationCameraMode.following
        ? _currentAzimuth
        : _deviceHeading ?? _validUserHeading(managedAndroidPosition) ?? 0;

    final mapObjects = <MapObject>[
      ...zoneObjects,
      if (_routePolyline != null && _routePolyline!.length >= 2)
        PolylineMapObject(
          mapId: const MapObjectId('route_polyline'),
          polyline: Polyline(points: _routePolyline!),
          strokeColor: Colors.blue,
          strokeWidth: 5,
        ),
      if (_activeRouteZoneId != null &&
          _activeRouteZoneId != selectedMarkerZoneId)
        ...buildHighlightZone(
          zones,
          _activeRouteZoneId!,
          brightness: Theme.of(context).brightness,
        ),
      ...zoneLabels,
      if (managedAndroidPoint != null &&
          managedAndroidAccuracy != null &&
          shouldShowUserLocationAccuracyCircle(
            accuracy: managedAndroidAccuracy,
            freshness: _userLocationFreshness,
          ))
        CircleMapObject(
          mapId: const MapObjectId('android_user_location_accuracy'),
          circle: Circle(
            center: managedAndroidPoint,
            radius: managedAndroidAccuracy,
          ),
          zIndex: 40,
          strokeColor: userLocationAccuracyStrokeColor,
          strokeWidth: userLocationAccuracyStrokeWidth,
          fillColor: userLocationAccuracyFillColor,
        ),
      if (managedAndroidPoint != null && _userLocationMarkerBitmaps != null)
        PlacemarkMapObject(
          mapId: const MapObjectId('android_user_location_marker'),
          point: managedAndroidPoint,
          zIndex: 50,
          opacity: userLocationMarkerOpacity(_userLocationFreshness),
          direction: managedAndroidHeading,
          icon: PlacemarkIcon.single(
            PlacemarkIconStyle(
              image: BitmapDescriptor.fromBytes(
                _userLocationMarkerBitmaps!.arrow,
              ),
              anchor: const Offset(0.5, 0.5),
              scale: _userLocationMarkerBitmaps!.scale,
              rotationType: RotationType.rotate,
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
              anchor: destinationMarkerAnchor,
              zIndex: 10,
              scale: 1.0,
            ),
          ),
        ),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bitmapBrightness = isDark ? Brightness.dark : Brightness.light;
    if (_markerBrightness != bitmapBrightness && zones.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_updateZoneBitmaps(zones, brightness: bitmapBrightness));
        }
      });
    }
    final searchResultsVisible =
        {
          ParkingSearchView.loading,
          ParkingSearchView.results,
          ParkingSearchView.routeBuilding,
          ParkingSearchView.error,
        }.contains(parkingSearchState.view) &&
        !isNavigating &&
        routePreview == null;
    final searchDetailsVisible =
        parkingSearchState.view == ParkingSearchView.details &&
        !isNavigating &&
        routePreview == null;
    final selectedCandidateIndex = parkingSearchState.candidates.indexWhere(
      (candidate) => candidate.zoneId == selectedSearchZoneId,
    );
    final selectedCandidate = selectedCandidateIndex < 0
        ? null
        : parkingSearchState.candidates[selectedCandidateIndex];
    final selectedDetailZone = selectedSearchZoneId == null
        ? null
        : zones
              .where((zone) => zone.zoneId == selectedSearchZoneId)
              .firstOrNull;
    final standaloneDetailsVisible =
        _standaloneSelectedZone != null &&
        parkingSearchState.view == ParkingSearchView.hidden &&
        !isNavigating &&
        routePreview == null;
    final resultsPanelState = switch (parkingSearchState.view) {
      ParkingSearchView.loading => ParkingResultsPanelState.loading,
      ParkingSearchView.routeBuilding => ParkingResultsPanelState.routeBuilding,
      ParkingSearchView.error => ParkingResultsPanelState.error,
      _ => ParkingResultsPanelState.results,
    };
    final mediaQuery = MediaQuery.of(context);
    final viewportHeight = mediaQuery.size.height - mediaQuery.padding.vertical;
    final viewportWidth = mediaQuery.size.width - mediaQuery.padding.horizontal;
    final maxDetailsPanelHeight = math.min(viewportHeight * 0.62, 470.0);
    final routePreviewVisible = routePreview != null && !isNavigating;
    final maxRoutePreviewPanelHeight = math.min(viewportHeight * 0.56, 390.0);
    final destinationCardVisible =
        destination != null &&
        !isNavigating &&
        !routePreviewVisible &&
        parkingSearchState.view == ParkingSearchView.hidden &&
        !standaloneDetailsVisible;
    final parkingFabVisible =
        destination == null &&
        !isNavigating &&
        !routePreviewVisible &&
        parkingSearchState.view == ParkingSearchView.hidden &&
        !standaloneDetailsVisible;
    final double mapPanelHeight = searchResultsVisible
        ? _searchPanelHeight
        : searchDetailsVisible || standaloneDetailsVisible
        ? _detailsPanelHeight
        : routePreviewVisible
        ? _routePreviewPanelHeight
        : isNavigating
        ? 86.0 + MediaQuery.paddingOf(context).bottom
        : destinationCardVisible
        ? _destinationPanelHeight
        : 0.0;
    final mapControlsBottom =
        mapPanelHeight + (parkingFabVisible ? 82.0 : 0.0) + 12;
    final showZoomControls = viewportHeight - mapControlsBottom >= 280;
    final zoomControlsBottom = resolveZoomControlsBottom(
      viewportHeight: viewportHeight,
      mapControlsBottom: mapControlsBottom,
    );
    final showLowerMapControls = shouldShowLowerMapControls(
      viewportHeight: viewportHeight,
      mapControlsBottom: mapControlsBottom,
    );
    final mapFocusMargins = EdgeInsets.only(
      top: 88,
      right: 24,
      bottom: mapPanelHeight > 0 ? mapPanelHeight + 20 : 0,
      left: 24,
    );
    final nativeFocusRect = visibleMapFocusRect(
      viewport: Size(viewportWidth, viewportHeight),
      margins: mapFocusMargins,
      devicePixelRatio: mediaQuery.devicePixelRatio,
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
                selectedZoneId: selectedMarkerZoneId,
                onZoneTap: _onZoneTap,
                onMapTap: _onMapBackgroundTap,
                route: _routePolyline,
                activeRouteZoneId: _activeRouteZoneId,
                userLatitude: isNavigating ? null : _userPosition?.latitude,
                userLongitude: isNavigating ? null : _userPosition?.longitude,
                userHeading: isNavigating
                    ? null
                    : _validUserHeading(_userPosition),
                userAccuracy: isNavigating ? null : _userPosition?.accuracy,
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
                focusRect: nativeFocusRect,
                onMapCreated: (controller) async {
                  _mapController = controller;
                  const fallback = Point(
                    latitude: 61.789114,
                    longitude: 34.359757,
                  );
                  _lastCameraTarget = fallback;
                  await (_markerBitmapsFuture ??
                      _loadMarkerBitmaps(
                        MediaQuery.devicePixelRatioOf(context),
                      ));
                  if (_usesManagedAndroidLocation) {
                    await _syncNativeUserLayer(visible: false);
                    unawaited(_startAndroidHeadingTracking());
                    unawaited(_startAndroidLocationTracking());
                  } else {
                    await _syncNativeUserLayer(visible: true);
                  }
                  await controller.moveCamera(
                    CameraUpdate.newCameraPosition(
                      const CameraPosition(target: fallback, zoom: 14),
                    ),
                  );
                  _fetchZones();
                },
                onCameraPositionChanged: _onCameraPositionChanged,
                onUserLocationAdded: _onUserLocationAdded,
                onMapTap: (_) => _onMapBackgroundTap(),
              ),
            if (searchResultsVisible)
              Positioned.fill(
                child: _BottomPanelTransition(
                  child: CandidatesSheet(
                    candidates: parkingSearchState.candidates,
                    zones: zones,
                    hasDestination: destination != null,
                    originLatitude: _userPosition?.latitude,
                    originLongitude: _userPosition?.longitude,
                    panelState: resultsPanelState,
                    lastViewedZoneId: parkingSearchState.lastViewedZoneId,
                    initialScrollOffset: parkingSearchState.scrollOffset,
                    onSelect: _openCandidateById,
                    onAction: _onCandidateAction,
                    onPanelHeightChanged: (height) {
                      if ((_searchPanelHeight - height).abs() < 1 || !mounted) {
                        return;
                      }
                      setState(() => _searchPanelHeight = height);
                    },
                    onScrollOffsetChanged: ref
                        .read(parkingSearchProvider.notifier)
                        .saveScrollOffset,
                    onClose: ref.read(routingProvider.notifier).reset,
                  ),
                ),
              ),
            if (searchDetailsVisible && selectedDetailZone != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxDetailsPanelHeight),
                  child: _PanelSizeReporter(
                    onSizeChanged: (height) {
                      if ((_detailsPanelHeight - height).abs() < 1 ||
                          !mounted) {
                        return;
                      }
                      setState(() => _detailsPanelHeight = height);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) unawaited(_focusZone(selectedDetailZone));
                      });
                    },
                    child: _BottomPanelTransition(
                      child: PointerInterceptor(
                        intercepting: kIsWeb,
                        child: ParkingCardSheet(
                          zone: selectedDetailZone,
                          candidate: selectedCandidate,
                          resultIndex: selectedCandidateIndex,
                          resultCount: parkingSearchState.candidates.length,
                          onBack: () {
                            ref
                                .read(parkingSearchProvider.notifier)
                                .backToResults();
                          },
                          onPrevious: selectedCandidateIndex > 0
                              ? () => _openAdjacentCandidate(-1)
                              : null,
                          onNext:
                              selectedCandidateIndex >= 0 &&
                                  selectedCandidateIndex <
                                      parkingSearchState.candidates.length - 1
                              ? () => _openAdjacentCandidate(1)
                              : null,
                          onBuildRoute: () => _buildRouteFromSearchCard(
                            selectedDetailZone,
                            selectedCandidate,
                          ),
                          onShare: (address) => _shareLink(
                            parkingShareUri(selectedDetailZone.zoneId),
                            '${s.parkingNumber}${selectedDetailZone.zoneId}',
                            text: _parkingShareText(
                              selectedDetailZone,
                              address,
                            ),
                          ),
                          onOpenExternal: selectedDetailZone.geometry.isEmpty
                              ? null
                              : () {
                                  final point = centroid(
                                    selectedDetailZone.geometry,
                                  );
                                  _openExternalMap(
                                    point.latitude,
                                    point.longitude,
                                  );
                                },
                          originLatitude: _userPosition?.latitude,
                          originLongitude: _userPosition?.longitude,
                          onClose: ref.read(routingProvider.notifier).reset,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (standaloneDetailsVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxDetailsPanelHeight),
                  child: _PanelSizeReporter(
                    onSizeChanged: (height) {
                      if ((_detailsPanelHeight - height).abs() < 1 ||
                          !mounted) {
                        return;
                      }
                      setState(() => _detailsPanelHeight = height);
                      final zone = _standaloneSelectedZone;
                      if (zone != null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) unawaited(_focusZone(zone));
                        });
                      }
                    },
                    child: _BottomPanelTransition(
                      child: PointerInterceptor(
                        intercepting: kIsWeb,
                        child: ParkingCardSheet(
                          zone: _standaloneSelectedZone!,
                          onBuildRoute: () => _buildRouteForZone(
                            _standaloneSelectedZone!.zoneId,
                          ),
                          onShare: (address) => _shareLink(
                            parkingShareUri(_standaloneSelectedZone!.zoneId),
                            '${s.parkingNumber}'
                            '${_standaloneSelectedZone!.zoneId}',
                            text: _parkingShareText(
                              _standaloneSelectedZone!,
                              address,
                            ),
                          ),
                          onOpenExternal:
                              _standaloneSelectedZone!.geometry.isEmpty
                              ? null
                              : () {
                                  final point = centroid(
                                    _standaloneSelectedZone!.geometry,
                                  );
                                  _openExternalMap(
                                    point.latitude,
                                    point.longitude,
                                  );
                                },
                          originLatitude: _userPosition?.latitude,
                          originLongitude: _userPosition?.longitude,
                          onClose: _closeStandaloneParkingDetails,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (routePreviewVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: maxRoutePreviewPanelHeight,
                  ),
                  child: _PanelSizeReporter(
                    onSizeChanged: (height) {
                      if ((_routePreviewPanelHeight - height).abs() < 1 ||
                          !mounted) {
                        return;
                      }
                      setState(() => _routePreviewPanelHeight = height);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          unawaited(_fitRoutePreview(_routePolyline));
                        }
                      });
                    },
                    child: _BottomPanelTransition(
                      child: PointerInterceptor(
                        intercepting: kIsWeb,
                        child: RoutePreviewSheet(
                          route: routePreview,
                          onShare: () => unawaited(
                            _shareRouteLink(routePreview, routePreviewTarget),
                          ),
                          zoneLat: routePreviewTarget?.latitude,
                          zoneLon: routePreviewTarget?.longitude,
                          onNavigateInApp: routePreviewTarget == null
                              ? null
                              : () => _startInAppNavigation(
                                  zoneId: routePreview.selectedZoneId,
                                  toLat: routePreviewTarget!.latitude,
                                  toLon: routePreviewTarget.longitude,
                                ),
                          onClose: ref.read(routingProvider.notifier).reset,
                        ),
                      ),
                    ),
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
                          icon: Icons.filter_alt_outlined,
                          tooltip: s.filters,
                          onTap: () => _showFilters(context),
                        ),
                        const SizedBox(width: 4),
                        _MapButton(
                          icon: Icons.person_outlined,
                          tooltip: s.account,
                          onTap: () => context.push('/profile'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 12,
              bottom: zoomControlsBottom,
              child: PointerInterceptor(
                intercepting: kIsWeb,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: showZoomControls
                      ? _ZoomControlGroup(
                          key: const ValueKey('zoom_controls'),
                          onZoomIn: _zoomIn,
                          onZoomOut: _zoomOut,
                          onZoomInHold: _zoomInContinuously,
                          onZoomOutHold: _zoomOutContinuously,
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('zoom_controls_hidden'),
                        ),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: mapControlsBottom,
              child: PointerInterceptor(
                intercepting: kIsWeb,
                child: IgnorePointer(
                  ignoring: !showLowerMapControls,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: showLowerMapControls
                        ? Row(
                            key: const ValueKey('lower_map_controls'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: _showCompass
                                    ? Padding(
                                        key: const ValueKey('compass_visible'),
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: ValueListenableBuilder<double>(
                                          valueListenable: _compassAzimuth,
                                          builder: (context, azimuth, _) =>
                                              MapCompassButton(
                                                azimuth: azimuth,
                                                onPressed: _resetNorth,
                                                tooltip: s.map,
                                              ),
                                        ),
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey('compass_hidden'),
                                      ),
                              ),
                              _RoundMapControl(
                                onTap: _goToMyLocation,
                                tooltip: s.myLocation,
                                child:
                                    _myLocationCameraMode ==
                                        MyLocationCameraMode.following
                                    ? const LocationFollowIcon()
                                    : Transform.rotate(
                                        angle: math.pi / 4,
                                        child: Icon(
                                          Icons.navigation_rounded,
                                          size: 26,
                                          color:
                                              _myLocationCameraMode ==
                                                  MyLocationCameraMode.centered
                                              ? const Color(0xFF1967D2)
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('lower_map_controls_hidden'),
                          ),
                  ),
                ),
              ),
            ),
            // ─── Селектор времени: всегда левый край ──────────────
            if (parkingFabVisible)
              Positioned(
                bottom: bottomInset + 20,
                left: 16,
                child: PointerInterceptor(
                  intercepting: kIsWeb,
                  child: const TimeSelectorWidget(),
                ),
              ),
            // ─── FAB: всегда правый край ───────────────────────────
            if (parkingFabVisible)
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
            if (destinationCardVisible)
              Positioned(
                bottom: bottomInset + 12,
                left: 12,
                right: 12,
                child: PointerInterceptor(
                  intercepting: kIsWeb,
                  child: _BottomPanelTransition(
                    child: _PanelSizeReporter(
                      onSizeChanged: (height) {
                        if ((_destinationPanelHeight - height).abs() < 1 ||
                            !mounted) {
                          return;
                        }
                        setState(() => _destinationPanelHeight = height);
                      },
                      child: _DestinationCard(
                        destination: destination,
                        onShare: () => _shareLink(
                          destinationShareUri(
                            latitude: destination.latitude,
                            longitude: destination.longitude,
                            name: destination.name,
                          ),
                          destination.name ?? s.selectedPlace,
                        ),
                        onFindParking: isRoutingLoading ? null : _findParking,
                        onNavigate: () => _openExternalMap(
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
                              Text(s.startingNavigation),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_parkingDetailsLoading)
              Positioned(
                top: 148,
                left: 0,
                right: 0,
                child: Center(
                  child: PointerInterceptor(
                    intercepting: kIsWeb,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(s.loadingData),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if ((isRoutingLoading || _routeBuilding) &&
                parkingSearchState.view != ParkingSearchView.loading &&
                parkingSearchState.view != ParkingSearchView.routeBuilding)
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
                            Text(
                              _routeBuilding ? s.routeBuilding : s.searching,
                            ),
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
    required this.onShare,
    required this.onFindParking,
    required this.onNavigate,
    required this.onNavigateInApp,
    required this.onClear,
  });

  final Destination destination;
  final VoidCallback onShare;
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
              IconButton(
                key: const Key('destination_share'),
                tooltip: s.share,
                onPressed: onShare,
                icon: const Icon(Icons.share_outlined, size: 20),
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
                  icon: const Icon(Icons.navigation_rounded, size: 16),
                  label: Text(s.goAction),
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 13),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onNavigate,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(s.openInYandexMaps),
                  ),
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 13),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
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

class _PanelSizeReporter extends StatefulWidget {
  const _PanelSizeReporter({required this.child, required this.onSizeChanged});

  final Widget child;
  final ValueChanged<double> onSizeChanged;

  @override
  State<_PanelSizeReporter> createState() => _PanelSizeReporterState();
}

class _PanelSizeReporterState extends State<_PanelSizeReporter> {
  double? _lastHeight;
  bool _scheduled = false;

  void _reportSize() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final height = context.size?.height;
      if (height == null || height <= 0 || height == _lastHeight) return;
      _lastHeight = height;
      widget.onSizeChanged(height);
    });
  }

  @override
  Widget build(BuildContext context) {
    _reportSize();
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _reportSize();
        return false;
      },
      child: SizeChangedLayoutNotifier(child: widget.child),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────

class _BottomPanelTransition extends StatelessWidget {
  const _BottomPanelTransition({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 240),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, (1 - value) * 18),
        child: child,
      ),
    ),
    child: child,
  );
}

// ───────────────────────────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: Icon(
              icon,
              size: 25,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(message: tooltip, child: button),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────

class _ZoomControlGroup extends StatelessWidget {
  const _ZoomControlGroup({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomInHold,
    required this.onZoomOutHold,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomInHold;
  final VoidCallback onZoomOutHold;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: mapControlSurfaceColor(context),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ZoomButton(
              icon: Icons.add_rounded,
              tooltip: '+',
              onTap: onZoomIn,
              onHoldTick: onZoomInHold,
            ),
            Divider(
              height: 1,
              indent: 10,
              endIndent: 10,
              color: mapControlDividerColor(context),
            ),
            _ZoomButton(
              icon: Icons.remove_rounded,
              tooltip: '−',
              onTap: onZoomOut,
              onHoldTick: onZoomOutHold,
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomButton extends StatefulWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.onHoldTick,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback onHoldTick;

  @override
  State<_ZoomButton> createState() => _ZoomButtonState();
}

class _ZoomButtonState extends State<_ZoomButton> {
  static const _holdStartDelay = Duration(milliseconds: 500);
  static const _holdTickInterval = Duration(milliseconds: 55);

  Timer? _holdStartTimer;
  Timer? _holdTickTimer;
  int? _activePointer;
  bool _holdActive = false;
  bool _pointerInside = false;

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _pointerInside = true;
    _holdActive = false;
    _holdStartTimer?.cancel();
    _holdStartTimer = Timer(_holdStartDelay, _startHoldTicks);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(event.position);
    final inside =
        local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx <= box.size.width &&
        local.dy <= box.size.height;
    if (!inside) _cancelPointer();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    final wasHolding = _holdActive;
    final wasInside = _pointerInside;
    _cancelPointer();
    if (!wasHolding && wasInside) widget.onTap();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _activePointer) _cancelPointer();
  }

  void _startHoldTicks() {
    if (_activePointer == null || _holdActive) return;
    _holdActive = true;
    widget.onHoldTick();
    _holdTickTimer = Timer.periodic(
      _holdTickInterval,
      (_) => widget.onHoldTick(),
    );
  }

  void _cancelPointer() {
    _holdStartTimer?.cancel();
    _holdStartTimer = null;
    _holdTickTimer?.cancel();
    _holdTickTimer = null;
    _activePointer = null;
    _holdActive = false;
    _pointerInside = false;
  }

  @override
  void dispose() {
    _cancelPointer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.tooltip,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: SizedBox(
        width: 52,
        height: 48,
        child: Icon(
          widget.icon,
          size: 27,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ),
  );
}

class _RoundMapControl extends StatelessWidget {
  const _RoundMapControl({
    required this.onTap,
    required this.tooltip,
    required this.child,
  });

  final VoidCallback onTap;
  final String tooltip;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: mapControlSurfaceColor(context),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.22),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(dimension: 52, child: Center(child: child)),
        ),
      ),
    ),
  );
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
