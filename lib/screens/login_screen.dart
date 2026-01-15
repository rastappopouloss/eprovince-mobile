import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_services.dart';
import 'EmbarquementScreen.dart';
import 'POSScreen.dart';
import 'taxation_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Appel au service
    final result = await AuthService().login(
        _emailCtrl.text.trim(),
        _passCtrl.text
    );

    setState(() => _isLoading = false);

    if (result['success']) {
      // Récupérer le type pour savoir où aller
      final prefs = await SharedPreferences.getInstance();
      String type = prefs.getString('access_type') ?? 'PEAGE';
      /*if (mounted) {
        if (type == 'EMBARQUEMENT') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const EmbarquementScreen()));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const POSScreen()));
        }
      }*/

      Widget nextScreen;
      if (type == 'TAXE') {
        nextScreen = const TaxationScreen();
      } else if (type == 'EMBARQUEMENT') {
        nextScreen = const EmbarquementScreen();
      } else {
        nextScreen = const POSScreen(); // Péage par défaut
      }

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => nextScreen));
    } else {
      if (mounted) {
        // Affichage erreur propre (SnackBar rouge)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Définition des couleurs principales
    final primaryColor = const Color(0xFF0D47A1); // Un bleu institutionnel fort

    return Scaffold(
      backgroundColor: Colors.grey[50], // Fond très légèrement gris pour le contraste
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- EN-TÊTE DESIGN ---
            Container(
              height: 280,
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(60),
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // LOGO (Remplacez Icon par Image.asset('assets/logo.png'))
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black26)]
                      ),
                      child: Icon(Icons.shield, size: 60, color: primaryColor),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "E-PROVINCE",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Text(
                      "Portail Agent de Terrain",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),

            // --- FORMULAIRE ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Email
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: "Email / Matricule",
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (v) => v!.isEmpty ? "Champs requis" : null,
                    ),
                    const SizedBox(height: 20),

                    // Password
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: "Mot de passe",
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (v) => v!.isEmpty ? "Mot de passe requis" : null,
                    ),

                    const SizedBox(height: 40),

                    // Bouton Login
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _handleLogin, // Oups, correction: _handleLogin
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                          "SE CONNECTER",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Text(
                      "© 2024 Province - Système Sécurisé",
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}