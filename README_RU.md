# Мобильное приложение ParkTrack

**Русская версия** | [English Version](README.md)

ParkTrack — это современное мобильное приложение, разработанное для упрощения процесса поиска и управления парковочными местами. Созданное с использованием Flutter, оно предлагает удобный и интуитивно понятный интерфейс для водителей в городских условиях.

<a href="https://play.google.com/store/apps/details?id=com.parktrack.mobile">
<img src="docs/google-play.webp" alt="Get it on GooglePlay" width="150">
</a>

## Основные возможности

- **Интерактивная карта**: Визуализация парковочных мест вокруг вас с помощью интеграции Yandex Mapkit.
- **Навигация в реальном времени**: Поиск оптимального маршрута к выбранному парковочному месту.
- **Умный поиск**: Поиск парковки по адресу или названию.
- **Аутентификация пользователей**: Безопасный вход и управление профилем.
- **Управление сессиями**: Автоматическая обработка истекших сессий для повышения безопасности.
- **Deep Linking**: Быстрый доступ к разделам приложения через универсальные ссылки.

## Технологический стек

- **Framework**: [Flutter](https://flutter.dev)
- **State Management**: [Riverpod](https://riverpod.dev) (с генерацией кода)
- **Navigation**: [GoRouter](https://pub.dev/packages/go_router)
- **Networking**: [Dio](https://pub.dev/packages/dio) с кастомными интерцепторами для Auth и логирования.
- **Maps**: [Yandex Mapkit SDK](https://pub.dev/packages/yandex_mapkit)
- **Data Modeling**: [Freezed](https://pub.dev/packages/freezed) & [JSON Serializable](https://pub.dev/packages/json_serializable)
- **Storage**: [Flutter Secure Storage](https://pub.dev/packages/flutter_secure_storage)

## Структура проекта

Проект следует принципам чистой архитектуры:
- `lib/core`: Общие утилиты, работа с сетью, темы и роутинг.
- `lib/data`: Источники данных, реализации репозиториев и DTO.
- `lib/domain`: Бизнес-логика, сущности и интерфейсы репозиториев.
- `lib/presentation`: Слой UI, организованный по экранам (Map, Auth, Search, Profile) и провайдеры Riverpod.

## Начало работы

### Требования

- Flutter SDK (последняя стабильная версия)
- Android Studio / VS Code
- API ключ Yandex Mapkit

### Установка

1.  **Клонируйте репозиторий:**
    ```bash
    git clone https://github.com/ParkTrack-Project/mobile-app.git
    cd mobile-app
    ```

2.  **Установите зависимости:**
    ```bash
    flutter pub get
    ```

3.  **Сгенерируйте код:**
    ```bash
    flutter pub run build_runner build --delete-conflicting-outputs
    ```

4.  **Запустите приложение:**
    ```bash
    flutter run
    ```

## Лицензия

Этот проект распространяется под лицензией MIT — подробности см. в файле [LICENSE](LICENSE).
