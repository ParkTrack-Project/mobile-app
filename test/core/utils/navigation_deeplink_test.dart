import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_localizations.dart';
import 'package:mobile/core/utils/navigation_deeplink.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  test('builds Yandex Maps app and web route links from coordinates', () {
    final app = buildYandexMapsRouteUri(61.789114, 34.359757);
    final web = buildYandexMapsWebRouteUri(61.789114, 34.359757);

    expect(app.scheme, 'yandexmaps');
    expect(app.queryParameters['rtext'], '~61.789114,34.359757');
    expect(app.queryParameters['rtt'], 'auto');
    expect(web.host, 'yandex.ru');
    expect(web.queryParameters['rtext'], '~61.789114,34.359757');
  });

  test('uses web fallback when the Yandex Maps app is unavailable', () async {
    final launched = <Uri>[];

    await openYandexMapsRoute(
      61,
      34,
      canLaunch: (_) async => false,
      launch: (uri, mode) async {
        expect(mode, LaunchMode.externalApplication);
        launched.add(uri);
        return true;
      },
    );

    expect(launched, hasLength(1));
    expect(launched.single.scheme, 'https');
  });

  test('reports an error when neither external map target opens', () async {
    await expectLater(
      openYandexMapsRoute(
        61,
        34,
        canLaunch: (_) async => true,
        launch: (_, _) async => false,
      ),
      throwsStateError,
    );
  });

  test('new action labels are localized in Russian and English', () {
    expect(AppStrings.ru.goAction, 'В путь');
    expect(AppStrings.ru.buildRoute, 'Маршрут');
    expect(AppStrings.ru.openInYandexMaps, 'Яндекс Карты');
    expect(AppStrings.ru.routeBuilding, 'Строим маршрут');
    expect(AppStrings.en.goAction, 'Go');
    expect(AppStrings.en.buildRoute, 'Route');
    expect(AppStrings.en.openInYandexMaps, 'Yandex Maps');
  });
}
