import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/base_locale.dart';
import 'screens/auth_gate.dart';
import 'theme/nacrea_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: NacreaConfig.supabaseUrl,
    anonKey: NacreaConfig.supabasePublishableKey,
  );
  await ouvrirBaseLocale();
  runApp(const NacreaApp());
}

class NacreaApp extends StatelessWidget {
  const NacreaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nacréa',
      debugShowCheckedModeBanner: false,
      theme: NacreaTheme.light(),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(),
    );
  }
}
