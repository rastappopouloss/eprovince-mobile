import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart'; // Optionnel si tu veux sync direct

class CreateAssujettiScreen extends StatefulWidget {
  const CreateAssujettiScreen({super.key});

  @override
  State<CreateAssujettiScreen> createState() => _CreateAssujettiScreenState();
}

class _CreateAssujettiScreenState extends State<CreateAssujettiScreen> {
  final _formKey = GlobalKey<FormState>();

  // --- CONTRÔLEURS TEXTE ---
  final _nomCtrl = TextEditingController();
  final _postnomCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _adresseCtrl = TextEditingController();
  final _nationaliteCtrl = TextEditingController(text: "CONGOLAISE");

  // --- VARIABLES GÉOGRAPHIE (Restaurées) ---
  List<Map<String, dynamic>> _territoires = [];
  List<Map<String, dynamic>> _quartiers = [];
  int? _selectedTerritoire;
  int? _selectedQuartier;

  // --- VARIABLES TYPE & CATEGORIE ---
  int _selectedType = 1; // 1=Physique par défaut
  String _selectedCategorie = 'SPONTANE';

  final List<Map<String, dynamic>> _types = [
    {'value': 1, 'label': 'Personne Physique'},
    {'value': 2, 'label': 'Personne Morale'},
    {'value': 3, 'label': 'ONG'},
  ];

  final List<String> _categories = ['SPONTANE', 'DECLARATIF'];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadTerritoires(); // Chargement au démarrage
  }

  // --- LOGIQUE GÉOGRAPHIE ---
  Future<void> _loadTerritoires() async {
    final data = await DBService.instance.getTerritoires();
    if (mounted) {
      setState(() {
        _territoires = data;
      });
    }
  }

  Future<void> _onTerritoireChanged(int? id) async {
    if (id == null) return;
    final data = await DBService.instance.getQuartiers(id);
    if (mounted) {
      setState(() {
        _selectedTerritoire = id;
        _quartiers = data;
        _selectedQuartier =
            null; // Reset quartier quand on change de territoire
      });
    }
  }

  // --- ENREGISTREMENT ---
  Future<void> _saveAssujetti() async {
    if (!_formKey.currentState!.validate()) return;

    // Validation Géographique
    if (_selectedTerritoire == null || _selectedQuartier == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Veuillez sélectionner un territoire et un quartier"),
          backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      // Récupération des configs de l'agent
      int provId = prefs.getInt('config_province_id') ?? 1;
      int villeId = prefs.getInt('config_ville_id') ?? 1;

      Map<String, dynamic> newAssujetti = {
        'nom': _nomCtrl.text.toUpperCase(),
        'postnom': _postnomCtrl.text.toUpperCase(),
        'prenom': _prenomCtrl.text,
        'telephone': _telCtrl.text,
        'adresse': _adresseCtrl.text,
        'nationalite': _nationaliteCtrl.text, // Nouveau champ

        'type': _selectedType, // Nouveau champ
        'categorie': _selectedCategorie, // Nouveau champ

        'email': '',

        // GÉOGRAPHIE COMPLÈTE
        'province_id': provId,
        'ville_id': villeId,
        'territoire_id': _selectedTerritoire, // Restauré
        'quartier_id': _selectedQuartier, // Restauré

        'is_synced': 0,
        'datecreate': DateTime.now().toIso8601String(),
      };

      // Insertion via DBService
      int id = await DBService.instance.insertAssujetti(newAssujetti);

      // Optionnel : Lancer la sync en arrière-plan
      // SyncService().syncAssujettis();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("✅ Assujetti créé avec succès !"),
            backgroundColor: Colors.green));
        Navigator.pop(context,
            {'id': id, 'name': "${_nomCtrl.text} ${_postnomCtrl.text}"});
      }
    } catch (e) {
      print("Erreur Création: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nouvel Assujetti")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- SECTION 1 : TYPE & CATÉGORIE ---
              const Text("CLASSIFICATION",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.blue)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedType,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: "Type",
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5)),
                      items: _types
                          .map((t) => DropdownMenuItem<int>(
                              value: t['value'],
                              child: Text(
                                t['label'],
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              )))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedType = v!),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedCategorie,
                      isExpanded: true,
                      // <--- AJOUT CRUCIAL 1
                      decoration: const InputDecoration(
                          labelText: "Catégorie",
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5)),
                      items: _categories
                          .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                c,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              )))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCategorie = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // --- SECTION 2 : IDENTITÉ ---
              const Text("IDENTITÉ",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.blue)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildField(_nomCtrl, "Nom", required: true)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _buildField(_postnomCtrl, "Post-nom",
                          required: true)),
                ],
              ),
              const SizedBox(height: 15),
              _buildField(_prenomCtrl, "Prénom"),
              const SizedBox(height: 15),
              _buildField(_nationaliteCtrl, "Nationalité", icon: Icons.flag),

              const SizedBox(height: 20),

              // --- SECTION 3 : LOCALISATION (RESTAURÉE) ---
              const Text("LOCALISATION",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.blue)),
              const SizedBox(height: 10),

              // TERRITOIRE
              DropdownButtonFormField<int>(
                value: _selectedTerritoire,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: "Territoire / Commune",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.map)),
                items: _territoires
                    .map((e) => DropdownMenuItem(
                        value: e['id'] as int,
                        child: Text(e['nom'].toString())))
                    .toList(),
                onChanged: _onTerritoireChanged,
                hint: _territoires.isEmpty
                    ? const Text("Liste vide (Sync requise)")
                    : null,
              ),
              const SizedBox(height: 15),

              // QUARTIER
              DropdownButtonFormField<int>(
                value: _selectedQuartier,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: "Quartier",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_city)),
                items: _quartiers
                    .map((e) => DropdownMenuItem(
                        value: e['id'] as int,
                        child: Text(e['nom'].toString())))
                    .toList(),
                onChanged: (v) => setState(() => _selectedQuartier = v),
                hint: const Text("Sélectionnez d'abord un territoire"),
                disabledHint: const Text("Sélectionnez d'abord un territoire"),
              ),
              const SizedBox(height: 15),

              // ADRESSE PHYSIQUE
              _buildField(_adresseCtrl, "Numéro / Avenue",
                  icon: Icons.home, required: true),

              const SizedBox(height: 20),

              // --- SECTION 4 : CONTACT ---
              const Text("CONTACT",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.blue)),
              const SizedBox(height: 10),
              _buildField(_telCtrl, "Téléphone",
                  type: TextInputType.phone, icon: Icons.phone, required: true),

              const SizedBox(height: 30),

              // --- BOUTON ---
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveAssujetti,
                  icon: const Icon(Icons.save),
                  label: Text(
                      _isSaving ? "ENREGISTREMENT..." : "CRÉER L'ASSUJETTI"),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                      foregroundColor: Colors.white),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label,
      {TextInputType type = TextInputType.text,
      IconData? icon,
      bool required = false}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: icon != null ? Icon(icon) : null,
      ),
      validator: (v) =>
          required && (v == null || v.isEmpty) ? "Ce champ est requis" : null,
    );
  }
}
