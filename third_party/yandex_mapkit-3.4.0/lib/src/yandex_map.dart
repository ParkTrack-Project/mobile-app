part of yandex_mapkit;

/// Android specific settings for [YandexMap].
class AndroidYandexMap {
  /// Whether to render [YandexMap] with a [AndroidViewSurface] to build the Google Maps widget.
  ///
  /// This implementation uses hybrid composition to render the YandexMap Widget on Android.
  /// This comes at the cost of some performance on Android versions below 10.
  /// See https://flutter.dev/docs/development/platform-integration/platform-views#performance for more information.
  ///
  /// Defaults to true.
  static bool useAndroidViewSurface = true;
}

/// A widget which displays a map using Yandex maps service.
class YandexMap extends StatefulWidget {
  /// A `Widget` for displaying Yandex Map
  const YandexMap({
    Key? key,
    this.gestureRecognizers = const <Factory<OneSequenceGestureRecognizer>>{},
    this.mapObjects = const [],
    this.liveMapObjectsListenable,
    this.liveMapObjectsBuilder,
    this.tiltGesturesEnabled = true,
    this.zoomGesturesEnabled = true,
    this.rotateGesturesEnabled = true,
    this.scrollGesturesEnabled = true,
    this.nightModeEnabled = false,
    this.fastTapEnabled = false,
    this.mode2DEnabled = false,
    this.logoAlignment = const MapAlignment(horizontal: HorizontalAlignment.right, vertical: VerticalAlignment.bottom),
    this.focusRect,
    this.onMapCreated,
    this.onMapTap,
    this.onMapLongTap,
    this.onUserLocationAdded,
    this.onCameraPositionChanged,
    this.onTrafficChanged,
    this.mapType = MapType.vector,
    this.poiLimit,
    this.onObjectTap
  }) : super(key: key);

  static const String _viewType = 'yandex_mapkit/yandex_map';

  /// Which gestures should be consumed by the map.
  ///
  /// When this set is empty, the map will only handle pointer events for gestures that
  /// were not claimed by any other gesture recognizer.
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;

  /// Map objects to show on map
  final List<MapObject> mapObjects;

  /// A signal that a small, frequently changing set of map objects should be
  /// synchronized without rebuilding the platform view widget.
  final Listenable? liveMapObjectsListenable;

  /// Builds the frequently changing map objects when
  /// [liveMapObjectsListenable] notifies its listeners.
  final List<MapObject> Function()? liveMapObjectsBuilder;

  /// Enable tilt gestures, such as parallel pan with two fingers.
  final bool tiltGesturesEnabled;

  /// Enable rotation gestures, such as rotation with two fingers.
  final bool zoomGesturesEnabled;

  /// Enable rotation gestures, such as rotation with two fingers.
  final bool rotateGesturesEnabled;

  /// Enable/disable zoom gestures, for example: - pinch - double tap (zoom in) - tap with two fingers (zoom out)
  final bool nightModeEnabled;

  /// Enable scroll gestures, such as the pan gesture.
  final bool scrollGesturesEnabled;

  /// Enable removes the 300 ms delay in emitting a tap gesture.
  /// However, a double-tap will emit a tap gesture along with a double-tap.
  final bool fastTapEnabled;

  /// Forces the map to be flat.
  ///
  /// true - All loaded tiles start showing the "flatten out" animation; all new tiles do not start 3D animation.
  /// false - All tiles start showing the "rise up" animation.
  final bool mode2DEnabled;

  /// Set logo alignment on the map
  final MapAlignment logoAlignment;

  /// Allows to set map focus to a certain rectangle instead of the whole map
  /// For more info refer to https://yandex.com/dev/maps/mapkit/doc/ios-ref/full/Classes/YMKMapWindow.html#focusRect
  final ScreenRect? focusRect;

  /// Callback method for when the map is ready to be used.
  ///
  /// Pass to [YandexMap.onMapCreated] to receive a [YandexMapController] when the
  /// map is created.
  final MapCreatedCallback? onMapCreated;

  /// Called every time a [YandexMap] is tapped.
  final ArgumentCallback<Point>? onMapTap;

  /// Called every time a [YandexMap] is long tapped.
  final ArgumentCallback<Point>? onMapLongTap;

  /// Called every time when the camera position on [YandexMap] is changed.
  final CameraPositionCallback? onCameraPositionChanged;

  /// Callback to be called when a user location layer icon elements have been added to [YandexMap].
  ///
  /// Use this method if you want to change how users current position is displayed
  /// You can return [UserLocationView] with changed [UserLocationView.pin], [UserLocationView.arrow],
  /// [UserLocationView.accuracyCircle] to change how it is shown on the map.
  ///
  /// This is called only once when the layer is made visible for the first time
  final UserLocationCallback? onUserLocationAdded;

  /// Callback to be called where a change has occured in traffic layer.
  final TrafficChangedCallback? onTrafficChanged;

  /// Sets the base map type.
  final MapType mapType;

  /// Limits the number of visible basemap POIs
  final int? poiLimit;

  /// Called every time a [YandexMap] geo object is tapped.
  final ObjectTapCallback? onObjectTap;

  @override
  // ignore: library_private_types_in_public_api
  _YandexMapState createState() => _YandexMapState();
}

class _YandexMapState extends State<YandexMap> {
  late _YandexMapOptions _yandexMapOptions;
  List<MapObject> _liveMapObjects = const [];
  MapObjectCollection? _creationMapObjectCollection;

  /// Root object which contains all [MapObject] which were added to the map by user
  MapObjectCollection _mapObjectCollection = MapObjectCollection(
    mapId: const MapObjectId('root_map_object_collection'),
    mapObjects: const []
  );

  /// All [MapObject] which were created natively
  ///
  /// This mainly refers to objects that can't be created by normal means
  /// Cluster placemarks, user location objects, etc.
  final List<MapObject> _nonRootMapObjects = [];

  /// All visible [MapObject]
  ///
  /// This contains all objects that were created by any means
  List<MapObject> get _allMapObjects => _mapObjectCollection.mapObjects + _nonRootMapObjects;

  final Completer<YandexMapController> _controller = Completer<YandexMapController>();

  @override
  void initState() {
    super.initState();
    _yandexMapOptions = _YandexMapOptions.fromWidget(widget);
    _liveMapObjects = _buildLiveMapObjects();
    _mapObjectCollection = _mapObjectCollection.copyWith(
      mapObjects: <MapObject>[...widget.mapObjects, ..._liveMapObjects]
    );
    widget.liveMapObjectsListenable?.addListener(_updateLiveMapObjects);
  }

  @override
  void dispose() async {
    widget.liveMapObjectsListenable?.removeListener(_updateLiveMapObjects);
    super.dispose();
    final controller = await _controller.future;

    controller.dispose();
  }

  @override
  void didUpdateWidget(YandexMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liveMapObjectsListenable != widget.liveMapObjectsListenable) {
      oldWidget.liveMapObjectsListenable?.removeListener(_updateLiveMapObjects);
      widget.liveMapObjectsListenable?.addListener(_updateLiveMapObjects);
    }
    _updateMapOptions();
    _updateMapObjects();
  }

  void _updateMapOptions() async {
    final newOptions = _YandexMapOptions.fromWidget(widget);
    final updates = _yandexMapOptions.mapUpdates(newOptions);

    if (updates.isEmpty) {
      return;
    }

    final controller = await _controller.future;

    // ignore: unawaited_futures
    controller._updateMapOptions(updates);
    _yandexMapOptions = newOptions;
  }

  void _updateMapObjects() async {
    final updatedLiveMapObjects = _buildLiveMapObjects();
    final updatedMapObjectCollection = _mapObjectCollection.copyWith(
      mapObjects: <MapObject>[...widget.mapObjects, ...updatedLiveMapObjects]
    );
    final updates = MapObjectUpdates.from({_mapObjectCollection}, {updatedMapObjectCollection});
    _liveMapObjects = updatedLiveMapObjects;
    _mapObjectCollection = updatedMapObjectCollection;

    if (!_hasChanges(updates) || !_controller.isCompleted) {
      return;
    }

    final controller = await _controller.future;

    // ignore: unawaited_futures
    controller._updateMapObjects(updates.toJson());
  }

  List<MapObject> _buildLiveMapObjects() {
    return List<MapObject>.unmodifiable(
      widget.liveMapObjectsBuilder?.call() ?? const <MapObject>[]
    );
  }

  void _updateLiveMapObjects() async {
    final updatedLiveMapObjects = _buildLiveMapObjects();
    final updates = MapObjectUpdates<MapObject>.from(
      _liveMapObjects.toSet(),
      updatedLiveMapObjects.toSet()
    );
    _liveMapObjects = updatedLiveMapObjects;
    _mapObjectCollection = _mapObjectCollection.copyWith(
      mapObjects: <MapObject>[...widget.mapObjects, ..._liveMapObjects]
    );

    if (!_hasChanges(updates) || !_controller.isCompleted) {
      return;
    }

    final controller = await _controller.future;

    // ignore: unawaited_futures
    controller._updateMapObjects(_wrapRootMapObjectUpdates(updates));
  }

  bool _hasChanges<T extends MapObject>(MapObjectUpdates<T> updates) {
    return updates.objectsToAdd.isNotEmpty ||
      updates.objectsToChange.isNotEmpty ||
      updates.objectsToRemove.isNotEmpty;
  }

  Map<String, dynamic> _wrapRootMapObjectUpdates(MapObjectUpdates updates) {
    return <String, dynamic>{
      'toAdd': const <Map<String, dynamic>>[],
      'toChange': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': _mapObjectCollection.mapId.value,
          'type': MapObjectCollection._kType,
          'mapObjects': updates.toJson(),
          'zIndex': _mapObjectCollection.zIndex,
          'consumeTapEvents': _mapObjectCollection.consumeTapEvents,
          'isVisible': _mapObjectCollection.isVisible
        }
      ],
      'toRemove': const <Map<String, dynamic>>[]
    };
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (AndroidYandexMap.useAndroidViewSurface) {
        return PlatformViewLink(
          viewType: YandexMap._viewType,
          surfaceFactory: (BuildContext context, PlatformViewController controller) {
            return AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers: widget.gestureRecognizers,
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            );
          },
          onCreatePlatformView: (PlatformViewCreationParams params) {
            return PlatformViewsService.initExpensiveAndroidView(
              id: params.id,
              viewType: YandexMap._viewType,
              layoutDirection: TextDirection.ltr,
              creationParams: _creationParams(),
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () => params.onFocusChanged(true),
            )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
            ..create();
          }
        );
      } else {
        return AndroidView(
          viewType: YandexMap._viewType,
          onPlatformViewCreated: _onPlatformViewCreated,
          gestureRecognizers: widget.gestureRecognizers,
          creationParamsCodec: const StandardMessageCodec(),
          creationParams: _creationParams(),
        );
      }
    } else {
      return UiKitView(
        viewType: YandexMap._viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: widget.gestureRecognizers,
        creationParamsCodec: const StandardMessageCodec(),
        creationParams: _creationParams(),
      );
    }
  }

  Future<void> _onPlatformViewCreated(int id) async {
    final controller = await YandexMapController._init(id, this);

    _controller.complete(controller);

    final creationMapObjectCollection = _creationMapObjectCollection;
    if (creationMapObjectCollection != null &&
        creationMapObjectCollection != _mapObjectCollection) {
      final updates = MapObjectUpdates.from(
        {creationMapObjectCollection},
        {_mapObjectCollection}
      );
      if (_hasChanges(updates)) {
        // ignore: unawaited_futures
        controller._updateMapObjects(updates.toJson());
      }
    }

    if (widget.onMapCreated != null) {
      widget.onMapCreated!(controller);
    }
  }

  Map<String, dynamic> _creationParams() {
    _liveMapObjects = _buildLiveMapObjects();
    _mapObjectCollection = _mapObjectCollection.copyWith(
      mapObjects: <MapObject>[...widget.mapObjects, ..._liveMapObjects]
    );
    _creationMapObjectCollection = _mapObjectCollection;
    final mapOptions = _yandexMapOptions.toJson();
    final mapObjects = MapObjectUpdates.from(
      {_mapObjectCollection.copyWith(mapObjects: [])},
      {_mapObjectCollection}
    ).toJson();

    return {
      'mapOptions': mapOptions,
      'mapObjects': mapObjects
    };
  }
}

/// Configuration options for the YandexMap native view.
class _YandexMapOptions {
  _YandexMapOptions.fromWidget(YandexMap map) :
    tiltGesturesEnabled = map.tiltGesturesEnabled,
    zoomGesturesEnabled = map.zoomGesturesEnabled,
    rotateGesturesEnabled = map.rotateGesturesEnabled,
    scrollGesturesEnabled = map.scrollGesturesEnabled,
    nightModeEnabled = map.nightModeEnabled,
    fastTapEnabled = map.fastTapEnabled,
    mode2DEnabled = map.mode2DEnabled,
    logoAlignment = map.logoAlignment,
    focusRect = map.focusRect,
    mapType = map.mapType,
    poiLimit = map.poiLimit;

    final bool tiltGesturesEnabled;

    final bool zoomGesturesEnabled;

    final bool rotateGesturesEnabled;

    final bool nightModeEnabled;

    final bool scrollGesturesEnabled;

    final bool fastTapEnabled;

    final bool mode2DEnabled;

    final MapAlignment logoAlignment;

    final ScreenRect? focusRect;

    final MapType mapType;

    final int? poiLimit;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'tiltGesturesEnabled': tiltGesturesEnabled,
      'zoomGesturesEnabled': zoomGesturesEnabled,
      'rotateGesturesEnabled': rotateGesturesEnabled,
      'nightModeEnabled': nightModeEnabled,
      'scrollGesturesEnabled': scrollGesturesEnabled,
      'fastTapEnabled': fastTapEnabled,
      'mode2DEnabled': mode2DEnabled,
      'logoAlignment': logoAlignment.toJson(),
      'focusRect': focusRect?.toJson(),
      'mapType': mapType.index,
      'poiLimit': poiLimit
    };
  }

  Map<String, dynamic> mapUpdates(_YandexMapOptions newOptions) {
    final prevOptionsMap = toJson();

    return newOptions.toJson()..removeWhere(
      (String key, dynamic value) {
        if (value is Map) return mapEquals(prevOptionsMap[key], value);
        return prevOptionsMap[key] == value;
      }
    );
  }
}
