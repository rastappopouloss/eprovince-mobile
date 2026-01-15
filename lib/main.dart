import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const EProvinceApp());
}

class EProvinceApp extends StatelessWidget {
  const EProvinceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // C'est ICI que la Directionality est injectée par défaut
      title: 'E-Province',
      debugShowCheckedModeBanner: false, // Enlève le bandeau "DEBUG" en haut à droite

      // Configuration du Thème (Material 3)
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1), // Le Bleu E-Province
          primary: const Color(0xFF0D47A1),
        ),
        // On peut définir une police par défaut ici si vous avez google_fonts
        // fontFamily: 'Roboto',
      ),

      // Le point d'entrée de l'application
      home: const SplashScreen(),
    );
  }
}
