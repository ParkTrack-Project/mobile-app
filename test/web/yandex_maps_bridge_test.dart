import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String bridge;
  late String webView;
  late String indexHtml;

  setUpAll(() {
    bridge = File('web/yandex_maps.js').readAsStringSync();
    webView = File(
      'lib/presentation/screens/map/widgets/web_map_view_web.dart',
    ).readAsStringSync();
    indexHtml = File('web/index.html').readAsStringSync();
  });

  test('keeps rendering and service contracts implemented', () {
    expect(bridge, isNot(contains('window.ymaps.route')));
    expect(bridge, isNot(contains('/services/route/2.0/')));
    expect(bridge, contains('const responses = await withTimeout('));
    expect(bridge, contains('api.route({'));
    expect(bridge, contains('function routerApiKey()'));
    expect(bridge, contains('meta[name="yandex-router-api-key"]'));
    expect(bridge, contains('.setApikeys({ router: routerKey })'));
    expect(bridge, contains('if (routerApiKey())'));
    expect(
      bridge.indexOf('.setApikeys({ router: routerKey })'),
      lessThan(bridge.indexOf('entry.map = new api.YMap')),
    );
    expect(
      bridge.indexOf('.setApikeys({ router: routerKey })'),
      lessThan(bridge.indexOf('async route(fLat, fLon, tLat, tLon)')),
    );
    expect(bridge, contains('points: [[fLon, fLat], [tLon, tLat]]'));
    expect(
      bridge,
      contains(
        '.map(coordinate => [Number(coordinate[1]), Number(coordinate[0])])',
      ),
    );
    expect(bridge, contains('duration: Number(properties.duration) || 0'));
    expect(bridge, contains('distance: Number(properties.length) || 0'));
    expect(bridge, contains('async function routeViaOsrm('));
    expect(
      bridge,
      contains('https://router.project-osrm.org/route/v1/driving/'),
    );
    expect(bridge, contains('const osrmRouteTimeoutMs = 30000'));
    expect(bridge, contains("payload.code === 'Ok'"));
    expect(
      bridge,
      contains("'?overview=simplified&geometries=geojson&steps=false'"),
    );
    expect(
      bridge.indexOf('const responses = await withTimeout('),
      lessThan(bridge.indexOf('return JSON.stringify(await routeViaOsrm(')),
    );
    expect(bridge, contains('window.ymaps.geocode'));
    expect(bridge, contains('searchViaServices'));
    expect(bridge, contains('api-maps.yandex.ru/services/search/'));
    expect(bridge, isNot(contains('return JSON.stringify([])')));
  });

  test('uses supported v3 interactions and real themes', () {
    expect(bridge, contains("'pinchRotate'"));
    expect(bridge, contains("'pinchZoom'"));
    expect(bridge, contains("'drag'"));
    expect(bridge, contains("state.theme === 'dark' ? 'dark' : 'light'"));
    expect(bridge, isNot(contains('filter: invert')));
    expect(bridge, isNot(contains('grayscale(')));
    expect(bridge, isNot(contains('YMapOpenMapsButton')));
    expect(bridge, contains('zone.fill'));
    expect(bridge, contains('zone.stroke'));
    expect(bridge, contains(r'opacity:${zone.markerOpacity ?? 1}'));
    expect(bridge, contains('clusterExpansionZoom'));
    expect(
      bridge,
      contains('const firstZoom = clusterZoomBucket(currentZoom) + 0.5'),
    );
    expect(
      bridge,
      contains('for (let zoom = firstZoom; zoom <= 21; zoom += 0.5)'),
    );
    expect(bridge, contains('const parkingCounterMinZoom = 14'));
    expect(bridge, contains('zoom < parkingCounterMinZoom &&'));
    expect(bridge, contains('result.singletonIds.has(zoneId)'));
    expect(
      bridge,
      contains('if (!remainsOneCluster && !hasHiddenSingleton) return zoom'),
    );
    expect(bridge, isNot(contains('return Math.min(21, zoom + 0.25)')));
    expect(bridge, contains('center: cluster.center'));
    expect(bridge, contains('function connectedParkingGroups(points)'));
    expect(bridge, contains('function splitParkingGroupByCap(points, cap)'));
    expect(bridge, contains('function mergeOverlappingParkingGroups('));
    expect(bridge, contains('clusterParkingZones(zones, zoomBucket)'));
    expect(bridge, contains('deltaX * deltaX + deltaY * deltaY <= 22 * 22'));
    expect(bridge, contains('zonesInsideBounds(state.zones || []'));
    expect(
      bridge,
      contains('const south = Math.min(firstLatitude, secondLatitude)'),
    );
    expect(
      bridge,
      contains('const north = Math.max(firstLatitude, secondLatitude)'),
    );
    expect(bridge, contains('!Number.isFinite(firstLatitude)'));
    expect(bridge, contains('return zones'));
    expect(bridge, contains('clustering.singletonIds.has(zone.id)'));
    expect(bridge, contains('onClick: clustering.singletonIds.has(zone.id)'));
    expect(bridge, contains(': undefined'));
    expect(bridge, contains('for (const zone of zones) {'));
    expect(bridge, contains('if (zoomBucket >= parkingCounterMinZoom)'));
    expect(
      bridge,
      contains('Math.min(28 + Math.floor(zoneCount / 4) * 4, 44)'),
    );
    expect(bridge, contains('const parkingMarkerBaseScaleFactor = 1.3'));
    expect(bridge, contains('const webParkingMarkerMaxScaleFactor = 0.85'));
    expect(
      bridge,
      contains('2 / Math.max(1, Number(window.devicePixelRatio) || 1)'),
    );
    expect(bridge, contains('Math.min(\n    webParkingMarkerMaxScaleFactor,'));
    expect(
      bridge,
      contains('parkingClusterScaleFactor = parkingMarkerScaleFactor * 0.97'),
    );
    expect(
      bridge,
      contains('parkingClusterScaleFactor / parkingMarkerBaseScaleFactor'),
    );
    expect(bridge, contains('0 0 0 2px rgba(255,255,255,.7)'));
    expect(bridge, isNot(contains('clusterByGrid')));
    expect(bridge, contains('parktrack-user-location__direction'));
    expect(bridge, contains('parktrack-user-location__point'));
    expect(bridge, contains('const hasUserHeading = Number.isFinite'));
    expect(bridge, contains('hasUserHeading ? effectiveUserHeading : null'));
    expect(bridge, contains('if (hasUserHeading)'));
    expect(
      bridge,
      contains(
        "? '<span class=\"parktrack-user-location__direction\"></span>'",
      ),
    );
    expect(webView, contains('? widget.userHeading'));
    expect(webView, contains(': null'));
    expect(webView, isNot(contains('widget.userHeading ?? 0')));
    expect(bridge, contains('requestHeading(id)'));
    expect(bridge, contains("'deviceorientationabsolute'"));
    expect(bridge, contains('azimuth: 0, tilt: 0'));
    expect(bridge, contains('const azimuth = Number(entry.map.azimuth || 0)'));
    expect(bridge, contains('entry.cameraFrame = requestAnimationFrame(() =>'));
    expect(bridge, contains('cancelAnimationFrame(entry.cameraFrame)'));
    expect(bridge, contains('onUpdate: ({ mapInAction }) =>'));
    expect(bridge, contains('cameraUpdateFinished: !mapInAction'));
    expect(bridge, isNot(contains('cameraEmitIntervalMs')));
    expect(bridge, isNot(contains('cameraTimer')));
    expect(bridge, contains("left:-16px;top:-40px"));
    expect(bridge, contains('M16 39C13 32'));
    expect(bridge, contains('left: -32px'));
    expect(bridge, contains('top: -32px'));
    expect(bridge, contains('width: 64px'));
    expect(bridge, contains('height: 64px'));
    expect(bridge, contains('transform: scale(0.6666666667)'));
    expect(bridge, contains('transform-origin: center'));
    expect(bridge, contains('width: 30px'));
    expect(bridge, contains('height: 55px'));
    expect(bridge, contains('width: 36px'));
    expect(bridge, contains('height: 36px'));
    expect(bridge, contains('border: 3px solid'));
    expect(bridge, contains('inset: 4.5px'));
    expect(bridge, contains('entry.userMarkerElement.style.setProperty'));
    expect(bridge, contains('`\${heading - azimuth - 90}deg`'));
  });

  test('renders accuracy as a translucent red geodesic circle', () {
    expect(bridge, contains('function accuracyCircleCoordinates('));
    expect(bridge, contains('const segments = 48'));
    expect(bridge, contains('state.user[3]'));
    expect(bridge, contains("type: 'Polygon'"));
    expect(bridge, contains("color: 'rgba(255, 59, 48, 0.60)', width: 2"));
    expect(bridge, contains("fill: 'rgba(255, 59, 48, 0.14)'"));
    expect(webView, contains('final double? userAccuracy'));
    expect(webView, contains('widget.userAccuracy!.isFinite'));
    expect(indexHtml, contains('yandex_maps.js?v=3.11'));
  });

  test('updates moving markers without rebuilding parking zones', () {
    expect(bridge, contains('function renderPositions(entry, state)'));
    expect(bridge, contains('updatePosition(id, state)'));
    expect(bridge, contains('renderPositions(entry, entry.latestState)'));
    expect(
      bridge,
      contains('function animateUserMarker(entry, to, heading, userAccuracy)'),
    );
    expect(
      bridge,
      contains('entry.userAnimationFrame = requestAnimationFrame(tick)'),
    );
    expect(
      bridge,
      contains('updateMapObject(entry.userMarkerObject, { coordinates })'),
    );
    expect(bridge, contains('entry.userMarkerCoordinates = coordinates'));
    expect(
      bridge,
      isNot(
        contains(
          "clearObjectGroup(entry, 'positionObjects');\n\n    if (state.navigation)",
        ),
      ),
    );
  });

  test('supports web follow camera and user gesture detection', () {
    expect(bridge, contains('setZoom(id, z, durationMilliseconds)'));
    expect(
      bridge,
      contains('duration: Math.max(0, Number(durationMilliseconds) || 0)'),
    );
    expect(webView, contains('@JS(\'parkTrackYandexMaps.follow\')'));
    expect(webView, contains('widget.controller.followHandler'));
    expect(
      webView,
      contains('userGesture: data[\'userGesture\'] as bool? ?? false'),
    );
    expect(bridge, contains('durationMilliseconds'));
    expect(bridge, contains('azimuth,'));
    expect(
      bridge,
      contains('duration: Math.max(0, Number(durationMilliseconds) || 0)'),
    );
    expect(bridge, contains('userGesture,'));
    expect(bridge, contains('entry.userGestureActive = true'));
    expect(bridge, contains("element.addEventListener('pointermove'"));
    expect(bridge, contains("element.addEventListener('wheel'"));
  });

  test('fits route bounds with panel margins and route azimuth', () {
    expect(
      bridge,
      contains(
        'fitBounds(id, south, west, north, east, azimuth, top, right, bottom, left)',
      ),
    );
    expect(bridge, contains('bounds: [[west, south], [east, north]]'));
    expect(bridge, contains('azimuth,'));
    expect(bridge, contains('setCamera(id, lat, lon, zoom, azimuth'));
    expect(webView, contains('@JS(\'parkTrackYandexMaps.setCamera\')'));
    expect(webView, contains('JSNumber azimuth'));
  });
}
