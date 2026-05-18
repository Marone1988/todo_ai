import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'l10n/strings.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';
import 'services/location_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('fr_FR', null);
  await initializeDateFormatting('ar', null);
  await initializeDateFormatting('en_US', null);

  await NotificationService.instance.initialize();
  await LocationService.initialize();
  await LocationService.startMonitoring();
  await LocationService.registerMonthlyCalendarSync();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const VocalTodoApp());
}

class VocalTodoApp extends StatelessWidget {
  const VocalTodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: appLang,
      builder: (context, lang, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: appThemeMode,
          builder: (context, mode, _) {
            final isDark = mode == ThemeMode.dark;
            SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
            ));
            return MaterialApp(
              title: 'Vocal Todo',
              debugShowCheckedModeBanner: false,
              locale: Locale(lang),
              supportedLocales: const [
                Locale('en'),
                Locale('fr'),
                Locale('ar'),
              ],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              themeMode: mode,
              theme: lightTheme,
              darkTheme: darkTheme,
              home: const SplashScreen(),
            );
          },
        );
      },
    );
  }
}
