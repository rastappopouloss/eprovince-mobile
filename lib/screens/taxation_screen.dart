import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_services.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../services/taxe_printer_service.dart';
import 'create_assujetti_screen.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';
import 'taxe_history_clean.dart';

class TaxationScreen extends StatefulWidget {
  const TaxationScreen({super.key});

  @override
  State<TaxationScreen> createState() => _TaxationScreenState();
}

class _TaxationScreenState extends State<TaxationScreen> {
  // --- VARIABLES ---

  // Listes de références
  List<Map<String, dynamic>> _articles = [];
  List<Map<String, dynamic>> _natures = [];
  List<Map<String, dynamic>> _fiscals = [];
  List<Map<String, dynamic>> _assujettisList = [];

  // --- EN-TÊTE ---
  int? _selectedFiscal;
  int? _selectedAssujettiId;
  String _selectedType = 'NON-FISCAL(TAXE)';
  String _selectedDevise = 'FC';

  // --- SAISIE LIGNE ---
  int? _selectedArticle;
  int? _selectedNature;
  String _currentNatureName = "";
  String _currentArticleName = "";
  String _currentNatureType = "FORFAIT"; // Par défaut

  final _nombreCtrl = TextEditingController(text: "1");
  double _taux = 0.0;
  String _periodicite = "";
  double _currentLineTotal = 0.0;

  // --- PANIER ---
  List<Map<String, dynamic>> _cart = [];
  double _grandTotal = 0.0;

  bool _isSaving = false;

  // Configuration Province & Taux
  String _provinceNom = "";
  String _provinceEntete = "";
  String _provinceCode = "";
  double _tauxProvince = 1.0;

  final Color _themeColor = Colors.teal.shade800;

  @override
  void initState() {
    super.initState();
    _loadRefs();
  }

  // Fonction utilitaire pour le formatage
  String _formatMontant(double montant, String devise) {
    if (devise == 'USD') {
      return montant.toStringAsFixed(5);
    } else {
      return montant.toStringAsFixed(2);
    }
  }

  // --- CHARGEMENT ---
  Future<void> _loadRefs() async {
    final db = DBService.instance;
    final prefs = await SharedPreferences.getInstance();

    final art = await db.getArticles();
    final fisc = await db.getFiscals();
    final assuj = await db.getAllAssujettis();

    if (mounted) {
      setState(() {
        _articles = art;
        _fiscals = fisc;
        _assujettisList = assuj;

        double lu = prefs.getDouble('config_province_taux') ?? 1.0;
        _tauxProvince = lu;

        _provinceNom = prefs.getString('config_province_nom') ?? "KINSHASA";
        _provinceEntete = prefs.getString('config_province_entete') ?? "PROVINCE";
        _provinceCode = prefs.getString('config_province_code') ?? "CODE";

        if (_fiscals.isNotEmpty && _selectedFiscal == null) {
          _selectedFiscal = _fiscals.first['id'] as int;
        }
      });
    }
  }

  // --- LOGIQUE SAISIE LIGNE ---

  Future<void> _onArticleChanged(int? articleId) async {
    if (articleId == null) return;
    final n = await DBService.instance.getNatures(articleId);
    final artObj = _articles.firstWhere((e) => e['id'] == articleId, orElse: () => {});

    if (mounted) {
      setState(() {
        _selectedArticle = articleId;
        _currentArticleName = artObj['activite'] ?? "Inconnu";
        _natures = n;
        _selectedNature = null;
        _taux = 0;
        _currentLineTotal = 0;
        _periodicite = "";

        // Reset nature quand on change de secteur
        _currentNatureType = "FORFAIT";
      });
    }
  }

  void _onNatureChanged(int? natureId) {
    if (natureId == null) return;

    final nature = _natures.firstWhere((e) => e['id'] == natureId,
        orElse: () => {'taux': 0.0, 'periodicite': '', 'nom': '', 'type': 'FORFAIT'});

    setState(() {
      _selectedNature = natureId;
      _currentNatureName = nature['nom'];

      // RECUPERATION DU TYPE (POURCENTAGE ou FORFAIT)
      _currentNatureType = nature['type'] ?? 'FORFAIT';

      _taux = (nature['taux'] as num?)?.toDouble() ?? 0.0;
      _periodicite = nature['periodicite']?.toString() ?? "";

      // UX : Si c'est un pourcentage, on vide le champ pour forcer la saisie du montant déclaré
      // Si c'est un forfait, on remet "1" par défaut
      if (_currentNatureType == 'POURCENTAGE') {
        _nombreCtrl.text = "";
      } else {
        _nombreCtrl.text = "1";
      }

      _calculateLineTotal();
    });
  }

  // --- CALCUL EXACT SELON LOGIQUE LARAVEL ---
  void _calculateLineTotal() {
    // Dans Laravel, $request->nombre est utilisé pour la quantité OU la valeur imposable
    double nombreSaisi = double.tryParse(_nombreCtrl.text) ?? 0.0;

    setState(() {
      // 1. Calcul de la base USD (Formule Laravel)
      double baseUSD = 0.0;

      if (_currentNatureType == 'POURCENTAGE') {
        // Laravel: ($request->nombre * $request->taux) / 100
        // Ici 'nombreSaisi' joue le rôle de la valeur imposable
        baseUSD = (nombreSaisi * _taux) / 100;
      } else {
        // Laravel: $request->nombre * $request->taux
        // Ici 'nombreSaisi' joue le rôle de la quantité
        baseUSD = nombreSaisi * _taux;
      }

      // 2. Conversion pour l'affichage selon le choix de l'agent
      if (_selectedDevise == 'USD') {
        _currentLineTotal = baseUSD;
      } else {
        _currentLineTotal = baseUSD * _tauxProvince;
      }
    });
  }

  // --- LOGIQUE PANIER ---

  void _addLineToCart() {
    if (_selectedArticle == null || _selectedNature == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Sélectionnez un secteur et une nature")));
      return;
    }

    // Le champ _nombreCtrl correspond à la colonne 'nombre' de ta DB (Quantité ou Valeur)
    int nombrePourDB = int.tryParse(_nombreCtrl.text) ?? 0;
    // Si c'est un gros montant (pourcentage), int peut être limite, mais pour l'instant on suit ta structure DB (nombre INTEGER)
    // Idéalement, la colonne 'nombre' devrait être REAL si tu taxes des montants décimaux, mais INTEGER passe pour des montants entiers.

    Map<String, dynamic> line = {
      'article_id': _selectedArticle,
      'article_nom': _currentArticleName,
      'nature_id': _selectedNature,
      'nature_nom': _currentNatureName,
      'nature_type': _currentNatureType, // Important pour DBService
      'taux': _taux,
      'nombre': nombrePourDB,
      'periodicite': _periodicite,
      'total': _currentLineTotal // Total affiché (converti ou non)
    };

    setState(() {
      _cart.add(line);
      _grandTotal += _currentLineTotal;

      _selectedNature = null;
      _taux = 0;
      _currentLineTotal = 0;
      _periodicite = "";
      _nombreCtrl.text = "1";
      _currentNatureType = "FORFAIT"; // Reset visuel
    });
  }

  void _removeLineFromCart(int index) {
    setState(() {
      _grandTotal -= (_cart[index]['total'] as double);
      _cart.removeAt(index);
    });
  }

  // --- LOGIQUE SAUVEGARDE ---

  Future<void> _saveAll() async {
    if (_selectedAssujettiId == null || _selectedFiscal == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Veuillez choisir un assujetti et un exercice"),
          backgroundColor: Colors.orange));
      return;
    }

    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Ajoutez au moins une ligne de taxe"),
          backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      int currentUserId = prefs.getInt('agent_id') ?? 0;

      // Header
      Map<String, dynamic> taxHeader = {
        'assujetti_id': _selectedAssujettiId,
        'fiscal_id': _selectedFiscal,
        'devise': _selectedDevise,
        'user_id': currentUserId,
        'taux_change': _tauxProvince,
        'type': _selectedType,
        'datecreate': DateTime.now().toIso8601String(),
        'datefin': "${DateTime.now().year}-12-31",
        'is_synced': 0
      };

      // Lignes (On passe le nature_type pour que DBService sache quelle formule utiliser)
      List<Map<String, dynamic>> cleanLines = _cart.map((line) {
        return {
          'article_id': line['article_id'],
          'nature_id': line['nature_id'],
          'nature_type': line['nature_type'], // IMPORTANT
          'taux': line['taux'],
          'nombre': line['nombre'],
          'total': line['total']
        };
      }).toList();

      int newId = await DBService.instance.insertFullTax(taxHeader, cleanLines);
      taxHeader['id'] = newId;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("✅ Taxation enregistrée avec succès !"),
            backgroundColor: Colors.green));

        Map<String, dynamic> agentInfo = {
          'nom': prefs.getString('agent_name') ?? 'Agent',
          'prenom': '',
        };

        final assujettiFull = _assujettisList.firstWhere((e) => e['id'] == _selectedAssujettiId);

        try {
          await TaxePrinterService().printTicket(
            taxData: taxHeader,
            assujetti: assujettiFull,
            lignes: _cart,
            agent: agentInfo,
            provEntete: _provinceEntete,
            provCode: _provinceCode,
          );
        } catch (e) {
          print("Erreur impression: $e");
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("⚠️ Erreur imprimante (Bluetooth ?)")));
        }

        setState(() {
          _cart.clear();
          _grandTotal = 0;
          _selectedNature = null;
          _selectedArticle = null;
          _nombreCtrl.text = "1";
        });
      }

      _handleSync();
    } catch (e) {
      print("Erreur Save: $e");
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- SYNC VISUELLE ---
  Future<void> _handleSync() async {
    await SyncService().syncEverything(onProgress: (message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            if (!message.contains("✅") && !message.contains("Pas d'internet"))
              const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: message.contains("✅") ? Colors.green : _themeColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    });
    await _loadRefs();
  }

  Future<void> _pickAssujetti() async {
    final result = await Navigator.push(context,
        MaterialPageRoute(builder: (context) => const CreateAssujettiScreen()));
    if (result != null && result is Map) {
      await _loadRefs();
      setState(() => _selectedAssujettiId = result['id']);
    }
  }

  void _showSearchModal(
      {required String title,
        required List<Map<String, dynamic>> items,
        required String keyLabel,
        required Function(int) onSelected}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        List<Map<String, dynamic>> filteredItems = List.from(items);
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setModalState) {
                void filterList(String query) {
                  setModalState(() {
                    if (query.isEmpty) {
                      filteredItems = List.from(items);
                    } else {
                      filteredItems = items
                          .where((item) => (item[keyLabel] ?? "")
                          .toString()
                          .toLowerCase()
                          .contains(query.toLowerCase()))
                          .toList();
                    }
                  });
                }
                return Container(
                  decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                        child: Row(
                          children: [
                            IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(context)),
                            Expanded(
                                child: Text("Choisir $title",
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center)),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: TextField(
                          autofocus: true,
                          decoration: InputDecoration(
                              hintText: "Rechercher...",
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              filled: true,
                              fillColor: Colors.grey.shade100),
                          onChanged: filterList,
                        ),
                      ),
                      Expanded(
                        child: filteredItems.isEmpty
                            ? const Center(child: Text("Aucun résultat"))
                            : ListView.separated(
                          controller: scrollController,
                          itemCount: filteredItems.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];
                            return ListTile(
                              title: Text((item[keyLabel] ?? "Inconnu").toString(), style: const TextStyle(fontSize: 16)),
                              onTap: () {
                                Navigator.pop(context);
                                onSelected(item['id']);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Déconnexion"),
        content: const Text("Voulez-vous vraiment fermer votre session ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("NON")),
          TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await AuthService().logout();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
              },
              child: const Text("OUI, QUITTER", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  InputDecoration _buildInputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label.isEmpty ? null : label, // Permet de cacher le label si vide
      labelStyle: TextStyle(color: Colors.grey[700], fontSize: 13),
      prefixIcon: Icon(icon, color: _themeColor, size: 22),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _themeColor, width: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("GUICHET TAXATION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: _themeColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard),
            tooltip: "Aller au Dashboard",
            onPressed: () {
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const DashboardScreen()), (route) => false);
            },
          ),
          IconButton(
              icon: const Icon(Icons.history),
              tooltip: "Historique",
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const TaxeHistoryScreen()));
              }),
          IconButton(icon: const Icon(Icons.sync), tooltip: "Synchroniser", onPressed: _handleSync),
          IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: _handleLogout),
        ],
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0, left: 0, right: 0, height: 100,
            child: Container(decoration: BoxDecoration(color: _themeColor, borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)))),
          ),
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // --- CARTE 1 : EN-TÊTE ---
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.person_pin, color: _themeColor),
                                  const SizedBox(width: 10),
                                  const Text("Infos Assujetti", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const Divider(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      value: _selectedAssujettiId,
                                      isExpanded: true,
                                      decoration: _buildInputDeco("Nom de l'assujetti", Icons.person),
                                      items: _assujettisList.map((e) => DropdownMenuItem(value: e['id'] as int, child: Text("${e['nom']} ${e['postnom'] ?? ''}", overflow: TextOverflow.ellipsis))).toList(),
                                      onChanged: (v) => setState(() => _selectedAssujettiId = v),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    decoration: BoxDecoration(color: _themeColor, borderRadius: BorderRadius.circular(12)),
                                    child: IconButton(icon: const Icon(Icons.add, color: Colors.white), onPressed: _pickAssujetti, tooltip: "Créer nouveau"),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: DropdownButtonFormField<String>(
                                      value: _selectedType,
                                      isExpanded: true,
                                      decoration: _buildInputDeco("Type Acte", Icons.description),
                                      items: const [DropdownMenuItem(value: 'NON-FISCAL(TAXE)', child: Text('NON-FISCAL(TAXE)')), DropdownMenuItem(value: 'FISCAL(IMPOT)', child: Text('FISCAL(IMPOT)'))],
                                      onChanged: (v) => setState(() => _selectedType = v!),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<int>(
                                      value: _selectedFiscal,
                                      isExpanded: true,
                                      decoration: _buildInputDeco("Année", Icons.calendar_today),
                                      items: _fiscals.map((e) => DropdownMenuItem(value: e['id'] as int, child: Text(e['nom'].toString()))).toList(),
                                      onChanged: (v) => setState(() => _selectedFiscal = v),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<String>(
                                      value: _selectedDevise,
                                      isExpanded: true,
                                      decoration: _buildInputDeco("Devise", Icons.monetization_on),
                                      items: const [
                                        DropdownMenuItem(value: 'FC', child: Text('FC', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DropdownMenuItem(value: 'USD', child: Text('USD', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                                      ],
                                      onChanged: (v) => setState(() {
                                        _selectedDevise = v!;
                                        _calculateLineTotal();
                                      }),
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // --- CARTE 2 : SAISIE LIGNE (AMÉLIORÉE UX) ---
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.add_shopping_cart, color: _themeColor),
                                  const SizedBox(width: 10),
                                  const Text("Ajouter une ligne", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const Divider(height: 20),
                              InkWell(
                                onTap: () => _showSearchModal(title: "un Secteur", items: _articles, keyLabel: 'activite', onSelected: (id) => _onArticleChanged(id)),
                                child: IgnorePointer(
                                  child: TextFormField(
                                    controller: TextEditingController(text: _currentArticleName.isNotEmpty ? _currentArticleName : null),
                                    decoration: _buildInputDeco("Secteur d'activité", Icons.business).copyWith(hintText: "Appuyez pour choisir...", suffixIcon: const Icon(Icons.arrow_drop_down)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              InkWell(
                                onTap: () {
                                  if (_selectedArticle == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Choisissez d'abord un secteur")));
                                    return;
                                  }
                                  _showSearchModal(title: "une Nature", items: _natures, keyLabel: 'nom', onSelected: (id) => _onNatureChanged(id));
                                },
                                child: IgnorePointer(
                                  child: TextFormField(
                                    controller: TextEditingController(text: _currentNatureName.isNotEmpty ? _currentNatureName : null),
                                    decoration: _buildInputDeco("Nature de l'acte", Icons.category).copyWith(hintText: "Appuyez pour choisir...", suffixIcon: const Icon(Icons.arrow_drop_down)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // --- BLOC DYNAMIQUE UX ---
                              if (_selectedNature != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: _currentNatureType == 'POURCENTAGE' ? Colors.orange[50] : Colors.teal[50], // Couleur conditionnelle
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: _currentNatureType == 'POURCENTAGE' ? Colors.orange.shade200 : Colors.teal.shade200)
                                  ),
                                  child: Column(
                                    children: [
                                      // Indicateur visuel
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                                color: _currentNatureType == 'POURCENTAGE' ? Colors.orange : _themeColor,
                                                borderRadius: BorderRadius.circular(8)
                                            ),
                                            child: Text(
                                              _currentNatureType == 'POURCENTAGE' ? "TYPE : POURCENTAGE (%)" : "TYPE : FORFAIT (PRIX FIXE)",
                                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            _currentNatureType == 'POURCENTAGE'
                                                ? "Taux : $_taux %"
                                                : "P.U : $_taux USD",
                                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800]),
                                          ),
                                        ],
                                      ),
                                      const Divider(),

                                      // Champ de saisie avec Label dynamique
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                    _currentNatureType == 'POURCENTAGE'
                                                        ? "Montant Imposable / Valeur :" // Label explicite
                                                        : "Quantité / Nombre :",
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)
                                                ),
                                                Text("Change: $_tauxProvince FC", style: TextStyle(fontSize: 11, color: Colors.grey[700], fontStyle: FontStyle.italic)),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            width: 120,
                                            child: TextField(
                                              controller: _nombreCtrl,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              style: TextStyle(color: _themeColor, fontWeight: FontWeight.bold, fontSize: 16),
                                              decoration: _buildInputDeco("", _currentNatureType == 'POURCENTAGE' ? Icons.attach_money : Icons.numbers)
                                                  .copyWith(hintText: "0", contentPadding: const EdgeInsets.symmetric(horizontal: 10)),
                                              onChanged: (v) => _calculateLineTotal(),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(),

                                      // Total Ligne
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("TOTAL LIGNE:", style: TextStyle(color: _themeColor, fontWeight: FontWeight.bold)),
                                          Text("${_formatMontant(_currentLineTotal, _selectedDevise)} $_selectedDevise",
                                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _themeColor)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 15),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _addLineToCart,
                                    icon: const Icon(Icons.check),
                                    label: const Text("AJOUTER AU PANIER"),
                                    style: ElevatedButton.styleFrom(backgroundColor: _themeColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                                  ),
                                )
                              ]
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // --- CARTE 3 : PANIER ---
                        if (_cart.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                            child: Text("PANIER DES TAXES", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          ),
                          ..._cart.asMap().entries.map((entry) {
                            double tauxLigne = (entry.value['taux'] as num).toDouble();
                            double totalLigne = (entry.value['total'] as num).toDouble();
                            int qte = entry.value['nombre'];
                            String type = entry.value['nature_type'] ?? 'FORFAIT';

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: Colors.teal[100], child: Text("${entry.key + 1}", style: TextStyle(color: _themeColor, fontWeight: FontWeight.bold))),
                                title: Text(entry.value['nature_nom'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                subtitle: _selectedDevise == 'FC'
                                    ? Text(
                                  // Formule d'affichage adaptée au type (Pourcentage ou Forfait)
                                  type == 'POURCENTAGE'
                                      ? "($qte x $tauxLigne%) x $_tauxProvince = ${_formatMontant(totalLigne, 'FC')} FC"
                                      : "$tauxLigne\$ x $qte x $_tauxProvince = ${_formatMontant(totalLigne, 'FC')} FC",
                                  style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                                )
                                    : Text(
                                  type == 'POURCENTAGE'
                                      ? "($qte x $tauxLigne%) = ${_formatMontant(totalLigne, 'USD')} USD"
                                      : "$tauxLigne\$ x $qte = ${_formatMontant(totalLigne, 'USD')} USD",
                                  style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                                ),
                                trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _removeLineFromCart(entry.key)),
                              ),
                            );
                          }).toList(),
                        ],
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -5))]),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("TOTAL À PAYER", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                  Builder(builder: (context) {
                    if (_selectedDevise == 'FC') {
                      return Text("${_formatMontant(_grandTotal, 'FC')} FC", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _themeColor));
                    } else {
                      return Text("${_formatMontant(_grandTotal, 'USD')} USD", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green[800]));
                    }
                  }),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: (_isSaving || _cart.isEmpty) ? null : _saveAll,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), backgroundColor: _themeColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 4),
              icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.print),
              label: Text(_isSaving ? "..." : "ENREGISTRER"),
            )
          ],
        ),
      ),
    );
  }
}