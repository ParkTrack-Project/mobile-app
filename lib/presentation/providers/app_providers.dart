import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/token_storage.dart';
import '../../data/api/auth_api.dart';
import '../../data/api/zones_api.dart';
import '../../data/api/occupancy_api.dart';
import '../../data/api/forecasts_api.dart';
import '../../data/api/routing_api.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/zones_repository.dart';
import '../../data/repositories/routing_repository.dart';


final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final dioProvider = Provider<Dio>((ref) {
  final tokenStorage = ref.read(tokenStorageProvider);
  return createDio(tokenStorage);
});

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.read(dioProvider)));
final zonesApiProvider = Provider<ZonesApi>((ref) => ZonesApi(ref.read(dioProvider)));
final occupancyApiProvider = Provider<OccupancyApi>((ref) => OccupancyApi(ref.read(dioProvider)));
final forecastsApiProvider = Provider<ForecastsApi>((ref) => ForecastsApi(ref.read(dioProvider)));
final routingApiProvider = Provider<RoutingApi>((ref) => RoutingApi(ref.read(dioProvider)));

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(
      ref.read(authApiProvider),
      ref.read(tokenStorageProvider),
    ));

final zonesRepositoryProvider = Provider<ZonesRepository>((ref) => ZonesRepository(
      ref.read(zonesApiProvider),
      ref.read(occupancyApiProvider),
      ref.read(forecastsApiProvider),
    ));

final routingRepositoryProvider = Provider<RoutingRepository>(
    (ref) => RoutingRepository(ref.read(routingApiProvider)));
