import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../../core/localization/app_localizations.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(l10nProvider);
    final authState = ref.watch(authStateProvider);
    final settings = ref.watch(settingsProvider);

    final user = authState.maybeWhen(
      authenticated: (u) => u,
      orElse: () => null,
    );

    return PointerInterceptor(
      intercepting: kIsWeb,
      child: Scaffold(
        appBar: AppBar(title: Text(s.settings)),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            // --- Account Section ---
            _buildSectionHeader(s.account),
            if (user != null)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(user.fullName ?? user.email),
                subtitle: Text(user.email),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => GoRouter.of(context).push('/profile/edit'),
              )
            else
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(s.notAuthenticated),
              ),

            const Divider(),

            // --- Appearance Section ---
            _buildSectionHeader(s.appearance),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(s.theme),
              subtitle: Text(_themeModeName(settings.themeMode, s)),
              onTap: () => _showThemePicker(context, ref, s),
            ),

            const Divider(),

            // --- Language Section ---
            _buildSectionHeader(s.language),
            ListTile(
              leading: const Icon(Icons.language_outlined),
              title: Text(s.language),
              subtitle: Text(_languageName(settings.locale?.languageCode, s)),
              onTap: () => _showLanguagePicker(context, ref, s),
            ),

            const Divider(),

            // --- Information Section ---
            _buildSectionHeader(s.info),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(s.privacyPolicy),
              onTap: () => _launchUrl('https://parktrack.live/privacy'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(s.dataErasure),
              onTap: () => _launchUrl('https://parktrack.live/data-erasure'),
            ),
            ListTile(
              leading: const Icon(Icons.code_outlined),
              title: Text(s.github),
              onTap: () => _launchUrl('https://github.com/ParkTrack-Project'),
            ),

            const SizedBox(height: 32),

            if (user != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: OutlinedButton.icon(
                  onPressed: () => _showLogoutDialog(context, ref, s),
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: Text(
                    s.logout,
                    style: const TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),

            const SizedBox(height: 24),
            Center(
              child: Text(
                'ParkTrack v1.3.0+3',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  String _themeModeName(ThemeMode mode, AppStrings s) {
    switch (mode) {
      case ThemeMode.system:
        return s.themeSystem;
      case ThemeMode.light:
        return s.themeLight;
      case ThemeMode.dark:
        return s.themeDark;
    }
  }

  String _languageName(String? code, AppStrings s) {
    if (code == null) return s.langSystem;
    if (code == 'ru') return s.langRussian;
    if (code == 'en') return s.langEnglish;
    return code;
  }

  void _showThemePicker(BuildContext context, WidgetRef ref, AppStrings s) {
    final currentMode = ref.read(settingsProvider).themeMode;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                s.selectTheme,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _buildPickerItem(
              context,
              ref,
              s.themeSystem,
              ThemeMode.system,
              currentMode == ThemeMode.system,
            ),
            _buildPickerItem(
              context,
              ref,
              s.themeLight,
              ThemeMode.light,
              currentMode == ThemeMode.light,
            ),
            _buildPickerItem(
              context,
              ref,
              s.themeDark,
              ThemeMode.dark,
              currentMode == ThemeMode.dark,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerItem(
    BuildContext context,
    WidgetRef ref,
    String title,
    ThemeMode mode,
    bool selected,
  ) {
    return ListTile(
      title: Text(title),
      trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
      onTap: () {
        ref.read(settingsProvider.notifier).setThemeMode(mode);
        Navigator.pop(context);
      },
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref, AppStrings s) {
    final currentLang = ref.read(settingsProvider).locale?.languageCode;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                s.selectLanguage,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _buildLangItem(
              context,
              ref,
              s.langSystem,
              null,
              currentLang == null,
              s,
            ),
            _buildLangItem(
              context,
              ref,
              s.langRussian,
              'ru',
              currentLang == 'ru',
              s,
            ),
            _buildLangItem(
              context,
              ref,
              s.langEnglish,
              'en',
              currentLang == 'en',
              s,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildLangItem(
    BuildContext context,
    WidgetRef ref,
    String title,
    String? code,
    bool selected,
    AppStrings s,
  ) {
    return ListTile(
      title: Text(title),
      trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
      onTap: () {
        ref.read(settingsProvider.notifier).setLanguage(code);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.restartRequiredForMap),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref, AppStrings s) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.logout),
        content: Text(s.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authStateProvider.notifier).signOut();
            },
            child: Text(s.logout, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
