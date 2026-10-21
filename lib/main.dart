import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'apercu.dart';
import 'config.dart';
import 'data/base_locale.dart';
import 'screens/auth_gate.dart';
import 'theme/mode_affichage.dart';
import 'theme/nacrea_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('APERCU')) {
    runApp(const ApercuApp());
    return;
  }
  try {
    await Affichage.charger();
  } catch (_) {
    // Préférence d'affichage illisible : on garde le mode clair.
  }
  NacreaColors.sombre = Affichage.estSombre();
  try {
    await Supabase.initialize(
      url: NacreaConfig.supabaseUrl,
      publishableKey: NacreaConfig.supabasePublishableKey,
    );
    await ouvrirBaseLocale();
  } catch (e) {
    // Plutôt qu'un écran bloqué sur le logo : on explique le problème.
    runApp(_ErreurDemarrage(e));
    return;
  }
  runApp(const NacreaApp());
}

class _ErreurDemarrage extends StatelessWidget {
  const _ErreurDemarrage(this.erreur);
  final Object erreur;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: NacreaTheme.actuel(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: NacreaColors.erreur),
                const SizedBox(height: 16),
                Text('YDS Beauty n\'a pas pu démarrer', style: NacreaTheme.titre(size: 28), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Text(
                  'Fermez complètement l\'application puis rouvrez-la. Si le problème continue, '
                  'envoyez une capture de cet écran au service YDS Beauty.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SelectableText('$erreur',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: NacreaColors.gris)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NacreaApp extends StatefulWidget {
  const NacreaApp({super.key});

  @override
  State<NacreaApp> createState() => _NacreaAppState();
}

class _NacreaAppState extends State<NacreaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Affichage.mode.addListener(_appliquer);
  }

  @override
  void dispose() {
    Affichage.mode.removeListener(_appliquer);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Le téléphone ou le PC passe en mode sombre (mode « Automatique »).
  @override
  void didChangePlatformBrightness() => _appliquer();

  void _appliquer() {
    final sombre = Affichage.estSombre();
    if (sombre == NacreaColors.sombre) return;
    NacreaColors.sombre = sombre;
    setState(() {});
    // Les couleurs sont lues partout dans l'appli : on redessine tous les écrans ouverts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void redessiner(Element e) {
        e.markNeedsBuild();
        e.visitChildren(redessiner);
      }

      (context as Element).visitChildren(redessiner);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YDS Beauty',
      debugShowCheckedModeBanner: false,
      theme: NacreaTheme.actuel(),
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
