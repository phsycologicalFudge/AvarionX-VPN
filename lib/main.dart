import 'package:colourswift_av/services/themes/theme_manager.dart';
import 'package:colourswift_av/vpn/screens/mainScreen.dart';
import 'package:colourswift_av/vpn/vpn_permission_intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'translations/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

class LanguageManager extends ChangeNotifier {
  String _code = 'system';

  String get code => _code;

  Locale? get locale {
    if (_code == 'system') return const Locale('en');
    return Locale(_code);
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _code = prefs.getString('app_language') ?? 'system';
  }

  Future<void> setLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', code);
    _code = code;
    notifyListeners();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FMTCObjectBoxBackend().initialise();

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );

  final themeManager = ThemeManager();
  await themeManager.init();

  final languageManager = LanguageManager();
  await languageManager.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => themeManager),
        ChangeNotifierProvider(create: (_) => languageManager),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);
    final languageManager = Provider.of<LanguageManager>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AvarionX VPN',
      theme: themeManager.themeData,
      themeMode: themeManager.themeMode,
      locale: languageManager.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        return const Locale('en');
      },
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _HomeGate(),
    );
  }
}

class _HomeGate extends StatefulWidget {
  const _HomeGate();

  @override
  State<_HomeGate> createState() => _HomeGateState();
}

class _HomeGateState extends State<_HomeGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool(VpnPermissionIntroScreen.kDoneKey) == true;

      if (!mounted) return;

      if (done) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const FullVpnModeScreen()),
        );
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const VpnPermissionIntroScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SizedBox.shrink(),
    );
  }
}