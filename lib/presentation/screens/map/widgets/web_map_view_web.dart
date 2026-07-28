import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../domain/models/zone.dart';
import 'parking_zone_layer.dart';
import 'web_map_types.dart';

@JS('parkTrackYandexMaps.create')
external void _createYandexMap(
  web.HTMLElement element,
  JSString locale,
  JSString theme,
  JSFunction cameraCallback,
  JSFunction zoneTapCallback,
  JSFunction mapTapCallback,
  JSFunction errorCallback,
);

@JS('parkTrackYandexMaps.update')
external void _updateYandexMap(JSString elementId, JSString stateJson);

@JS('parkTrackYandexMaps.updatePosition')
external void _updateYandexMapPosition(
  JSString elementId,
  JSString positionJson,
);

@JS('parkTrackYandexMaps.move')
external void _moveYandexMap(
  JSString elementId,
  JSNumber latitude,
  JSNumber longitude,
  JSNumber zoom,
);

@JS('parkTrackYandexMaps.setZoom')
external void _setYandexMapZoom(JSString elementId, JSNumber zoom);

@JS('parkTrackYandexMaps.retry')
external void _retryYandexMap(JSString elementId);

@JS('parkTrackYandexMaps.resetNorth')
external void _resetNorthYandexMap(JSString elementId);

@JS('parkTrackYandexMaps.requestHeading')
external void _requestYandexMapHeading(JSString elementId);

@JS('parkTrackYandexMaps.fitBounds')
external void _fitYandexMapBounds(
  JSString elementId,
  JSNumber south,
  JSNumber west,
  JSNumber north,
  JSNumber east,
  JSNumber top,
  JSNumber right,
  JSNumber bottom,
  JSNumber left,
);

@JS('parkTrackYandexMaps.focus')
external void _focusYandexMap(
  JSString elementId,
  JSNumber latitude,
  JSNumber longitude,
  JSNumber zoom,
  JSNumber top,
  JSNumber right,
  JSNumber bottom,
  JSNumber left,
);

@JS('parkTrackYandexMaps.destroy')
external void _destroyYandexMap(JSString elementId);

class WebMapView extends StatefulWidget {
  const WebMapView({
    super.key,
    required this.controller,
    required this.zones,
    required this.candidateIds,
    this.selectedZoneId,
    required this.onZoneTap,
    required this.onMapTap,
    required this.onCameraChanged,
    required this.onMapReady,
    required this.onError,
    this.route,
    this.activeRouteZoneId,
    this.userLatitude,
    this.userLongitude,
    this.userHeading,
    this.navigationLatitude,
    this.navigationLongitude,
    this.navigationHeading,
    this.destinationLatitude,
    this.destinationLongitude,
  });

  final WebMapController controller;
  final List<Zone> zones;
  final Set<int> candidateIds;
  final int? selectedZoneId;
  final void Function(Zone zone) onZoneTap;
  final VoidCallback onMapTap;
  final void Function(WebMapCamera camera) onCameraChanged;
  final VoidCallback onMapReady;
  final void Function(Object error) onError;
  final List<Point>? route;
  final int? activeRouteZoneId;
  final double? userLatitude;
  final double? userLongitude;
  final double? userHeading;
  final double? navigationLatitude;
  final double? navigationLongitude;
  final double? navigationHeading;
  final double? destinationLatitude;
  final double? destinationLongitude;

  @override
  State<WebMapView> createState() => _WebMapViewState();
}

class _WebMapViewState extends State<WebMapView> {
  late final String _elementId =
      'parktrack-yandex-map-${identityHashCode(this)}';
  late final String _viewType = 'parktrack-yandex-map-view-$_elementId';
  web.ResizeObserver? _attachmentObserver;
  bool _created = false;
  List<Zone>? _serializedZonesSource;
  Set<int> _serializedCandidateIds = const {};
  int? _serializedSelectedZoneId;
  int? _serializedActiveRouteZoneId;
  Brightness? _serializedBrightness;
  List<Map<String, Object?>> _serializedZones = const [];
  List<Point>? _serializedRouteSource;
  List<List<double>>? _serializedRoute;
  Map<int, Zone> _zonesById = const {};
  String? _lastStateJson;
  String? _lastPositionJson;

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final element = web.HTMLDivElement()..id = _elementId;
      element.style
        ..width = '100%'
        ..height = '100%'
        ..minWidth = '1px'
        ..minHeight = '1px';

      final observer = web.ResizeObserver(
        ((
              JSArray<web.ResizeObserverEntry> entries,
              web.ResizeObserver observer,
            ) {
              if (!element.isConnected || !mounted) return;
              final bounds = element.getBoundingClientRect();
              if (bounds.width <= 0 || bounds.height <= 0) return;
              observer.disconnect();
              _attachmentObserver = null;
              _initializeMap(element);
            })
            .toJS,
      );
      _attachmentObserver = observer;
      observer.observe(element);
      return element;
    });
  }

  @override
  void didUpdateWidget(covariant WebMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_created) return;
    if (_hasStructuralChanges(oldWidget)) {
      _updateMap();
    } else if (_hasPositionChanges(oldWidget)) {
      _updatePosition();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_created) _updateMap();
  }

  bool _hasStructuralChanges(WebMapView oldWidget) {
    return !identical(oldWidget.zones, widget.zones) ||
        !setEquals(oldWidget.candidateIds, widget.candidateIds) ||
        oldWidget.selectedZoneId != widget.selectedZoneId ||
        oldWidget.activeRouteZoneId != widget.activeRouteZoneId ||
        !identical(oldWidget.route, widget.route);
  }

  bool _hasPositionChanges(WebMapView oldWidget) {
    return oldWidget.userLatitude != widget.userLatitude ||
        oldWidget.userLongitude != widget.userLongitude ||
        oldWidget.userHeading != widget.userHeading ||
        oldWidget.navigationLatitude != widget.navigationLatitude ||
        oldWidget.navigationLongitude != widget.navigationLongitude ||
        oldWidget.navigationHeading != widget.navigationHeading ||
        oldWidget.destinationLatitude != widget.destinationLatitude ||
        oldWidget.destinationLongitude != widget.destinationLongitude;
  }

  void _initializeMap(web.HTMLElement element) {
    if (_created) return;
    _created = true;
    widget.controller.moveHandler = (latitude, longitude, zoom) {
      _moveYandexMap(_elementId.toJS, latitude.toJS, longitude.toJS, zoom.toJS);
    };
    widget.controller.zoomHandler = (zoom) {
      _setYandexMapZoom(_elementId.toJS, zoom.toJS);
    };
    widget.controller.fitBoundsWithInsetsHandler =
        (south, west, north, east, top, right, bottom, left) {
          _fitYandexMapBounds(
            _elementId.toJS,
            south.toJS,
            west.toJS,
            north.toJS,
            east.toJS,
            top.toJS,
            right.toJS,
            bottom.toJS,
            left.toJS,
          );
        };
    widget.controller.focusHandler =
        (latitude, longitude, zoom, top, right, bottom, left) {
          _focusYandexMap(
            _elementId.toJS,
            latitude.toJS,
            longitude.toJS,
            zoom.toJS,
            top.toJS,
            right.toJS,
            bottom.toJS,
            left.toJS,
          );
        };
    widget.controller.retryHandler = () {
      _retryYandexMap(_elementId.toJS);
    };
    widget.controller.resetNorthHandler = () {
      _resetNorthYandexMap(_elementId.toJS);
    };
    widget.controller.requestHeadingHandler = () {
      _requestYandexMapHeading(_elementId.toJS);
    };

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.localeOf(context).languageCode == 'ru'
        ? 'ru_RU'
        : 'en_RU';

    _createYandexMap(
      element,
      locale.toJS,
      (isDark ? 'dark' : 'light').toJS,
      ((JSString value) {
        final data = jsonDecode(value.toDart) as Map<String, dynamic>;
        final camera = WebMapCamera(
          latitude: (data['latitude'] as num).toDouble(),
          longitude: (data['longitude'] as num).toDouble(),
          zoom: (data['zoom'] as num).toDouble(),
          west: (data['west'] as num).toDouble(),
          south: (data['south'] as num).toDouble(),
          east: (data['east'] as num).toDouble(),
          north: (data['north'] as num).toDouble(),
          azimuth: (data['azimuth'] as num?)?.toDouble() ?? 0,
        );
        final firstCamera = !widget.controller.isReady;
        widget.controller.camera = camera;
        widget.onCameraChanged(camera);
        if (firstCamera) widget.onMapReady();
      }).toJS,
      ((JSNumber zoneId) {
        final zone = _zonesById[zoneId.toDartInt];
        if (zone != null) widget.onZoneTap(zone);
      }).toJS,
      (() => widget.onMapTap()).toJS,
      ((JSString error) {
        debugPrint('Yandex Maps Error: ${error.toDart}');
        widget.onError(error.toDart);
      }).toJS,
    );
    _updateMap();
  }

  void _updateMap() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.localeOf(context).languageCode == 'ru'
        ? 'ru_RU'
        : 'en_RU';

    final position = _positionState();
    final state = <String, Object?>{
      'theme': isDark ? 'dark' : 'light',
      'locale': locale,
      'zones': _zoneState(),
      'route': _routeState(),
      ...position,
    };
    final stateJson = jsonEncode(state);
    if (stateJson == _lastStateJson) return;
    _lastStateJson = stateJson;
    _lastPositionJson = jsonEncode(position);
    _updateYandexMap(_elementId.toJS, stateJson.toJS);
  }

  void _updatePosition() {
    final positionJson = jsonEncode(_positionState());
    if (positionJson == _lastPositionJson) return;
    _lastPositionJson = positionJson;
    _updateYandexMapPosition(_elementId.toJS, positionJson.toJS);
  }

  Map<String, Object?> _positionState() => {
    'user': widget.userLatitude != null && widget.userLongitude != null
        ? [widget.userLatitude, widget.userLongitude, widget.userHeading ?? 0]
        : null,
    'navigation':
        widget.navigationLatitude != null && widget.navigationLongitude != null
        ? [
            widget.navigationLatitude,
            widget.navigationLongitude,
            widget.navigationHeading ?? 0,
          ]
        : null,
    'destination':
        widget.destinationLatitude != null &&
            widget.destinationLongitude != null
        ? [widget.destinationLatitude, widget.destinationLongitude]
        : null,
  };

  List<Map<String, Object?>> _zoneState() {
    final brightness = Theme.of(context).brightness;
    if (identical(_serializedZonesSource, widget.zones) &&
        setEquals(_serializedCandidateIds, widget.candidateIds) &&
        _serializedSelectedZoneId == widget.selectedZoneId &&
        _serializedActiveRouteZoneId == widget.activeRouteZoneId &&
        _serializedBrightness == brightness) {
      return _serializedZones;
    }

    _serializedZonesSource = widget.zones;
    _serializedCandidateIds = Set.unmodifiable(widget.candidateIds);
    _serializedSelectedZoneId = widget.selectedZoneId;
    _serializedActiveRouteZoneId = widget.activeRouteZoneId;
    _serializedBrightness = brightness;
    _zonesById = {for (final zone in widget.zones) zone.zoneId: zone};
    final markerState = resolveParkingMarkerState(
      allIds: _zonesById.keys.toSet(),
      resultIds: widget.candidateIds,
      selectedId: widget.selectedZoneId,
    );
    _serializedZones = widget.zones
        .where(isParkingZoneRenderable)
        .map((zone) {
          final colors = parkingZoneColors(zone, brightness: brightness);
          final center = centroid(zone.geometry);
          final isCandidate = widget.candidateIds.contains(zone.zoneId);
          final isSelected = widget.selectedZoneId == zone.zoneId;
          final isDimmed = !markerState.activeIds.contains(zone.zoneId);
          final displayedColors = isDimmed ? colors.dimmed() : colors;
          final clusterFull = parkingClusterColor(0, brightness: brightness);
          final clusterOne = parkingClusterColor(1, brightness: brightness);
          final clusterFree = parkingClusterColor(3, brightness: brightness);
          return <String, Object?>{
            'id': zone.zoneId,
            'type': zone.zoneType == ZoneType.parallel ? 'line' : 'polygon',
            'points': zone.geometry
                .map((point) => [point.latitude, point.longitude])
                .toList(growable: false),
            'fill': _cssColor(displayedColors.fill),
            'stroke': _cssColor(displayedColors.stroke),
            'freeCount': zone.freeCount,
            'label': zone.freeCount,
            'isActive': zone.isActive,
            'candidate': isCandidate,
            'active': widget.activeRouteZoneId == zone.zoneId || isSelected,
            'markerOpacity': isDimmed ? parkingCounterDimmedOpacity : 1.0,
            'markerTextColor': brightness == Brightness.dark
                ? '#09090b'
                : '#ffffff',
            'clusterFull': _cssColor(clusterFull),
            'clusterOne': _cssColor(clusterOne),
            'clusterFree': _cssColor(clusterFree),
            'center': [center.latitude, center.longitude],
          };
        })
        .toList(growable: false);
    return _serializedZones;
  }

  String _cssColor(Color color) {
    final value = color.toARGB32();
    final alpha = (value >>> 24).toRadixString(16).padLeft(2, '0');
    final rgb = (value & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '#$rgb$alpha';
  }

  List<List<double>>? _routeState() {
    if (identical(_serializedRouteSource, widget.route)) {
      return _serializedRoute;
    }
    _serializedRouteSource = widget.route;
    _serializedRoute = widget.route
        ?.map((point) => [point.latitude, point.longitude])
        .toList(growable: false);
    return _serializedRoute;
  }

  @override
  void dispose() {
    _attachmentObserver?.disconnect();
    _attachmentObserver = null;
    if (_created) _destroyYandexMap(_elementId.toJS);
    widget.controller.clear();
    _zonesById = const {};
    _lastStateJson = null;
    _lastPositionJson = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
