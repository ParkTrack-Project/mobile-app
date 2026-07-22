import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../domain/models/zone.dart';
import 'parking_zone_layer.dart';
import 'web_map_types.dart';

@JS('parkTrackYandexMaps.create')
external void _createYandexMap(
  JSString elementId,
  JSString locale,
  JSString theme,
  JSFunction cameraCallback,
  JSFunction zoneTapCallback,
  JSFunction errorCallback,
);

@JS('parkTrackYandexMaps.update')
external void _updateYandexMap(JSString elementId, JSString stateJson);

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

@JS('parkTrackYandexMaps.destroy')
external void _destroyYandexMap(JSString elementId);

class WebMapView extends StatefulWidget {
  const WebMapView({
    super.key,
    required this.controller,
    required this.zones,
    required this.candidateIds,
    required this.onZoneTap,
    required this.onCameraChanged,
    required this.onMapReady,
    this.route,
    this.activeRouteZoneId,
    this.userLatitude,
    this.userLongitude,
    this.navigationLatitude,
    this.navigationLongitude,
    this.navigationHeading,
    this.destinationLatitude,
    this.destinationLongitude,
  });

  final WebMapController controller;
  final List<Zone> zones;
  final Set<int> candidateIds;
  final void Function(Zone zone) onZoneTap;
  final void Function(WebMapCamera camera) onCameraChanged;
  final VoidCallback onMapReady;
  final List<Point>? route;
  final int? activeRouteZoneId;
  final double? userLatitude;
  final double? userLongitude;
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
              _initializeMap();
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
    if (_created) _updateMap();
  }

  void _initializeMap() {
    if (_created) return;
    _created = true;
    widget.controller.moveHandler = (latitude, longitude, zoom) {
      _moveYandexMap(_elementId.toJS, latitude.toJS, longitude.toJS, zoom.toJS);
    };
    widget.controller.zoomHandler = (zoom) {
      _setYandexMapZoom(_elementId.toJS, zoom.toJS);
    };
    widget.controller.retryHandler = () {
      _retryYandexMap(_elementId.toJS);
    };

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.localeOf(context).languageCode == 'ru' ? 'ru_RU' : 'en_RU';

    _createYandexMap(
      _elementId.toJS,
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
        );
        final firstCamera = !widget.controller.isReady;
        widget.controller.camera = camera;
        widget.onCameraChanged(camera);
        if (firstCamera) widget.onMapReady();
      }).toJS,
      ((JSNumber zoneId) {
        final id = zoneId.toDartInt;
        for (final zone in widget.zones) {
          if (zone.zoneId == id) {
            widget.onZoneTap(zone);
            break;
          }
        }
      }).toJS,
      ((JSString error) {
        debugPrint('Yandex Maps Error: ${error.toDart}');
      }).toJS,
    );
    _updateMap();
  }

  void _updateMap() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.localeOf(context).languageCode == 'ru' ? 'ru_RU' : 'en_RU';

    final state = <String, Object?>{
      'theme': isDark ? 'dark' : 'light',
      'locale': locale,
      'zones': widget.zones
// ... (rest is same)
          .map((zone) {
            final color = zoneColor(zone);
            return <String, Object?>{
              'id': zone.zoneId,
              'type': zone.zoneType == ZoneType.parallel ? 'line' : 'polygon',
              'points': zone.geometry
                  .map((point) => [point.latitude, point.longitude])
                  .toList(growable: false),
              'color':
                  '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
              'freeCount': zone.freeCount,
              'label': color == AppColors.parkingUnknown
                  ? null
                  : zone.freeCount,
              'hasForecast': zone.hasForecast,
              'candidate': widget.candidateIds.contains(zone.zoneId),
              'active': widget.activeRouteZoneId == zone.zoneId,
              'center': () {
                final point = centroid(zone.geometry);
                return [point.latitude, point.longitude];
              }(),
            };
          })
          .toList(growable: false),
      'route': widget.route
          ?.map((point) => [point.latitude, point.longitude])
          .toList(growable: false),
      'user': widget.userLatitude != null && widget.userLongitude != null
          ? [widget.userLatitude, widget.userLongitude]
          : null,
      'navigation':
          widget.navigationLatitude != null &&
              widget.navigationLongitude != null
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
    _updateYandexMap(_elementId.toJS, jsonEncode(state).toJS);
  }

  @override
  void dispose() {
    _attachmentObserver?.disconnect();
    _attachmentObserver = null;
    if (_created) _destroyYandexMap(_elementId.toJS);
    widget.controller.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
