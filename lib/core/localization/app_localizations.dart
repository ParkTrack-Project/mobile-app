import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../presentation/providers/settings_provider.dart';

class AppStrings {
  final String appTitle;
  final String findParking;
  final String noInternet;
  final String requestTimedOut;
  final String networkFailure;
  final String mapLoadError;
  final String routeLoadError;
  final String unknownError;
  final String retry;
  final String pwaInstallTitle;
  final String pwaInstallStep1;
  final String pwaInstallStep2;
  final String searching;
  final String routeReady;
  final String selectParking;
  final String parkingZone;
  final String free;
  final String pay;
  final String hourSign;
  final String capacity;
  final String forecast;
  final String confidence;
  final String type;
  final String parkingType;
  final String updatedAt;
  final String searchPlaceholder;
  final String filters;
  final String apply;
  final String reset;
  final String logout;
  final String settings;
  final String appearance;
  final String theme;
  final String language;
  final String info;
  final String privacyPolicy;
  final String github;
  final String themeLight;
  final String themeDark;
  final String themeSystem;
  final String langRussian;
  final String langEnglish;
  final String langSystem;
  final String account;
  final String notAuthenticated;
  final String logoutConfirm;
  final String cancel;
  final String inAppRoute;
  final String yandexNavigator;
  final String buildRoute;
  final String searchParkingNear;
  final String selectedPlace;
  final String myLocation;
  final String now;
  final String time;
  final String today;
  final String tomorrow;
  final String yesterday;
  final String street;
  final String yard;
  final String openLot;
  final String underground;
  final String multilevel;
  final String parallel;
  final String regular;
  final String login;
  final String password;
  final String signIn;
  final String noAccount;
  final String signUp;
  final String forgotPassword;
  final String emailRequired;
  final String passwordTooShort;
  final String name;
  final String nameRequired;
  final String invalidEmail;
  final String createAccount;
  final String alreadyHaveAccount;
  final String registration;
  final String resetPassword;
  final String passwordResetInstructions;
  final String sendInstructions;
  final String hideFull;
  final String hidePrivate;
  final String hideInaccessible;
  final String hideInactive;
  final String minConfidence;
  final String limitPrice;
  final String minFreeSpots;
  final String any;
  final String locationType;
  final String searchNoResults;
  final String searchError;
  final String searchHint;
  final String errorDetails;
  final String errorCreatingRoute;
  final String errorLoadingZones;
  final String copy;
  final String close;
  final String moreInfo;
  final String copiedToClipboard;
  final String locationPermissionDenied;
  final String locationPermissionReason;
  final String pickZoneOnMap;
  final String navigationActive;
  final String unauthorized;
  final String forbidden;
  final String notFound;
  final String emailAlreadyExists;
  final String invalidData;
  final String serverError;
  final String requestError;
  final String searchTimeout;
  final String pointLookupError;
  final String pointLookupTimeout;
  final String restartRequiredForMap;
  final String private;
  final String loadingData;
  final String noForecast;
  final String forWord;
  final String generated;
  final String jumpToClosest;
  final String forecastFor;
  final String youPicked;
  final String arrival;
  final String list;
  final String map;
  final String pickOnMapInstruction;
  final String pickOnMapAction;
  final String recalculating;
  final String straightAhead;
  final String finish;
  final String finishConfirmTitle;
  final String finishConfirmContent;
  final String timeLabel;
  final String distanceLabel;
  final String speedLabel;
  final String selectTheme;
  final String selectLanguage;
  final String metersSign;
  final String kmSign;
  final String minutesSign;
  final String turnLeft;
  final String keepLeft;
  final String turnRight;
  final String keepRight;
  final String uTurn;
  final String inWord;
  final List<String> monthNames;
  final String dataErasure;
  final String editProfile;
  final String save;
  final String profileUpdated;

  AppStrings({
    required this.appTitle,
    required this.findParking,
    required this.searching,
    required this.routeReady,
    required this.selectParking,
    required this.parkingZone,
    required this.free,
    required this.pay,
    required this.hourSign,
    required this.capacity,
    required this.forecast,
    required this.confidence,
    required this.type,
    required this.parkingType,
    required this.updatedAt,
    required this.searchPlaceholder,
    required this.filters,
    required this.apply,
    required this.reset,
    required this.passwordResetInstructions,
    required this.logout,
    required this.settings,
    required this.appearance,
    required this.theme,
    required this.language,
    required this.info,
    required this.privacyPolicy,
    required this.github,
    required this.themeLight,
    required this.themeDark,
    required this.themeSystem,
    required this.langRussian,
    required this.langEnglish,
    required this.langSystem,
    required this.account,
    required this.notAuthenticated,
    required this.logoutConfirm,
    required this.cancel,
    required this.inAppRoute,
    required this.yandexNavigator,
    required this.buildRoute,
    required this.searchParkingNear,
    required this.selectedPlace,
    required this.myLocation,
    required this.now,
    required this.time,
    required this.today,
    required this.tomorrow,
    required this.yesterday,
    required this.street,
    required this.yard,
    required this.openLot,
    required this.underground,
    required this.multilevel,
    required this.parallel,
    required this.regular,
    required this.login,
    required this.password,
    required this.signIn,
    required this.noAccount,
    required this.signUp,
    required this.forgotPassword,
    required this.emailRequired,
    required this.passwordTooShort,
    required this.name,
    required this.nameRequired,
    required this.invalidEmail,
    required this.createAccount,
    required this.alreadyHaveAccount,
    required this.registration,
    required this.resetPassword,
    required this.sendInstructions,
    required this.hideFull,
    required this.hidePrivate,
    required this.hideInaccessible,
    required this.hideInactive,
    required this.minConfidence,
    required this.limitPrice,
    required this.minFreeSpots,
    required this.any,
    required this.locationType,
    required this.searchNoResults,
    required this.searchError,
    required this.searchHint,
    required this.errorDetails,
    required this.errorCreatingRoute,
    required this.errorLoadingZones,
    required this.copy,
    required this.close,
    required this.moreInfo,
    required this.copiedToClipboard,
    required this.locationPermissionDenied,
    required this.locationPermissionReason,
    required this.pickZoneOnMap,
    required this.navigationActive,
    required this.unauthorized,
    required this.forbidden,
    required this.notFound,
    required this.emailAlreadyExists,
    required this.invalidData,
    required this.serverError,
    required this.requestError,
    required this.searchTimeout,
    required this.pointLookupError,
    required this.pointLookupTimeout,
    required this.restartRequiredForMap,
    required this.private,
    required this.loadingData,
    required this.noForecast,
    required this.forWord,
    required this.generated,
    required this.jumpToClosest,
    required this.forecastFor,
    required this.youPicked,
    required this.arrival,
    required this.list,
    required this.map,
    required this.pickOnMapInstruction,
    required this.pickOnMapAction,
    required this.recalculating,
    required this.straightAhead,
    required this.finish,
    required this.finishConfirmTitle,
    required this.finishConfirmContent,
    required this.timeLabel,
    required this.distanceLabel,
    required this.speedLabel,
    required this.selectTheme,
    required this.selectLanguage,
    required this.metersSign,
    required this.kmSign,
    required this.minutesSign,
    required this.turnLeft,
    required this.keepLeft,
    required this.turnRight,
    required this.keepRight,
    required this.uTurn,
    required this.inWord,
    required this.monthNames,
    required this.dataErasure,
    required this.editProfile,
    required this.save,
    required this.profileUpdated,
  });

  static AppStrings ru = AppStrings(
    appTitle: 'ParkTrack',
    findParking: 'Припарковаться',
    noInternet: 'Нет интернета',
    requestTimedOut: 'Время ожидания истекло',
    networkFailure: 'Ошибка сети',
    mapLoadError: 'Ошибка загрузки карты',
    routeLoadError: 'Ошибка загрузки маршрута',
    unknownError: 'Что-то пошло не так',
    retry: 'Повторить',
    pwaInstallTitle: 'Установка приложения',
    pwaInstallStep1: 'Нажмите кнопку «Поделиться» в браузере',
    pwaInstallStep2: 'Выберите «На экран Домой»',
    searching: 'Ищем...',
    routeReady: 'Маршрут готов',
    selectParking: 'Выберите парковку',
    parkingZone: 'Парковка',
    free: 'Свободно',
    pay: 'Стоимость',
    hourSign: 'ч',
    capacity: 'Мест',
    forecast: 'Прогноз',
    confidence: 'Уверенность',
    type: 'Тип',
    parkingType: 'Постановка',
    updatedAt: 'Обновлено',
    searchPlaceholder: 'Найти место назначения',
    filters: 'Фильтры',
    apply: 'Применить',
    reset: 'Сбросить',
    passwordResetInstructions: 'Введите свой email чтобы получить инструкции по сбросу пароля.',
    logout: 'Выйти',
    settings: 'Настройки',
    appearance: 'Внешний вид',
    theme: 'Тема',
    language: 'Язык',
    info: 'Информация',
    privacyPolicy: 'Политика конфиденциальности',
    github: 'GitHub',
    themeLight: 'Светлая',
    themeDark: 'Тёмная',
    themeSystem: 'Системная',
    langRussian: 'Русский',
    langEnglish: 'English',
    langSystem: 'Системный',
    account: 'Аккаунт',
    notAuthenticated: 'Неверные данные для входа',
    logoutConfirm: 'Вы уверены, что хотите выйти из аккаунта?',
    cancel: 'Отмена',
    inAppRoute: 'В приложении',
    yandexNavigator: 'Яндекс',
    buildRoute: 'Построить маршрут',
    searchParkingNear: 'Искать парковку рядом',
    selectedPlace: 'Выбранное место',
    myLocation: 'Мое местоположение',
    now: 'Сейчас',
    time: 'Время',
    today: 'Сегодня',
    tomorrow: 'Завтра',
    yesterday: 'Вчера',
    street: 'Уличная',
    yard: 'Дворовая',
    openLot: 'Открытая стоянка',
    underground: 'Подземная',
    multilevel: 'Многоуровневая',
    parallel: 'Параллельная',
    regular: 'Обычная',
    login: 'Email',
    password: 'Пароль',
    signIn: 'Войти',
    noAccount: 'Нет аккаунта? Зарегистрироваться',
    signUp: 'Зарегистрироваться',
    forgotPassword: 'Забыли пароль?',
    emailRequired: 'Введите email',
    passwordTooShort: 'Минимум 6 символов',
    name: 'Имя',
    nameRequired: 'Введите имя',
    invalidEmail: 'Неверный email',
    createAccount: 'Создать аккаунт',
    alreadyHaveAccount: 'Уже есть аккаунт? Войти',
    registration: 'Регистрация',
    resetPassword: 'Восстановление пароля',
    sendInstructions: 'Отправить инструкции',
    hideFull: 'Скрыть занятые',
    hidePrivate: 'Скрыть частные',
    hideInaccessible: 'Скрыть места для инвалидов',
    hideInactive: 'Скрыть неактивные',
    minConfidence: 'Минимальная уверенность',
    limitPrice: 'Ограничить стоимость',
    minFreeSpots: 'Минимум свободных мест',
    any: 'Любое',
    locationType: 'Тип парковки',
    searchNoResults: 'Ничего не найдено',
    searchError: 'Ошибка поиска',
    searchHint: 'Введите адрес или место',
    errorDetails: 'Детали ошибки',
    errorCreatingRoute: 'Ошибка при построении маршрута',
    errorLoadingZones: 'Не удалось загрузить парковки',
    copy: 'Копировать',
    close: 'Закрыть',
    moreInfo: 'Подробнее',
    copiedToClipboard: 'Скопировано в буфер',
    locationPermissionDenied: 'Нет доступа к геолокации',
    locationPermissionReason:
        'Для поиска парковок рядом с вами необходим доступ к местоположению.',
    pickZoneOnMap: 'Выберите парковочную зону на карте',
    navigationActive: 'Навигация активна',
    unauthorized: 'Не авторизован',
    forbidden: 'Нет доступа',
    notFound: 'Не найдено',
    emailAlreadyExists: 'Пользователь с таким email уже существует',
    invalidData: 'Неверные данные',
    serverError: 'Ошибка сервера',
    requestError: 'Ошибка запроса',
    searchTimeout: 'Поиск занял слишком много времени',
    pointLookupError: 'Не удалось определить координаты места',
    pointLookupTimeout: 'Определение точки заняло слишком много времени',
    restartRequiredForMap:
        'Перезапустите приложение, чтобы обновить названия на карте',
    private: 'Частная',
    loadingData: 'Загрузка данных...',
    noForecast: 'Нет прогноза',
    forWord: 'на',
    generated: 'Создан',
    jumpToClosest: 'Открыть ближайшее доступное',
    forecastFor: 'Прогноз на',
    youPicked: 'вы выбрали',
    arrival: 'Прибытие',
    list: 'Список',
    map: 'Карта',
    pickOnMapInstruction:
        'Нажмите «Выбирать на карте», затем тапните подходящую зону на карте.',
    pickOnMapAction: 'Выбирать на карте',
    recalculating: 'Пересчёт маршрута...',
    straightAhead: 'Движение прямо',
    finish: 'Завершить',
    finishConfirmTitle: 'Завершить маршрут?',
    finishConfirmContent: 'Навигация будет остановлена.',
    timeLabel: 'времени',
    distanceLabel: 'до цели',
    speedLabel: 'км/ч',
    selectTheme: 'Выберите тему',
    selectLanguage: 'Выберите язык',
    metersSign: 'м',
    kmSign: 'км',
    minutesSign: 'мин',
    turnLeft: 'Поверните налево',
    keepLeft: 'Держитесь левее',
    turnRight: 'Поверните направо',
    keepRight: 'Держитесь правее',
    uTurn: 'Выполните разворот',
    inWord: 'через',
    monthNames: [
      '',
      'янв',
      'фев',
      'мар',
      'апр',
      'май',
      'июн',
      'июл',
      'авг',
      'сен',
      'окт',
      'ноя',
      'дек',
    ],
    dataErasure: 'Удаление данных',
    editProfile: 'Редактировать профиль',
    save: 'Сохранить',
    profileUpdated: 'Профиль обновлен',
  );

  static AppStrings en = AppStrings(
    appTitle: 'ParkTrack',
    findParking: 'Park Now',
    noInternet: 'No internet',
    requestTimedOut: 'Request timed out',
    networkFailure: 'Network failure',
    mapLoadError: 'Map load error',
    routeLoadError: 'Route load error',
    unknownError: 'Something went wrong',
    retry: 'Retry',
    pwaInstallTitle: 'Install App',
    pwaInstallStep1: 'Tap the Share button in your browser',
    pwaInstallStep2: 'Select "Add to Home Screen"',
    searching: 'Searching...',
    routeReady: 'Route Ready',
    selectParking: 'Select Parking',
    parkingZone: 'Parking',
    free: 'Free',
    pay: 'Price',
    hourSign: 'h',
    capacity: 'Capacity',
    forecast: 'Forecast',
    confidence: 'Confidence',
    type: 'Type',
    parkingType: 'Layout',
    updatedAt: 'Updated',
    searchPlaceholder: 'Find destination',
    filters: 'Filters',
    apply: 'Apply',
    reset: 'Reset',
    passwordResetInstructions: 'Enter your email to receive password reset instructions.',
    logout: 'Logout',
    settings: 'Settings',
    appearance: 'Appearance',
    theme: 'Theme',
    language: 'Language',
    info: 'Information',
    privacyPolicy: 'Privacy Policy',
    github: 'GitHub',
    themeLight: 'Light',
    themeDark: 'Dark',
    themeSystem: 'System',
    langRussian: 'Russian',
    langEnglish: 'English',
    langSystem: 'System',
    account: 'Account',
    notAuthenticated: 'Invalid login credentials',
    logoutConfirm: 'Are you sure you want to sign out?',
    cancel: 'Cancel',
    inAppRoute: 'In-app',
    yandexNavigator: 'Yandex',
    buildRoute: 'Build Route',
    searchParkingNear: 'Search parking nearby',
    selectedPlace: 'Selected place',
    myLocation: 'My location',
    now: 'Now',
    time: 'Time',
    today: 'Today',
    tomorrow: 'Tomorrow',
    yesterday: 'Yesterday',
    street: 'Street',
    yard: 'Yard',
    openLot: 'Open Lot',
    underground: 'Underground',
    multilevel: 'Multilevel',
    parallel: 'Parallel',
    regular: 'Regular',
    login: 'Email',
    password: 'Password',
    signIn: 'Sign In',
    noAccount: 'No account? Sign Up',
    signUp: 'Sign Up',
    forgotPassword: 'Forgot password?',
    emailRequired: 'Email is required',
    passwordTooShort: 'Min 6 characters',
    name: 'Name',
    nameRequired: 'Name is required',
    invalidEmail: 'Invalid email',
    createAccount: 'Create Account',
    alreadyHaveAccount: 'Already have an account? Sign In',
    registration: 'Registration',
    resetPassword: 'Reset Password',
    sendInstructions: 'Send Instructions',
    hideFull: 'Hide full',
    hidePrivate: 'Hide private',
    hideInaccessible: 'Hide disabled spots',
    hideInactive: 'Hide inactive',
    minConfidence: 'Min confidence',
    limitPrice: 'Limit price',
    minFreeSpots: 'Min free spots',
    any: 'Any',
    locationType: 'Parking type',
    searchNoResults: 'No results found',
    searchError: 'Search error',
    searchHint: 'Enter address or place',
    errorDetails: 'Error details',
    errorCreatingRoute: 'Error while creating route',
    errorLoadingZones: 'Failed to load parking zones',
    copy: 'Copy',
    close: 'Close',
    moreInfo: 'Details',
    copiedToClipboard: 'Copied to clipboard',
    locationPermissionDenied: 'Location access denied',
    locationPermissionReason:
        'Location access is required to find parking near you.',
    pickZoneOnMap: 'Select a parking zone on the map',
    navigationActive: 'Navigation active',
    unauthorized: 'Unauthorized',
    forbidden: 'Forbidden',
    notFound: 'Not found',
    emailAlreadyExists: 'User with this email already exists',
    invalidData: 'Invalid data',
    serverError: 'Server error',
    requestError: 'Request error',
    searchTimeout: 'Search timeout',
    pointLookupError: 'Could not determine coordinates',
    pointLookupTimeout: 'Point lookup timeout',
    restartRequiredForMap: 'Restart the app to update map labels',
    private: 'Private',
    loadingData: 'Loading data...',
    noForecast: 'No forecast',
    forWord: 'for',
    generated: 'Generated',
    jumpToClosest: 'Jump to closest available',
    forecastFor: 'Forecast for',
    youPicked: 'you picked',
    arrival: 'Arrival',
    list: 'List',
    map: 'Map',
    pickOnMapInstruction:
        'Tap "Pick on Map", then tap a parking zone on the map.',
    pickOnMapAction: 'Pick on Map',
    recalculating: 'Recalculating...',
    straightAhead: 'Straight ahead',
    finish: 'Finish',
    finishConfirmTitle: 'Finish route?',
    finishConfirmContent: 'Navigation will be stopped.',
    timeLabel: 'time',
    distanceLabel: 'to goal',
    speedLabel: 'km/h',
    selectTheme: 'Select theme',
    selectLanguage: 'Select language',
    metersSign: 'm',
    kmSign: 'km',
    minutesSign: 'min',
    turnLeft: 'Turn left',
    keepLeft: 'Keep left',
    turnRight: 'Turn right',
    keepRight: 'Keep right',
    uTurn: 'U-turn',
    inWord: 'in',
    monthNames: [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ],
    dataErasure: 'Data Erasure',
    editProfile: 'Edit Profile',
    save: 'Save',
    profileUpdated: 'Profile updated',
  );
}

final l10nProvider = Provider<AppStrings>((ref) {
  final settings = ref.watch(settingsProvider);
  final locale = settings.locale ?? const Locale('ru');
  return locale.languageCode == 'en' ? AppStrings.en : AppStrings.ru;
});
