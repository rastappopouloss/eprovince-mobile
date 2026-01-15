import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/db_service.dart';
import '../services/printer_service.dart'; // Assure-toi d'avoir cet import
import '../services/sync_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Données Transactions
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;

  // Contexte Session (Pour l'impression)
  String _accessType = 'PEAGE';
  int _agentId = 0;
  String _agentName = "Agent";
  String _siteNom = "Site";
  String _provinceNom = "KINSHASA";
  String _provinceCode = "KIN";
  String _provinceEntete = "DGRK";

  // Service Imprimante
  final PrinterService _printerService = PrinterService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Récupération Contexte (Pour réimpression)
    final type = prefs.getString('access_type') ?? 'PEAGE';
    final agentId = prefs.getInt('agent_id') ?? 0;

    // Infos cosmétiques pour le ticket
    final agentName = prefs.getString('agent_name') ?? "Inconnu";
    final siteNom = prefs.getString('config_site_nom') ?? prefs.getString('config_poste_nom') ?? "Site Inconnu";
    final provNom = prefs.getString('config_province_nom') ?? "KINSHASA";
    final provCode = prefs.getString('config_province_code') ?? "";
    final provEntete = prefs.getString('config_province_entete') ?? "";

    // 2. Récupération DB
    List<Map<String, dynamic>> data = [];
    if (type == 'EMBARQUEMENT') {
      data = await DBService.instance.getEmbarquementHistory(agentId);
    } else {
      data = await DBService.instance.getPeageHistory(agentId);
    }

    if (mounted) {
      setState(() {
        _accessType = type;
        _agentId = agentId;
        _agentName = agentName;
        _siteNom = siteNom;
        _provinceNom = provNom;
        _provinceCode = provCode;
        _provinceEntete = provEntete;

        _transactions = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _forceSync() async {
    setState(() => _isLoading = true);
    await SyncService().syncEverything();
    await _loadData();
  }

  // --- LOGIQUE DE RÉIMPRESSION ---
  Future<void> _reprintTicket(Map<String, dynamic> item) async {
    // On ferme le dialogue d'aperçu
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Envoi à l'imprimante...")));

    try {
      if (_accessType == 'EMBARQUEMENT') {
        await _printerService.printEmbarquementTicket(
            item,
            _agentName,
            _siteNom,
            _provinceNom,
            _provinceCode,
            _provinceEntete
        );
      } else {
        // PEAGE
        await _printerService.printTicket(
            item,
            _agentName,
            _siteNom,
            _provinceNom,
            _provinceCode,
            _provinceEntete
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur impression: $e"), backgroundColor: Colors.red)
      );
    }
  }

  // --- DIALOGUE D'APERÇU ---
  void _showTicketPreview(Map<String, dynamic> item) {
    bool isPeage = _accessType != 'EMBARQUEMENT';
    String date = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(item['datecreate']));

    showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.blue),
                const SizedBox(width: 10),
                const Text("Aperçu du Ticket"),
              ],
            ),
            content: SingleChildScrollView(
              child: Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 5)]
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(_provinceNom, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Text("--- $_siteNom ---", textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                    const Divider(thickness: 1),
                    Text(isPeage ? "TICKET PÉAGE" : "TAXE AÉROPORTUAIRE", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),

                    // ID Transaction
                    Text("ID: ${item['id']}", style: const TextStyle(fontFamily: 'monospace')),
                    Text("Date: $date", style: const TextStyle(fontFamily: 'monospace')),
                    const SizedBox(height: 15),

                    // Détails Spécifiques
                    if (isPeage) ...[
                      _buildRow("Catégorie:", item['categorie']),
                      _buildRow("Plaque:", item['immatriculation']),
                      if(item['num_sachet'] != null && item['num_sachet'].toString().isNotEmpty)
                        _buildRow("Sachet:", item['num_sachet']),
                    ] else ...[
                      _buildRow("Passager:", item['passager']),
                      _buildRow("Vol:", item['vol']),
                      _buildRow("Dest:", item['destination']),
                    ],

                    const Divider(),
                    // Montant
                    const Text("MONTANT PAYÉ", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                        "${item['montant']} ${item['devise']}",
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)
                    ),

                    const SizedBox(height: 15),
                    Text("Agent: $_agentName", style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Fermer", style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                onPressed: () => _reprintTicket(item),
                icon: const Icon(Icons.print),
                label: const Text("RÉ-IMPRIMER"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white),
              )
            ],
          );
        }
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Historique"),
        backgroundColor: Colors.blue[800], // Uniformisation couleur
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Actualiser",
            onPressed: _forceSync,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _transactions.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 10),
            const Text("Aucune transaction trouvée"),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _transactions.length,
        itemBuilder: (context, index) {
          final item = _transactions[index];
          final bool isSynced = item['is_synced'] == 1;

          String title = _accessType == 'EMBARQUEMENT'
              ? (item['passager'] ?? 'Inconnu')
              : (item['immatriculation'] ?? '---');

          String subtitle = _accessType == 'EMBARQUEMENT'
              ? "Vol: ${item['vol']} • Dest: ${item['destination']}"
              : "Cat: ${item['categorie']}";

          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
                side: BorderSide(
                    color: isSynced ? Colors.green : Colors.orange,
                    width: 2
                ),
                borderRadius: BorderRadius.circular(12)
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              onTap: () => _showTicketPreview(item), // <--- CLIC POUR VOIR LE TICKET
              leading: CircleAvatar(
                backgroundColor: isSynced ? Colors.green[100] : Colors.orange[100],
                child: Icon(
                  isSynced ? Icons.cloud_done : Icons.cloud_upload,
                  color: isSynced ? Colors.green[800] : Colors.orange[900],
                ),
              ),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(item['datecreate'])),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "${item['montant']} ${item['devise']}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue),
                  ),
                  const SizedBox(height: 5),
                  // Petit bouton imprimante visuel
                  const Icon(Icons.print, size: 16, color: Colors.grey),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}