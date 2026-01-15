import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'db_service.dart';

class SyncService {
  // Assurez-vous que cette IP est bien celle de votre serveur Laravel
  //final String baseUrl = "http://10.217.152.193:8000/api";
  final String baseUrl = "https://test.e-province.com/api";

  /// Fonction principale avec suivi de progression
  // On ajoute le paramètre {Function(String)? onProgress}
  Future<void> syncEverything({Function(String)? onProgress}) async {

    // Helper pour envoyer le message si le callback existe
    void notify(String msg) {
      if (onProgress != null) onProgress(msg);
      print("🔄 SYNC: $msg");
    }

    notify("Vérification de la connexion...");

    // 1. Vérif connexion
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      notify("Pas d'internet. Synchronisation annulée.");
      return;
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('auth_token');

    if (token == null) return;

    notify("Démarrage de la synchronisation...");

    // ENVOI DONNÉES
    notify("1/5 : Envoi des Péages...");
    await _syncPeages(token);

    notify("2/5 : Envoi des Embarquements...");
    await _syncEmbarquements(token);

    notify("3/5 : Envoi des Nouveaux Assujettis...");
    await syncAssujettis();

    notify("4/5 : Envoi des Taxes...");
    await syncTaxes();

    // RÉCEPTION DONNÉES
    notify("5/5 : Téléchargement des mises à jour...");
    await downloadRefs();

    notify("✅ Tout est synchronisé !");
  }

  // --- PARTIE 1 : SYNCHRONISATION DES PÉAGES ---
  Future<void> _syncPeages(String token) async {
    final db = DBService.instance;

    try {
      // A. Récupérer données locales non sync
      List<Map<String, dynamic>> unsynced = await db.getUnsyncedPeages();
      if (unsynced.isEmpty) return;

      // B. Préparer le payload
      List<Map<String, dynamic>> payload = unsynced.map((e) {
        Map<String, dynamic> map = Map.from(e);
        map['local_id'] = e['id']; // Important pour le retour
        map.remove('id');
        map.remove('is_synced');
        return map;
      }).toList();

      // C. Envoi à Laravel
      final response = await http.post(
        Uri.parse('$baseUrl/sync/peages'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'data': payload}),
      );

      // D. Traitement réponse
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        List<dynamic> syncedIds = responseData['synced_ids'];

        if (syncedIds.isNotEmpty) {
          // Note : Assurez-vous que markAsSynced existe dans DBService pour les péages
          // Si vous l'avez renommé markPeagesAsSynced, changez-le ici
          await db.markAsSynced(syncedIds.cast<int>());
          print("🚚 Péages synchronisés : ${syncedIds.length}");
        }
      } else {
        print("Erreur Serveur Péage: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("Erreur Sync Péage: $e");
    }
  }

  // --- PARTIE 2 : SYNCHRONISATION DES EMBARQUEMENTS ---
  Future<void> _syncEmbarquements(String token) async {
    final db = DBService.instance;

    try {
      List<Map<String, dynamic>> unsynced = await db.getUnsyncedEmbarquements();
      if (unsynced.isEmpty) return;

      print("📦 Envoi de ${unsynced.length} embarquements...");

      // Préparation des données
      List<Map<String, dynamic>> payload = unsynced.map((e) {
        Map<String, dynamic> map = Map.from(e);
        map['local_id'] = e['id'];
        map.remove('id');        // On retire l'ID local
        map.remove('is_synced'); // On retire le statut
        // Note : On laisse 'user_id', 'site_id', etc.
        return map;
      }).toList();

      print("DATA ENVOYÉ : ${jsonEncode({'data': payload})}"); // AFFICHE LE JSON

      final response = await http.post(
        Uri.parse('$baseUrl/sync/embarquements'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'Accept': 'application/json' // Important pour avoir les erreurs Laravel en JSON
        },
        body: jsonEncode({'data': payload}),
      );

      print("CODE RETOUR : ${response.statusCode}");
      print("RÉPONSE SERVEUR : ${response.body}");

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        List<dynamic> syncedIds = responseData['synced_ids'];
        if (syncedIds.isNotEmpty) {
          await db.markEmbarquementsAsSynced(syncedIds.cast<int>());
          print("✅ Synchronisation réussie !");
        }
      } else {
        print("❌ ÉCHEC SYNC : Le serveur a refusé les données.");
      }
    } catch (e) {
      print("💥 ERREUR RÉSEAU/CODE : $e");
    }
  }

  // 1. TÉLÉCHARGER LES CONFIGS (À appeler dans initState du Dashboard ou Home)
  Future<void> downloadRefs() async {
    print("🔵 [SYNC] Démarrage du téléchargement des références...");
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    try {
      final response = await http.get(
          Uri.parse('$baseUrl/references'),
          headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        List fiscals = data['fiscals'] ?? [];
        List articles = data['articles'] ?? [];
        List natures = data['natures'] ?? [];

        print("📊 Réception: ${fiscals.length} Fiscals, ${articles.length} Articles, ${natures.length} Natures");

        final db = DBService.instance;
        final dbase = await db.database;

        await dbase.transaction((txn) async {
          // 1. On vide les tables
          await txn.delete('fiscals');
          await txn.delete('articles');
          await txn.delete('natures');



          Batch batch = txn.batch();

          // 2. On insère SEULEMENT les champs qui existent dans SQLite

          // --- FISCALS (id, nom) ---
          for(var item in fiscals) {
            batch.insert('fiscals', {
              'id': item['id'],
              'nom': item['nom'],
              // On IGNORE user_id, created_at, etc.
            });
          }

          // --- ARTICLES (id, activite, province_id) ---
          for(var item in articles) {
            batch.insert('articles', {
              'id': item['id'],
              // Attention : Laravel envoie peut-être 'nom' ou 'activite', on gère les deux cas
              'activite': item['activite'] ?? item['nom'] ?? 'Inconnu',
              'province_id': item['province_id'],
            });
          }

          // --- NATURES (id, article_id, nom, type, taux, periodicite) ---
          for(var item in natures) {
            batch.insert('natures', {
              'id': item['id'],
              'article_id': item['article_id'],
              'nom': item['nom'],
              'type': item['type'] ?? 'FORFAIT', // Valeur par défaut au cas où
              'taux': item['taux'],
              'periodicite': item['periodicite'] ?? 'Mensuel',
            });
          }

          // 4. TERRITOIRES (Vérifie les noms de clés JSON !)
          List terr = data['territoires'] ?? [];
          print("📊 Territoires reçus : ${terr.length}"); // <--- AJOUTE CE PRINT

          await txn.delete('territoires');
          for(var item in terr) {
            batch.insert('territoires', {
              'id': item['id'],
              'nom': item['nom'],
              'ville_id': item['ville_id']
            });
          }

          // 5. QUARTIERS
          List quart = data['quartiers'] ?? [];
          print("📊 Quartiers reçus : ${quart.length}"); // <--- AJOUTE CE PRINT

          await txn.delete('quartiers');
          for(var item in quart) {
            batch.insert('quartiers', {
              'id': item['id'],
              'nom': item['nom'],
              'territoire_id': item['territoire_id']
            });
          }

          // --- ASSUJETTIS (id, nom, postnom, prenom) ---
          // ... (Dans downloadRefs, à l'intérieur de la transaction txn) ...

          // --- GESTION INTELLIGENTE DES ASSUJETTIS ---
          List assujettis = data['assujettis'] ?? [];
          print("📊 Assujettis reçus : ${assujettis.length}");

          for(var item in assujettis) {
            int serverId = item['id'];

            // 1. On vérifie si cet ID existe déjà en local
            List<Map> existing = await txn.query(
                'assujettis',
                where: 'id = ?',
                whereArgs: [serverId]
            );

            if (existing.isNotEmpty) {
              // Il y a un conflit !
              var localAssujetti = existing.first;

              if (localAssujetti['is_synced'] == 0) {
                // DANGER : C'est une donnée locale non envoyée !
                // On ne doit PAS l'écraser. On la déplace.

                print("⚠️ Conflit détecté sur ID $serverId (Donnée locale). Déplacement...");

                // On génère un nouvel ID temporaire unique (basé sur le temps)
                int newTempId = DateTime.now().millisecondsSinceEpoch + serverId;

                // A. On déplace l'assujetti local vers le nouvel ID
                await txn.update(
                    'assujettis',
                    {'id': newTempId},
                    where: 'id = ?',
                    whereArgs: [serverId]
                );

                // B. IMPORTANT : On met à jour les TAXES liées à cet ancien ID
                await txn.update(
                    'taxes',
                    {'assujetti_id': newTempId},
                    where: 'assujetti_id = ?',
                    whereArgs: [serverId]
                );

                print("✅ Assujetti local $serverId déplacé vers $newTempId. Taxes mises à jour.");
              }
            }

            // 2. Maintenant que la place est libre, on insère la donnée du serveur
            // On utilise REPLACE pour écraser seulement si c'était une donnée déjà sync (is_synced=1)
            batch.insert(
              'assujettis',
              {
                'id': item['id'],
                'nom': item['nom'],
                'postnom': item['postnom'],
                'prenom': item['prenom'],
                'telephone': item['telephone'],
                'adresse': item['adresse'],
                'province_id': item['province_id'],
                'ville_id': item['ville_id'],
                'territoire_id': item['territoire_id'],
                'quartier_id': item['quartier_id'],
                'is_synced': 1
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }

          await batch.commit(noResult: true);
        });

        print("✅ [SYNC] Données insérées et filtrées avec succès !");

      } else {
        print("❌ Erreur Serveur downloadref: ${response.body}");
      }
    } catch (e) {
      print("💥 Erreur pendant la sync : $e");
    }
  }

  Future<void> syncAssujettis() async {
    final db = DBService.instance;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    try {
      List<Map<String, dynamic>> unsynced = await db.getUnsyncedAssujettis();
      if (unsynced.isEmpty) return;

      print("📤 Envoi de ${unsynced.length} nouveaux assujettis...");

      // On prépare les données (ajout local_id)
      List<Map<String, dynamic>> payload = unsynced.map((e) {
        Map<String, dynamic> map = Map.from(e);
        map['local_id'] = e['id'];
        return map;
      }).toList();

      final response = await http.post(
        Uri.parse('$baseUrl/sync/assujettis'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'data': payload}),
      );

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        List<dynamic> ids = resData['synced_ids'];
        await db.markAssujettisAsSynced(ids.cast<int>());
        print("✅ Assujettis synchronisés !");
      } else {
        print("❌ Erreur Sync Assujetti: ${response.body}");
      }
    } catch (e) {
      print("💥 Erreur: $e");
    }
  }

  // 2. ENVOYER LES TAXES
  Future<void> syncTaxes() async {
    final db = DBService.instance;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    try {
      // 1. Récupère Taxes + Actes
      List<Map<String, dynamic>> payload = await db.getUnsyncedTaxesWithActs();

      if (payload.isEmpty) {
        print("⚠️ [SYNC] Aucune taxe à synchroniser.");
        return;
      }

      print("📦 [SYNC] Envoi de ${payload.length} taxes vers le serveur...");

      final response = await http.post(
        Uri.parse('$baseUrl/sync/taxes'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json' // Important pour voir les erreurs Laravel
        },
        body: jsonEncode({'data': payload}),
      );

      print("🔵 [SYNC] Réponse Serveur : ${response.statusCode}");

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        List<dynamic> ids = resData['synced_ids'];
        await db.markTaxesAsSynced(ids.cast<int>());
        print("✅ [SYNC] Succès ! Taxes synchronisées.");
      } else {
        print("❌ [SYNC] Erreur : ${response.body}");
      }
    } catch (e) {
      print("💥 [SYNC] Exception : $e");
    }
  }
}