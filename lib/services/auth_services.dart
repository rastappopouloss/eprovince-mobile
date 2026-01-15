import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // URL de Production (cPanel)
  final String baseUrl = "https://test.e-province.com/api";

  // URL de Test Local (Décommentez si besoin)
  // final String baseUrl = "http://10.217.152.193:8000/api";

  /// Fonction utilitaire pour forcer la conversion en INT
  /// Empêche le crash "String is not a subtype of int" sur cPanel
  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Accept': 'application/json'},
        body: {
          'email': email,
          'password': password,
          'device_name': 'POS_TERMINAL',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        SharedPreferences prefs = await SharedPreferences.getInstance();

        // 1. Sauvegarde du Token
        await prefs.setString('auth_token', data['access_token']);

        // 2. Sauvegarde Config Agent (AVEC SÉCURITÉ TYPES)
        Map<String, dynamic> agent = data['agent'];

        // On utilise _parseInt pour être sûr que ce sont des chiffres
        await prefs.setInt('agent_id', _parseInt(agent['id']));
        await prefs.setString('agent_name', agent['name'].toString());

        await prefs.setInt('config_province_id', _parseInt(agent['province_id']));

        // Gestion Ville (souvent oubliée, on la sécurise aussi)
        await prefs.setInt('config_ville_id', _parseInt(agent['ville_id']));

        // Type d'accès (PEAGE, TAXE ou EMBARQUEMENT)
        await prefs.setString('access_type', data['access_type'] ?? 'PEAGE');

        // --- NOUVEAU : SAUVEGARDE DU TAUX PROVINCIAL ---
        // On utilise double.tryParse pour éviter les crashs si le serveur envoie "2800" (String) ou 2800 (Int)
        // On cherche d'abord à la racine, et si on trouve pas, on cherche DANS l'agent
        var rawTaux = data['province_taux'] ?? data['agent']['province_taux'];

        double tauxProv = double.tryParse(rawTaux.toString()) ?? 1.0;

        if (tauxProv <= 0) tauxProv = 1.0;

        await prefs.setDouble('config_province_taux', tauxProv);

        print("💰 Taux Province appliqué : $tauxProv");
        // -----------------------------------------------

        // Site ID (Poste ou Aéroport)
        // Note : Si cPanel renvoie "aeroport_id" au lieu de "site_id", on gère le cas
        int siteId = _parseInt(agent['site_id']);
        if (siteId == 0) {
          siteId = _parseInt(agent['aeroport_id']); // Tentative alternative
        }
        if (siteId == 0) {
          siteId = _parseInt(agent['poste_id']); // Tentative alternative 2
        }
        await prefs.setInt('config_site_id', siteId);
        // Nom du site
        // On préfère afficher "Site Inconnu" plutôt que le nom de l'agent si le site est vide
        String nomSiteRecu = agent['site_nom']?.toString() ?? 'Site Inconnu';

        // Petite sécurité supplémentaire si le serveur renvoie une chaine vide ""
        if (nomSiteRecu.trim().isEmpty) nomSiteRecu = "Site Inconnu";
        await prefs.setString('config_site_nom', nomSiteRecu);
        // NOUVELLES SAUVEGARDES
        await prefs.setString('config_province_nom', (agent['province_nom'] ?? '').toString());
        await prefs.setString('config_province_code', (agent['province_code'] ?? '').toString());
        await prefs.setString('config_province_entete', (agent['province_entete'] ?? '').toString());

        return {'success': true, 'message': 'Bienvenue ${agent['name']}'};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Identifiants incorrects'
        };
      }
    } catch (e) {
      print("Erreur Login: $e");
      return {'success': false, 'message': 'Erreur de connexion: Vérifiez votre internet'};
    }
  }

  // Vérifier si déjà connecté au lancement de l'app
  Future<bool> isLoggedIn() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('auth_token');
  }

  // Déconnexion propre
  Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('auth_token');

    // 1. Tenter de prévenir Laravel
    if (token != null) {
      try {
        await http.post(
          Uri.parse('$baseUrl/logout'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json'
          },
        ).timeout(const Duration(seconds: 2));
      } catch (e) {
        print("Déconnexion hors ligne");
      }
    }

    // 2. Nettoyage Local
    await prefs.remove('auth_token');
    await prefs.remove('access_type');
    await prefs.remove('agent_id');
    await prefs.remove('config_site_id');
    // On ne touche PAS à la DB SQLite
  }

  // Récupérer le type d'accès stocké
  Future<String> getAccessType() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_type') ?? 'PEAGE';
  }
}