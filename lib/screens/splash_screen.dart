import 'package:flutter/material.dart';
import '../services/auth_services.dart';

// Importe tous tes écrans ici
import 'dashboard_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  void _checkLoginStatus() async {
    // Petit délai pour le branding
    await Future.delayed(const Duration(seconds: 2));

    // 1. Vérifier si on est connecté
    bool isLoggedIn = await AuthService().isLoggedIn();

    if (!mounted) return;

    /*if (isLoggedIn) {
      // 2. RECUPERER LE TYPE D'ACCÈS STOCKÉ
      final prefs = await SharedPreferences.getInstance();
      String type = prefs.getString('access_type') ?? 'PEAGE';

      print("🔄 Auto-Login : Type détecté = $type"); // Debug pour être sûr

      // 3. DIRIGER VERS LE BON ÉCRAN
      Widget nextScreen;

      if (type == 'TAXE') {
        nextScreen = const TaxationScreen();
      } else if (type == 'EMBARQUEMENT') {
        nextScreen = const EmbarquementScreen();
      } else {
        nextScreen = const POSScreen(); // Péage par défaut
      }

      Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => nextScreen)
      );

    } else {
      // Pas connecté -> Login
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen())
      );
    }*/

    if (isLoggedIn) {
      // ON ENVOIE TOUT LE MONDE SUR LE DASHBOARD
      // Le Dashboard chargera lui-même les couleurs et stats selon le type
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen())
      );

    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }



  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0D47A1),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield, size: 80, color: Colors.white),
            SizedBox(height: 20),
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 10),
            // Petit texte pour montrer que ça charge
            Text("Chargement...", style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}