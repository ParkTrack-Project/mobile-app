# ParkTrack Mobile App

[Русская версия](README_RU.md) | **English Version**

ParkTrack is a modern mobile application designed to simplify the process of finding and managing parking spaces. Built with Flutter, it offers a seamless and intuitive experience for drivers navigating urban environments.

<a href="https://play.google.com/store/apps/details?id=com.parktrack.mobile">
<img src="docs/google-play.webp" alt="Get it on GooglePlay" width="150">
</a>

## Key Features

- **Interactive Map**: Visualize parking spots around you using Yandex Mapkit integration.
- **Real-time Navigation**: Find the best route to your selected parking spot.
- **Smart Search**: Search for parking by address or name.
- **User Authentication**: Secure sign-in and profile management.
- **Session Management**: Automated handling of expired sessions for enhanced security.
- **Deep Linking**: Quick access to specific app sections via universal links.

## Tech Stack

- **Framework**: [Flutter](https://flutter.dev)
- **State Management**: [Riverpod](https://riverpod.dev) (with code generation)
- **Navigation**: [GoRouter](https://pub.dev/packages/go_router)
- **Networking**: [Dio](https://pub.dev/packages/dio) with custom interceptors for Auth and Logging.
- **Maps**: [Yandex Mapkit SDK](https://pub.dev/packages/yandex_mapkit)
- **Data Modeling**: [Freezed](https://pub.dev/packages/freezed) & [JSON Serializable](https://pub.dev/packages/json_serializable)
- **Storage**: [Flutter Secure Storage](https://pub.dev/packages/flutter_secure_storage)

## Project Structure

The project follows a clean architecture approach:
- `lib/core`: Shared utilities, networking, themes, and routing.
- `lib/data`: Data sources, repositories implementations, and DTOs.
- `lib/domain`: Business logic, entities, and repository interfaces.
- `lib/presentation`: UI layer organized by screens (Map, Auth, Search, Profile) and Riverpod providers.

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Android Studio / VS Code
- Yandex Mapkit API Key

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/ParkTrack-Project/mobile-app.git
    cd mobile-app
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Generate code:**
    ```bash
    flutter pub run build_runner build --delete-conflicting-outputs
    ```

4.  **Run the application:**
    ```bash
    flutter run
    ```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
