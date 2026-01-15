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

class POSScreen extends StatefulWidget {
  const POSScreen({super.key});

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _plaqueCtrl = TextEditingController();
  final TextEditingController _montantCtrl = TextEditingController();
  final TextEditingController _sachetCtrl = TextEditingController();

  // Variables UI dynamiques
  String _agentName = "Chargement...";
  String _posteNom = "Chargement...";

  // Variables techniques dynamiques
  int? _agentId;
  int? _provinceId;
  int? _villeId;
  int? _posteId;

  String _categorie = 'PÉAGE ROUTE MOTO';
  String _devise = 'FC';

  String _provinceNom = "";
  String _provinceCode = "";
  String _provinceEntete = "";

  bool _isSaving = false;

  // Variables Imprimante
  final PrinterService _printerService = PrinterService();
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _loadAgentSession();
    _initPrinter();
  }

  void _initPrinter() async {
    try {
      _devices = await _printerService.getBondedDevices();
      setState(() {});
    } catch (e) {
      print("Erreur init imprimante: $e");
    }
  }

  Future<void> _loadAgentSession() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _agentId = prefs.getInt('agent_id');
      _agentName = prefs.getString('agent_name') ?? "Agent";
      _provinceId = prefs.getInt('config_province_id');
      _villeId = prefs.getInt('config_ville_id') ?? 1;
      _posteId = prefs.getInt('config_poste_id') ?? prefs.getInt('config_site_id');
      _posteNom = prefs.getString('config_poste_nom') ?? prefs.getString('config_site_nom') ?? "Poste Inconnu";
      _provinceNom = prefs.getString('config_province_nom') ?? "KINSHASA";
      _provinceCode = prefs.getString('config_province_code') ?? "";
      _provinceEntete = prefs.getString('config_province_entete') ?? "";
    });
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

  Future<void> _handleEncaissement() async {
    if (!_formKey.currentState!.validate()) return;

    if (_provinceId == null || _posteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Erreur Config Agent. Reconnectez-vous."), backgroundColor: Colors.red));
      return;
    }

    if (!_connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Imprimante non connectée"), backgroundColor: Colors.orange));
    }

    setState(() => _isSaving = true);

    try {
      Map<String, dynamic> transaction = {
        'province_id': _provinceId,
        'ville_id': _villeId,
        'poste_id': _posteId,
        'user_id': _agentId,
        'categorie': _categorie,
        'immatriculation': _plaqueCtrl.text.toUpperCase(),
        'num_sachet': _sachetCtrl.text.toUpperCase(),
        'montant': double.parse(_montantCtrl.text),
        'devise': _devise,
        'datecreate': DateTime.now().toIso8601String(),
        'is_synced': 0
      };

      await DBService.instance.insertPeage(transaction);

      try {
        await _printerService.printTicket(
            transaction,
            _agentName,
            _posteNom,
            _provinceNom,
            _provinceCode,
            _provinceEntete
        );
      } catch (e) {
        print("Erreur impression: $e");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Enregistré !'), backgroundColor: Colors.green));
        _plaqueCtrl.clear();
        _montantCtrl.clear();
        _sachetCtrl.clear();
      }

      SyncService().syncEverything();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- STYLE PERSONNALISÉ POUR LES CHAMPS ---
  InputDecoration _buildInputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[700]),
      prefixIcon: Icon(icon, color: const Color(0xFF0D47A1)),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 2)),
    );
  }

  // --- NOUVELLE FONCTION DE SYNC AVEC FEEDBACK ---
  Future<void> _handleSync() async {
    await SyncService().syncEverything(
      onProgress: (message) {
        if (!mounted) return;

        // 1. Nettoyer le précédent
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        // 2. Afficher le nouveau
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
            backgroundColor: message.contains("✅") ? Colors.green : Colors.blue[800],
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF0D47A1);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('GUICHET PÉAGE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: primaryColor,
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
            tooltip: "Synchroniser",
          ),
          IconButton(
            icon: Icon(Icons.print, color: _connected ? Colors.greenAccent : Colors.white),
            onPressed: _showDeviceDialog,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. HEADER BLEU (Fond du haut)
          // On utilise Positioned pour bien le caler en haut
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: Container(
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
              ),
            ),
          ),

          // 2. CONTENU PRINCIPAL
          // C'EST ICI LA CORRECTION : Positioned.fill
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                children: [
                  // INFO AGENT (Carte flottante du haut)
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 20),
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
                          backgroundColor: Colors.blue[50],
                          child: Text(_agentName.isNotEmpty ? _agentName[0] : "A", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 20)),
                        ),
                        const SizedBox(width: 15),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_agentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Row(
                              children: [
                                Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(_posteNom, style: TextStyle(color: Colors.grey[800], fontSize: 13)),
                              ],
                            ),
                          ],
                        ),
                        const Spacer(),
                        // Petit bouton Sync Rapide
                        IconButton(
                          onPressed: _handleSync, // <--- APPEL ICI AUSSI
                          icon: const Icon(Icons.sync, color: Colors.blue),
                          tooltip: "Sync",
                        )
                      ],
                    ),
                  ),

                  // FORMULAIRE (Carte principale)
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
                          const Text("Nouvelle Transaction", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                          const Divider(height: 30),

                          // Catégorie
                          DropdownButtonFormField<String>(
                            value: _categorie,
                            decoration: _buildInputDeco('Catégorie', Icons.category),
                            isExpanded: true,
                            items: ['PÉAGE ROUTE MOTO','PÉAGE ROUTE VÉHICULE','PÉAGE ROUTE CAMION','CTTO','⁠⁠VIGNETTE','TAXE CONVENTIONNELLE (MOTO)']
                                .map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
                            onChanged: (v) => setState(() => _categorie = v!),
                          ),
                          const SizedBox(height: 15),

                          // Plaque
                          TextFormField(
                            controller: _plaqueCtrl,
                            decoration: _buildInputDeco('Immatriculation', Icons.directions_car),
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                          ),
                          const SizedBox(height: 15),

                          // Sachet
                          TextFormField(
                            controller: _sachetCtrl,
                            decoration: _buildInputDeco('N° Sachet / Bordereau', Icons.folder_shared),
                          ),
                          const SizedBox(height: 15),

                          // Ligne Montant & Devise (VERSION CORRIGÉE PRÉCÉDEMMENT)
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _montantCtrl,
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor),
                                  decoration: _buildInputDeco('Montant', Icons.payments),
                                  validator: (v) => v!.isEmpty ? 'Requis' : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  value: _devise,
                                  isExpanded: true,
                                  decoration: _buildInputDeco('', Icons.currency_exchange).copyWith(
                                      prefixIcon: null, // Pas d'icône pour éviter overflow
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                                      labelText: 'Devise'
                                  ),
                                  items: ['FC', 'USD'].map((val) => DropdownMenuItem(value: val, child: Text(val, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                                  onChanged: (v) => setState(() => _devise = v!),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),

                          // BOUTON ACTION
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _handleEncaissement,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 5,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              child: _isSaving
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.print),
                                  SizedBox(width: 10),
                                  Text("VALIDER & IMPRIMER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // BOUTON HISTORIQUE (En bas)
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoryScreen()));
                    },
                    icon: const Icon(Icons.history, color: Colors.grey),
                    label: const Text("Voir l'historique de mes ventes", style: TextStyle(color: Colors.grey)),
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