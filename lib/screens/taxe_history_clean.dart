import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/db_service.dart';
import '../services/taxe_printer_service.dart'; // Assure-toi d'avoir cet import

class TaxeHistoryScreen extends StatefulWidget {
  const TaxeHistoryScreen({super.key});

  @override
  State<TaxeHistoryScreen> createState() => _TaxeHistoryScreenState();
}

class _TaxeHistoryScreenState extends State<TaxeHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Listes de données
  List<Map<String, dynamic>> _pendingList = [];
  List<Map<String, dynamic>> _syncedList = [];
  bool _isLoading = true;

  // Contexte pour l'impression
  String _agentName = "Agent";
  String _provinceNom = "KINSHASA";
  String _provinceEntete = "";
  String _provinceCode = "";
  /*
     String _provinceEntete = ""; */

  // Couleur du thème Taxe (Teal)
  final Color _themeColor = Colors.teal.shade800;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadContext(); // Charger les infos agent/province
    _loadData();
  }

  Future<void> _loadContext() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _agentName = prefs.getString('agent_name') ?? "Agent";
      _provinceEntete = prefs.getString('config_province_entete') ?? "PROVINCE";
      _provinceCode = prefs.getString('config_province_code') ?? "CODE";
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    // 0 = En attente, 1 = Synchronisé
    final pending = await DBService.instance.getTaxHistory(0);
    final synced = await DBService.instance.getTaxHistory(1);

    if (mounted) {
      setState(() {
        _pendingList = pending;
        _syncedList = synced;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteTax(int id) async {
    bool confirm = await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Supprimer ?"),
          content: const Text("Voulez-vous vraiment supprimer cet enregistrement ?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui", style: TextStyle(color: Colors.red))),
          ],
        )
    ) ?? false;

    if (confirm) {
      await DBService.instance.deleteTax(id);
      _loadData();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enregistrement supprimé")));
    }
  }

  // --- LOGIQUE D'APERÇU ET IMPRESSION ---

  // --- DIALOGUE D'APERÇU CORRIGÉ ---
  void _showTicketPreview(Map<String, dynamic> taxItem) async {
    String devise = taxItem['devise'] ?? 'FC';
    // 1. Loader pendant le chargement des détails
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator())
    );

    List<Map<String, dynamic>> lines = [];
    try {
      lines = await DBService.instance.getTaxLines(taxItem['id']);
    } catch (e) {
      print("Erreur recup lignes: $e");
    }

    if (!mounted) return;
    Navigator.pop(context); // Fermer le loader

    // 2. Calcul du total
    double totalCalc = lines.fold(0.0, (sum, item) => sum + (item['total'] as num).toDouble());
    String date = _formatDate(taxItem['datecreate']);
    //String devise = taxItem['devise'] ?? 'FC';

    // 3. Afficher le Dialogue
    showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            // En-tête du dialogue
            title: Row(
              children: [
                Icon(Icons.receipt_long, color: _themeColor),
                const SizedBox(width: 10),
                const Text("Aperçu Quittance", style: TextStyle(fontSize: 18)),
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
                  crossAxisAlignment: CrossAxisAlignment.center, // Centrer le contenu global
                  children: [
                    // EN-TÊTE TICKET
                    Text(_provinceEntete.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text("PREUVE DE PAIEMENT", style: TextStyle(fontWeight: FontWeight.bold, color: _themeColor, fontSize: 14)),
                    const Divider(thickness: 1.5),

                    // INFO GÉNÉRALES (Alignées à gauche)
                    _buildRow("Quittance N°:", "${taxItem['id']}"),
                    _buildRow("Date:", date),
                    _buildRow("Assujetti:", "${taxItem['nom']} ${taxItem['postnom'] ?? ''}"),

                    const Divider(),
                    const Align(
                        alignment: Alignment.centerLeft,
                        child: Text("DÉTAILS:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))
                    ),
                    const SizedBox(height: 5),

                    // LISTE DES DÉTAILS (CORRIGÉE)
                    ...lines.map((l) {
                      double ligneTotal = (l['total'] as num).toDouble();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start, // Important pour le texte long
                          children: [
                            // Description (Prend toute la place dispo)
                            Expanded(
                                flex: 3,
                                child: Text(
                                  "- ${l['nature_nom'] ?? 'Taxe'}",
                                  style: const TextStyle(fontSize: 12, height: 1.3),
                                )
                            ),
                            const SizedBox(width: 8),
                            // Montant (Prend la place nécessaire, aligné droite)
                            Expanded(
                              flex: 2,
                              child: Text(
                                //"${ligneTotal.toStringAsFixed(2)} $devise", // <--- ARRONDISSEMENT ICI
                                // CONDITION TERNAIRE POUR LE FORMATAGE
                                "${(l['total'] as num).toStringAsFixed(devise == 'USD' ? 5 : 2)} $devise",
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    const Divider(thickness: 1.5),

                    // TOTAL GÉNÉRAL (CORRECTION DU RENDU)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end, // Aligne le texte sur la ligne de base
                      children: [
                        const Text("TOTAL PAYÉ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(width: 10), // Espace de sécurité

                        // Flexible permet au montant de passer à la ligne si vraiment trop grand
                        Flexible(
                          child: Text(
                              //"${totalCalc.toStringAsFixed(2)} $devise", // <--- ARRONDISSEMENT ICI
                            // CONDITION TERNAIRE POUR LE FORMATAGE
                              "${totalCalc.toStringAsFixed(devise == 'USD' ? 5 : 2)} $devise",
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _themeColor)
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 15),
                    Text("Taxateur: $_agentName", style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey)),
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
                onPressed: () {
                  Navigator.pop(ctx);
                  _reprintTicket(taxItem, lines);
                },
                icon: const Icon(Icons.print),
                label: const Text("RÉ-IMPRIMER"),
                style: ElevatedButton.styleFrom(backgroundColor: _themeColor, foregroundColor: Colors.white),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Future<void> _reprintTicket(Map<String, dynamic> taxItem, List<Map<String, dynamic>> lines) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Envoi à l'imprimante...")));

    // Reconstruction des Maps nécessaires pour le service d'impression
    Map<String, dynamic> assujettiMap = {
      'nom': taxItem['nom'],
      'postnom': taxItem['postnom'],
      'telephone': taxItem['telephone'] ?? '',
      'territoire_nom': taxItem['territoire_nom'] ?? '', // Assure-toi que ta requête getTaxHistory récupère ça
      'quartier_nom': taxItem['quartier_nom'] ?? '',
      'adresse': taxItem['adresse'] ?? ''
    };

    Map<String, dynamic> agentMap = {
      'nom': _agentName,
      'prenom': ''
    };

    try {
      await TaxePrinterService().printTicket(
          taxData: taxItem,
          assujetti: assujettiMap,
          agent: agentMap,
          lignes: lines,
          provEntete: _provinceEntete,
          provCode: _provinceCode
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur impression: $e"), backgroundColor: Colors.red)
      );
    }
  }

  String _formatDate(String isoDate) {
    try {
      DateTime dt = DateTime.parse(isoDate);
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (e) {
      return isoDate;
    }
  }

  Widget _buildList(List<Map<String, dynamic>> data, bool isPending) {
    if (data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isPending ? Icons.cloud_off : Icons.cloud_done, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text(isPending ? "Aucun élément en attente" : "Aucun historique synchronisé", style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: data.length,
      itemBuilder: (context, index) {
        final item = data[index];
        final String nom = "${item['nom'] ?? 'Inconnu'} ${item['postnom'] ?? ''}";

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
              side: BorderSide(color: isPending ? Colors.orange.shade200 : Colors.green.shade200, width: 1),
              borderRadius: BorderRadius.circular(12) // Plus arrondi
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            // --- CLIC POUR APERÇU ---
            onTap: () => _showTicketPreview(item),
            leading: CircleAvatar(
              backgroundColor: isPending ? Colors.orange[100] : Colors.green[100],
              child: Icon(
                  isPending ? Icons.hourglass_empty : Icons.check,
                  color: isPending ? Colors.orange[800] : Colors.green[800]
              ),
            ),
            title: Text(nom, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(item['type'] ?? 'TAXE', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                Text(_formatDate(item['datecreate']), style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            trailing: isPending
                ? IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _deleteTax(item['id']),
            )
                : Column( // Affichage montant + icône
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Icon(Icons.print, color: Colors.grey, size: 20),
                // Tu peux ajouter le montant ici si ta requête SQL le retourne (ex: item['total_taxe'])
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mes Enregistrements"),
        backgroundColor: _themeColor, // Uniformisation
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: "EN ATTENTE (${_pendingList.length})", icon: const Icon(Icons.sync_problem)),
            Tab(text: "SYNCHRONISÉS (${_syncedList.length})", icon: const Icon(Icons.cloud_done)),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _themeColor))
          : TabBarView(
        controller: _tabController,
        children: [
          _buildList(_pendingList, true),
          _buildList(_syncedList, false),
        ],
      ),
    );
  }
}