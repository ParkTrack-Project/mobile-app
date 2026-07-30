# Project Structure: ParkTrack

This document provides a comprehensive list of all project files and their purposes to assist AI agents and developers in navigating the codebase.

## 📁 Root Directory
- `AGENTS.md`: Meta-instructions and workflow rules for AI agents.
- `PROJECT_STRUCTURE.md`: This file (file-by-file description).
- `pubspec.yaml`: Project dependencies and configuration.
- `analysis_options.yaml`: Static analysis rules (Lint).
- `README.md` / `README_RU.md`: Project overview and setup instructions.
- `LICENSE`: Project license.

---

## 📁 lib/ (Core Logic & UI)

### 📂 core/ (App Infrastructure)
- `constants.dart`: Global constants (API URLs, keys, thresholds).
- **network/**:
  - `dio_client.dart`: Main HTTP client configuration.
  - `auth_interceptor.dart`: Logic for attaching JWT tokens and handling 401s.
  - `api_exception.dart`: Custom exceptions for network errors.
  - `network_error_classifier.dart`: Maps HTTP errors to domain-specific failures.
- **storage/**:
  - `token_storage.dart`: Secure storage for authentication tokens.
  - `settings_storage.dart`: Local persistence for theme/language settings.
- **theme/**:
  - `app_colors.dart`: Color palette definitions.
  - `app_theme.dart`: Material 3 theme configurations.
- **localization/**:
  - `app_localizations.dart`: Translation strings (RU/EN).
- **router/**:
  - `app_router.dart`: GoRouter navigation configuration.
  - `deep_link_coordinator.dart`: Logic for handling external app links.
- **utils/**:
  - `nav_math.dart`: Geometric calculations for map coordinates.
  - `error_snackbar.dart`: Global UI for error reporting.

### 📂 domain/ (Business Logic)
- **models/**:
  - `zone.dart`: Core model for a parking zone.
  - `user.dart`: Model for user profile data.
  - `route_result.dart`: Models for navigation paths and ETA.

### 📂 data/ (Data Access)
- **api/**:
  - `zones_api.dart`: REST endpoints for parking zones.
  - `auth_api.dart`: Endpoints for login/registration.
  - `routing_api.dart`: Interfacing with navigation services.
- **repositories/**:
  - `zones_repository.dart`: Fetching and caching parking data.
  - `auth_repository.dart`: Implementation of user auth logic.
  - `routing_repository.dart`: Coordinating pathfinding requests.

### 📂 presentation/ (State & UI)
- **providers/**:
  - `zones_provider.dart`: Reactive state for visible parking zones.
  - `routing_provider.dart`: State machine for the routing/navigation flow.
  - `auth_provider.dart`: Global authentication state.
  - `filters_provider.dart`: Logic for map filtering (price, availability).
- **screens/**:
  - **map/**: Main map screen, camera controls, and layer coordination.
    - **widgets/**: `parking_card_sheet.dart`, `candidates_sheet.dart`, `parking_zone_layer.dart`.
  - **search/**: Place search screen and suggestion logic.
  - **auth/**: Login, registration, and password recovery screens.
  - **profile/**: User settings and account management.

---

## 📁 web/ (Web Platform)
- `index.html`: Entry point for the web app.
- `yandex_maps.js`: Custom JavaScript bridge for Yandex Maps v3 (Web Mercator).
- `manifest.json`: Progressive Web App (PWA) metadata.

---

## 📁 android/ & ios/ (Native Platform)
- Standard Flutter platform folders containing native configurations, permissions (`AndroidManifest.xml`, `Info.plist`), and icons.

---

## 📁 test/ (Quality Assurance)
- **unit/**: Logic testing for providers, repositories, and math utilities.
- **widget/**: UI testing for individual components.
- **presentation/**: Scenario-based tests for map interactions and search flows.
