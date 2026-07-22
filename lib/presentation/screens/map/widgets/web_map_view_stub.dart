import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../domain/models/zone.dart';
import 'web_map_types.dart';

class WebMapView extends StatelessWidget {
  const WebMapView({
    super.key,
    required this.controller,
    required this.zones,
    required this.candidateIds,
    this.selectedZoneId,
    required this.onZoneTap,
    required this.onCameraChanged,
    required this.onMapReady,
    required this.onError,
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
  final int? selectedZoneId;
  final void Function(Zone zone) onZoneTap;
  final void Function(WebMapCamera camera) onCameraChanged;
  final VoidCallback onMapReady;
  final void Function(Object error) onError;
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
  Widget build(BuildContext context) => const SizedBox.expand();
}
