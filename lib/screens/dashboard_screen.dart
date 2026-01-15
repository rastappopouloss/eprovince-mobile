import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_services.dart';
import '../services/db_service.dart';
import 'EmbarquementScreen.dart';
import 'POSScreen.dart';
import 'login_screen.dart';
import 'taxation_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Données Agent
  String _agentName = "Chargement...";
  String _accessType = "PEAGE";

  // Données Stats
  bool _isLoading = true;
  int _todayCount = 0;
  List<Map<String, dynamic>> _weeklyData = [];

  // NOUVELLES VARIABLES
  double _totalFC = 0.0;
  double _totalUSD = 0.0;

  // Couleurs dynamiques
  Color _primaryColor = const Color(0xFF0D47A1); // Bleu par défaut

  @override
  void initState() {
    super.initState();
    _initDashboard();
  }

  Future<void> _initDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    String type = prefs.getString('access_type') ?? 'PEAGE';
    int id = prefs.getInt('agent_id') ?? 0;
    String name = prefs.getString('agent_name') ?? "Agent";

    // Définition de la couleur selon le métier
    Color color;
    if (type == 'TAXE') color = Colors.teal.shade800;
    else if (type == 'EMBARQUEMENT') color = Colors.indigo.shade800;
    else color = const Color(0xFF0D47A1); // Péage

    // Chargement des stats DB
    try {
      final stats = await DBService.instance.getAgentStats(id, type);

      if (mounted) {
        setState(() {
          _accessType = type;
          _agentId = id;
          _agentName = name;
          _primaryColor = color;

          // RÉCUPÉRATION DES DEUX DEVISES
          _totalFC = stats['total_fc'] ?? 0.0;
          _totalUSD = stats['total_usd'] ?? 0.0;
          _todayCount = stats['today_count'] ?? 0;
          _weeklyData = List<Map<String, dynamic>>.from(stats['weekly_data']);
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Erreur Dashboard: $e");
      if(mounted) setState(() => _isLoading = false);
    }
  }

  void _goToWork() {
    Widget nextScreen;
    if (_accessType == 'TAXE') {
      nextScreen = const TaxationScreen();
    } else if (_accessType == 'EMBARQUEMENT') {
      nextScreen = const EmbarquementScreen();
    } else {
      nextScreen = const POSScreen();
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => nextScreen))
        .then((_) => _initDashboard()); // Recharger les stats au retour
  }

  void _handleLogout() {
    // ... Copie ta fonction de logout habituelle ici ...
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Déconnexion"),
        content: const Text("Voulez-vous vraiment fermer votre session ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("NON"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await AuthService().logout();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (route) => false
              );
            },
            child: const Text("OUI, QUITTER", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _primaryColor))
          : Column(
        children: [
          // --- 1. HEADER ---
          Container(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 30),
            decoration: BoxDecoration(
              color: _primaryColor,
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Bonjour,", style: TextStyle(color: Colors.white70, fontSize: 16)),
                        Text(_agentName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        Container(
                          margin: const EdgeInsets.only(top: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(5)),
                          child: Text("AGENT $_accessType", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.white),
                      onPressed: _handleLogout,
                      tooltip: "Déconnexion",
                    )
                  ],
                ),
              ],
            ),
          ),

          // --- 2. CONTENU ---
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // CARTES RÉSUMÉ
                  const Text("Aujourd'hui", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      // CARTE RECETTES (Modifiée pour afficher 2 lignes)
                      Expanded(
                          child: _buildMultiCurrencyCard(
                              "Recettes du jour",
                              _totalFC,
                              _totalUSD,
                              Icons.payments
                          )
                      ),
                      const SizedBox(width: 15),
                      Expanded(child: _buildStatCard("Tickets", "$_todayCount", Icons.receipt)),
                    ],
                  ),

                  const SizedBox(height: 30),

                  // GRAPHIQUE 7 JOURS
                  const Text("Performance (7 derniers jours)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
                    ),
                    child: _buildBarChart(),
                  ),
                ],
              ),
            ),
          ),

          // --- 3. BOUTON ACTION FLOTTANT ---
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0,-5))]
            ),
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: _goToWork,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                icon: const Icon(Icons.work),
                label: const Text("COMMENCER LE TRAVAIL", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _primaryColor, size: 30),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _primaryColor)),
          Text(title, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildMultiCurrencyCard(String title, double fc, double usd, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _primaryColor, size: 30),
          const SizedBox(height: 15),

          // Montant FC
          Text(
              "${fc.toStringAsFixed(0)} FC",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryColor)
          ),

          // Barre de séparation discrète
          Container(margin: const EdgeInsets.symmetric(vertical: 5), height: 1, width: 40, color: Colors.grey[300]),

          // Montant USD
          Text(
              "${usd.toStringAsFixed(2)} \$",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green[700])
          ),

          const SizedBox(height: 5),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  // Petit widget de graphique fait main (simple et efficace)
  Widget _buildBarChart() {
    if (_weeklyData.isEmpty) return const Center(child: Text("Pas de données"));

    // Trouver le max pour l'échelle
    double maxVal = 1.0;
    for(var d in _weeklyData) {
      if(d['amount'] > maxVal) maxVal = d['amount'];
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end, // Aligner en bas
      children: _weeklyData.map((data) {
        double heightPercentage = (data['amount'] / maxVal);
        // Hauteur min pour qu'on voit quand même la barre si 0
        if (heightPercentage < 0.02) heightPercentage = 0.02;

        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Valeur (optionnel, peut surcharger si trop serré)
            // Text((data['amount']/1000).toStringAsFixed(0) + "k", style: TextStyle(fontSize: 8)),

            // Barre
            Container(
              width: 12, // Largeur de la barre
              height: 120 * heightPercentage, // Hauteur max 120px
              decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(6)
              ),
            ),
            const SizedBox(height: 8),
            // Jour
            Text(data['day'], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          ],
        );
      }).toList(),
    );
  }
}