import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_services.dart';
import '../services/db_service.dart';
import '../services/printer_service.dart';
import '../services/sync_service.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'login_screen.dart';

class EmbarquementScreen extends StatefulWidget {
  const EmbarquementScreen({super.key});
  @override
  State<EmbarquementScreen> createState() => _EmbarquementScreenState();
}

class _EmbarquementScreenState extends State<EmbarquementScreen> {
  final _formKey = GlobalKey<FormState>();

  // Champs spécifiques Embarquement
  final TextEditingController _passagerCtrl = TextEditingController();
  final TextEditingController _volCtrl = TextEditingController();
  final TextEditingController _destCtrl = TextEditingController();
  final TextEditingController _montantCtrl = TextEditingController();

  String _agentName = "Chargement...";
  String _siteNom = "Aéroport...";
  int? _provinceId, _villeId, _siteId, _agentId;
  String _devise = 'FC';

  String _provinceNom = "";
  String _provinceCode = "";
  String _provinceEntete = "";

  bool _isSaving = false;

  // Variables Imprimante
  final PrinterService _printerService = PrinterService();
  List<BluetoothDevice> _devices = [];
  bool _connected = false;

  // COULEUR DU THÈME AÉROPORT
  final Color _themeColor = Colors.indigo.shade800;

  @override
  void initState() {
    super.initState();
    _loadSession();
    _initPrinter();
  }

  void _initPrinter() async {
    try {
      _devices = await _printerService.getBondedDevices();
      setState(() {});
    } catch (e) {
      print("Erreur imprimante: $e");
    }
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _agentId = prefs.getInt('agent_id');
      _agentName = prefs.getString('agent_name') ?? "Agent";
      _provinceId = prefs.getInt('config_province_id');
      _villeId = prefs.getInt('config_ville_id');
      _siteId = prefs.getInt('config_site_id');
      _siteNom = prefs.getString('config_site_nom') ?? "Aéroport";

      _provinceNom = prefs.getString('config_province_nom') ?? "KINSHASA";
      _provinceCode = prefs.getString('config_province_code') ?? "";
      _provinceEntete = prefs.getString('config_province_entete') ?? "";
    });
  }

  void _showDeviceDialog() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text("Choisir l'imprimante"),
        children: _devices.map((device) => SimpleDialogOption(
          child: Row(
            children: [
              const Icon(Icons.print, color: Colors.blueGrey),
              const SizedBox(width: 10),
              Text(device.name ?? "Inconnu"),
            ],
          ),
          onPressed: () async {
            Navigator.pop(context);
            bool isConnected = await _printerService.connect(device);
            setState(() {
              _selectedDevice = device;
              _connected = isConnected;
            });
            if (isConnected) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Connecté à ${device.name}"), backgroundColor: Colors.green));
            }
          },
        )).toList(),
      ),
    );
  }

  void _handleLogout() {
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

  Future<void> _handleEmbarquement() async {
    if (!_formKey.currentState!.validate()) return;

    if (_provinceId == null || _siteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur configuration agent. Reconnectez-vous."), backgroundColor: Colors.red));
      return;
    }

    if (!_connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Imprimante non connectée"), backgroundColor: Colors.orange));
    }

    setState(() => _isSaving = true);

    try {
      Map<String, dynamic> data = {
        'province_id': _provinceId,
        'ville_id': _villeId,
        'site_id': _siteId,
        'user_id': _agentId,
        'passager': _passagerCtrl.text.toUpperCase(),
        'vol': _volCtrl.text.toUpperCase(),
        'destination': _destCtrl.text.toUpperCase(),
        'montant': double.parse(_montantCtrl.text),
        'devise': _devise,
        'datecreate': DateTime.now().toIso8601String(),
        'is_synced': 0
      };

      await DBService.instance.insertEmbarquement(data);

      try {
        await _printerService.printEmbarquementTicket(
            data,
            _agentName,
            _siteNom,
            _provinceNom,
            _provinceCode,
            _provinceEntete
        );
      } catch (e) {
        print("Erreur impression: $e");
      }

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Enregistré !"), backgroundColor: Colors.green));
        _passagerCtrl.clear();
        _volCtrl.clear();
        _destCtrl.clear();
        _montantCtrl.clear();
      }

      SyncService().syncEverything();

    } catch (e) {
      print("ERREUR FATALE: $e");
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur enregistrement: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if(mounted) setState(() => _isSaving = false);
    }
  }

  // --- HELPER POUR LE STYLE DES CHAMPS ---
  InputDecoration _buildInputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[700]),
      prefixIcon: Icon(icon, color: _themeColor),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _themeColor, width: 2)),
    );
  }

  // --- NOUVELLE FONCTION DE SYNC AVEC FEEDBACK (Thème Indigo) ---
  Future<void> _handleSync() async {
    await SyncService().syncEverything(
      onProgress: (message) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                if (!message.contains("✅") && !message.contains("Pas d'internet"))
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  ),
                Expanded(child: Text(message)),
              ],
            ),
            // On utilise le thème Indigo ici
            backgroundColor: message.contains("✅") ? Colors.green : Colors.indigo[800],
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo[50],
      appBar: AppBar(
        title: const Text('GUICHET AÉROPORT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: _themeColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard),
            tooltip: "Aller au Dashboard",
            onPressed: () {
              // Au lieu de pop(), on force la navigation vers le Dashboard
              Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const DashboardScreen()), // Assure-toi d'avoir importé dashboard_screen.dart
                      (route) => false // On efface tout l'historique pour ne pas revenir en boucle
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.white),
            onPressed: _handleSync, // <--- APPEL ICI
          ),
          IconButton(
            icon: Icon(Icons.print, color: _connected ? Colors.greenAccent : Colors.white),
            onPressed: _showDeviceDialog,
            tooltip: "Imprimante",
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _handleLogout,
            tooltip: "Déconnexion",
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. HEADER BLEU (Fixé en haut)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 150, // Hauteur fixe pour le fond
            child: Container(
              decoration: BoxDecoration(
                color: _themeColor,
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
              ),
            ),
          ),

          // 2. CONTENU (Ancré pour remplir l'écran)
          // C'est le Positioned.fill qui corrige le crash "RenderBox not laid out"
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              child: Column(
                children: [
                  // INFO AGENT (Carte du haut)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: Colors.indigo[100],
                          child: Icon(Icons.flight, color: _themeColor),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_agentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Row(
                                children: [
                                  Icon(Icons.location_city, size: 14, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Flexible(child: Text(_siteNom, style: TextStyle(color: Colors.grey[800], fontSize: 13), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Bouton Sync rapide
                        IconButton(
                          onPressed: _handleSync, // <--- APPEL ICI
                          icon: const Icon(Icons.sync, color: Colors.indigo),
                          tooltip: "Synchroniser",
                        )
                      ],
                    ),
                  ),

                  // FORMULAIRE (Carte Principale)
                  Form(
                    key: _formKey,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.airplane_ticket_outlined, color: _themeColor),
                              const SizedBox(width: 10),
                              const Text("Nouvel Embarquement", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                            ],
                          ),
                          const Divider(height: 30),

                          // Nom Passager
                          TextFormField(
                            controller: _passagerCtrl,
                            decoration: _buildInputDeco('Nom Passager', Icons.person),
                            textCapitalization: TextCapitalization.characters,
                          ),
                          const SizedBox(height: 15),

                          // Vol & Destination
                          Row(
                            children: [
                              Expanded(child: TextFormField(
                                controller: _volCtrl,
                                decoration: _buildInputDeco('N° Vol', Icons.flight_takeoff),
                                textCapitalization: TextCapitalization.characters,
                                validator: (v) => v!.isEmpty ? 'Requis' : null,
                              )),
                              const SizedBox(width: 10),
                              Expanded(child: TextFormField(
                                controller: _destCtrl,
                                decoration: _buildInputDeco('Destination', Icons.location_on),
                                textCapitalization: TextCapitalization.characters,
                                validator: (v) => v!.isEmpty ? 'Requis' : null,
                              )),
                            ],
                          ),
                          const SizedBox(height: 15),

                          // Montant & Devise (Correction Overflow incluse ici)
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                                color: Colors.indigo[50],
                                borderRadius: BorderRadius.circular(12)
                            ),
                            child: Row(
                              children: [
                                // Montant (Flex 3)
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: _montantCtrl,
                                    keyboardType: TextInputType.number,
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _themeColor),
                                    decoration: _buildInputDeco('Montant Payé', Icons.payments).copyWith(
                                      fillColor: Colors.white,
                                    ),
                                    validator: (v) => v!.isEmpty ? 'Requis' : null,
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // Devise (Flex 2 - Sans icône pour éviter le crash)
                                Expanded(
                                  flex: 2,
                                  child: DropdownButtonFormField<String>(
                                    value: _devise,
                                    isExpanded: true,
                                    decoration: _buildInputDeco('', Icons.money).copyWith(
                                        prefixIcon: null, // ON RETIRE L'ICÔNE ICI
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                                        fillColor: Colors.white,
                                        labelText: 'Devise'
                                    ),
                                    items: ['FC', 'USD'].map((val) => DropdownMenuItem(value: val, child: Text(val, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                                    onChanged: (v) => setState(() => _devise = v!),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 30),

                          // BOUTON ACTION
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _handleEmbarquement,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _themeColor,
                                foregroundColor: Colors.white,
                                elevation: 4,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              child: _isSaving
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.print),
                                  SizedBox(width: 10),
                                  Text("ÉMETTRE & IMPRIMER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),

                  // Lien Historique
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoryScreen()));
                    },
                    icon: const Icon(Icons.history, color: Colors.grey),
                    label: const Text("Voir les embarquements récents", style: TextStyle(color: Colors.grey)),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}