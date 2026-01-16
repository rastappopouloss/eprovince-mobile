import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBService {
  static final DBService instance = DBService._init();
  static Database? _database;

  DBService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    // J'ai gardé le même nom, donc désinstallation obligatoire
    _database = await _initDB('eprovince.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
        path,
        version: 1,
        onCreate: _createDB
    );
  }

  Future _createDB(Database db, int version) async {
    // 1. Table PÉAGES
    await db.execute('''
    CREATE TABLE peages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      province_id INTEGER,
      ville_id INTEGER,
      poste_id INTEGER,
      user_id INTEGER, 
      categorie TEXT,
      immatriculation TEXT,
      num_sachet TEXT,  
      montant REAL,
      devise TEXT,
      datecreate TEXT,
      is_synced INTEGER DEFAULT 0
    )
    ''');

    // 2. Table EMBARQUEMENTS
    await db.execute('''
    CREATE TABLE embarquements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      province_id INTEGER,
      ville_id INTEGER,
      site_id INTEGER, 
      user_id INTEGER,
      passager TEXT,
      vol TEXT,
      destination TEXT,
      montant REAL,
      devise TEXT,
      datecreate TEXT,
      is_synced INTEGER DEFAULT 0
    )
    ''');

    // AJOUT GÉOGRAPHIE
    await db.execute('CREATE TABLE territoires (id INTEGER PRIMARY KEY, nom TEXT, ville_id INTEGER)');
    await db.execute('CREATE TABLE quartiers (id INTEGER PRIMARY KEY, nom TEXT, territoire_id INTEGER)');

    // MODIFICATION TABLE ASSUJETTIS (Ajout des colonnes ID géo)
    await db.execute('''
      CREATE TABLE assujettis (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT,
        postnom TEXT,
        prenom TEXT,
        telephone TEXT,
        email TEXT,
        adresse TEXT,
        province_id INTEGER,
        territoire_id INTEGER, 
        quartier_id INTEGER,   
        user_id INTEGER,
        type INTEGER DEFAULT 1,         
        categorie TEXT DEFAULT 'SPONTANE', 
        nationalite TEXT,               
        
        ville_id INTEGER,
        datecreate TEXT,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    // 1. TABLES DE RÉFÉRENCE (Pour les listes déroulantes)
    await db.execute('CREATE TABLE fiscals (id INTEGER PRIMARY KEY, nom TEXT)');
    await db.execute('CREATE TABLE articles (id INTEGER PRIMARY KEY, activite TEXT, province_id INTEGER)');
    await db.execute('CREATE TABLE natures (id INTEGER PRIMARY KEY, article_id INTEGER, nom TEXT, type TEXT, taux REAL, periodicite TEXT)');

    // 2. TABLES TRANSACTIONNELLES (Ce que l'agent crée)
    await db.execute('''
      CREATE TABLE taxes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        assujetti_id INTEGER,
        fiscal_id INTEGER,
        user_id INTEGER,
        type TEXT,
        devise TEXT,
        taux_change REAL,
        datecreate TEXT,
        datefin TEXT,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE actes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        taxe_local_id INTEGER, -- Lien vers la table taxes locale
        article_id INTEGER,
        nature_id INTEGER,
        taux REAL,
        nombre INTEGER,
        total REAL,
        total_fc REAL,
        total_usd REAL
      )
    ''');

    print("✅ Base de données locale créée avec succès (Version harmonisée)");
  }

  // --- Helpers pour charger les listes ---
  Future<List<Map<String, dynamic>>> getFiscals() async => await (await database).query('fiscals');
  //Future<List<Map<String, dynamic>>> getArticles() async => await (await database).query('articles');
  // APRÈS : Avec filtre par province
  Future<List<Map<String, dynamic>>> getArticles(int provinceId) async {
    final db = await database;
    return await db.query(
        'articles',
        where: 'province_id = ?', // On filtre ici
        whereArgs: [provinceId],
        orderBy: 'activite ASC' // Bonus : on trie par ordre alphabétique pour faire joli
    );
  }
  Future<List<Map<String, dynamic>>> getNatures(int articleId) async =>
      await (await database).query('natures', where: 'article_id = ?', whereArgs: [articleId]);

  // --- Helpers pour Sauvegarder une Taxe (Version Corrigée) ---

 /* Future<int> insertFullTax(Map<String, dynamic> taxData, List<Map<String, dynamic>> actesList) async {
    final db = await database;
    int taxId = 0;

    // Récupération du taux de change et de la devise
    double tauxChange = (taxData['taux_change'] ?? 1.0).toDouble();
    String devise = taxData['devise'] ?? 'FC';

    await db.transaction((txn) async {
      // 1. Insérer la Taxe (Inchangé)
      taxId = await txn.insert('taxes', {
        'assujetti_id': taxData['assujetti_id'],
        'fiscal_id':    taxData['fiscal_id'],
        'user_id':      taxData['user_id'],
        'devise':       devise,
        'type':         taxData['type'],
        'datecreate':   taxData['datecreate'],
        'datefin':      taxData['datefin'],
        'is_synced':    0,
        'taux_change':  tauxChange,
      });

      // 2. Insérer les Actes avec calcul double devise
      for (var acte in actesList) {
        double totalLigne = (acte['total'] as num).toDouble();
        double totalFC = 0.0;
        double totalUSD = 0.0;

        // LOGIQUE DE CONVERSION
        if (devise == 'USD') {
          totalUSD = totalLigne;
          totalFC = totalLigne * tauxChange; // Ex: 10$ * 2800 = 28000 FC
        } else {
          totalFC = totalLigne;
          totalUSD = (tauxChange > 0) ? (totalLigne / tauxChange) : 0.0; // Ex: 28000 / 2800 = 10$
        }

        await txn.insert('actes', {
          'taxe_local_id': taxId,
          'article_id':    acte['article_id'],
          'nature_id':     acte['nature_id'],
          'taux':          acte['taux'],
          'nombre':        acte['nombre'],
          'total':         totalLigne, // Montant payé (tel quel)
          'total_fc':      totalFC,    // <--- Calculé
          'total_usd':     totalUSD    // <--- Calculé
        });
      }
    });
    return taxId;
  }
*/

  Future<int> insertFullTax(Map<String, dynamic> taxData, List<Map<String, dynamic>> actesList) async {
    final db = await database;
    int taxId = 0;

    // Récupération du taux de change et de la devise
    double tauxChange = (taxData['taux_change'] ?? 1.0).toDouble();
    String devise = taxData['devise'] ?? 'FC';

    await db.transaction((txn) async {
      // 1. Insérer la Taxe (Inchangé)
      taxId = await txn.insert('taxes', {
        'assujetti_id': taxData['assujetti_id'],
        'fiscal_id':    taxData['fiscal_id'],
        'user_id':      taxData['user_id'],
        'devise':       devise,
        'type':         taxData['type'],
        'datecreate':   taxData['datecreate'],
        'datefin':      taxData['datefin'],
        'is_synced':    0,
        'taux_change':  tauxChange,
      });

      // 2. Insérer les Actes avec LA LOGIQUE LARAVEL
      for (var acte in actesList) {
        // On récupère les valeurs brutes
        double taux = (acte['taux'] as num).toDouble();
        int nombre = (acte['nombre'] as num).toInt();
        String type = acte['nature_type'] ?? 'FORFAIT';

        double totalFC = 0.0;
        double totalUSD = 0.0;

        // --- APPLICATION STRICTE DE VOTRE LOGIQUE LARAVEL ---
        if (type == 'POURCENTAGE') {
          // Laravel: $acte->totalusd = ($request->nombre[$i] * $request->taux[$i])/100;
          totalUSD = (nombre * taux) / 100;

          // Laravel: $acte->totalfc = (($request->nombre[$i] * $request->taux[$i]) / 100) * $change->province->taux;
          totalFC = totalUSD * tauxChange;
        } else {
          // Laravel: $acte->totalusd = $request->nombre[$i] * $request->taux[$i];
          totalUSD = nombre * taux;

          // Laravel: $acte->totalfc = ($request->nombre[$i] * $request->taux[$i]) * $change->province->taux;
          totalFC = totalUSD * tauxChange;
        }
        // ----------------------------------------------------

        // La colonne 'total' stocke ce que le client a payé dans la devise choisie
        double totalPaye = (devise == 'USD') ? totalUSD : totalFC;

        await txn.insert('actes', {
          'taxe_local_id': taxId,
          'article_id':    acte['article_id'],
          'nature_id':     acte['nature_id'],
          'taux':          taux,
          'nombre':        nombre,
          'total':         totalPaye,  // Ce qu'on affiche sur le ticket
          'total_fc':      totalFC,    // Calculé proprement comme Laravel
          'total_usd':     totalUSD    // Calculé proprement comme Laravel
        });
      }
    });
    return taxId;
  }
  // --- Helper pour récupérer Taxes non sync ---
  Future<List<Map<String, dynamic>>> getUnsyncedTaxesWithActs() async {
    final db = await database;
    // Récupérer les en-têtes
    final taxes = await db.query('taxes', where: 'is_synced = ?', whereArgs: [0]);

    List<Map<String, dynamic>> result = [];

    for (var t in taxes) {
      Map<String, dynamic> taxMap = Map.from(t);
      // Récupérer les actes pour cette taxe
      final actes = await db.query('actes', where: 'taxe_local_id = ?', whereArgs: [t['id']]);
      taxMap['actes'] = actes;
      taxMap['local_id'] = t['id']; // Important pour le retour
      result.add(taxMap);
    }
    return result;
  }

  Future<void> markTaxesAsSynced(List<int> ids) async {
    final db = await database;
    await db.rawUpdate('UPDATE taxes SET is_synced = 1 WHERE id IN (${ids.join(',')})');
  }

  // Récupérer les lignes (actes) d'une taxe spécifique
  Future<List<Map<String, dynamic>>> getTaxLines(int taxId) async {
    final db = await database;
    // On joint avec la table 'natures' si tu veux afficher le nom de la nature
    // Sinon, assure-toi que ta table 'lignes_taxes' ou 'actes' a les infos nécessaires
    // Ici je suppose une jointure simple ou une récupération brute

    // Option A: Si tu as sauvegardé 'nature_nom' dans la table actes
    // return await db.query('actes', where: 'taxe_local_id = ?', whereArgs: [taxId]);

    // Option B (Plus robuste): Jointure avec la table de référence (si disponible)
    // Adapte selon tes noms de tables exacts
    return await db.rawQuery('''
      SELECT a.*, n.nom as nature_nom, s.activite as article_nom 
      FROM actes a
      LEFT JOIN natures n ON a.nature_id = n.id
      LEFT JOIN articles s ON a.article_id = s.id
      WHERE a.taxe_local_id = ?
    ''', [taxId]);
  }

  // --- STATISTIQUES POUR DASHBOARD ---
  // --- STATISTIQUES POUR DASHBOARD (MULTI-DEVISES) ---
  Future<Map<String, dynamic>> getAgentStats(int agentId, String type) async {
    final db = await database;

    String table = "";
    String dateCol = "datecreate";
    String amountCol = "montant"; // Pour Péage/Embarquement

    if (type == 'PEAGE') table = 'peages';
    else if (type == 'EMBARQUEMENT') table = 'embarquements';
    else if (type == 'TAXE') table = 'taxes';

    DateTime now = DateTime.now();
    String todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    double totalFC = 0.0;
    double totalUSD = 0.0;
    int todayCount = 0;
    List<Map<String, dynamic>> weeklyData = [];

    // --- A. CALCUL DU JOUR (AUJOURD'HUI) ---
    if (type == 'TAXE') {
      // 1. On compte les tickets (Taxes)
      final resCount = await db.rawQuery(
          "SELECT COUNT(*) as cnt FROM taxes WHERE user_id = ? AND datecreate LIKE '$todayStr%'",
          [agentId]
      );
      todayCount = (resCount.first['cnt'] as num?)?.toInt() ?? 0;

      // 2. On somme les montants (FC) via la table de liaison 'lignes_taxes'
      // ATTENTION : Vérifiez que votre table s'appelle bien 'lignes_taxes' ou 'actes'
      // Et que la devise est stockée dans l'en-tête 'taxes'
      final resFC = await db.rawQuery('''
        SELECT SUM(l.total) as total
        FROM taxes t
        JOIN actes l ON l.taxe_local_id = t.id 
        WHERE t.user_id = ? AND t.devise = 'FC' AND substr(t.datecreate, 1, 10) = ?
      ''', [agentId, todayStr]);
      totalFC = (resFC.first['total'] as num?)?.toDouble() ?? 0.0;

      // 3. On somme les montants (USD)
      final resUSD = await db.rawQuery('''
        SELECT SUM(l.total) as total
        FROM taxes t
        JOIN actes l ON l.taxe_local_id = t.id 
        WHERE t.user_id = ? AND t.devise = 'USD' AND substr(t.datecreate, 1, 10) = ?
      ''', [agentId, todayStr]);
      totalUSD = (resUSD.first['total'] as num?)?.toDouble() ?? 0.0;

    } else {
      // PEAGE & EMBARQUEMENT (Plus simple)

      // Compte total
      final resCount = await db.rawQuery(
          'SELECT COUNT(*) as cnt FROM $table WHERE user_id = ? AND substr($dateCol, 1, 10) = ?',
          [agentId, todayStr]
      );
      todayCount = (resCount.first['cnt'] as num?)?.toInt() ?? 0;

      // Somme FC
      final resFC = await db.rawQuery(
          "SELECT SUM($amountCol) as total FROM $table WHERE user_id = ? AND devise = 'FC' AND substr($dateCol, 1, 10) = ?",
          [agentId, todayStr]
      );
      totalFC = (resFC.first['total'] as num?)?.toDouble() ?? 0.0;

      // Somme USD
      final resUSD = await db.rawQuery(
          "SELECT SUM($amountCol) as total FROM $table WHERE user_id = ? AND devise = 'USD' AND substr($dateCol, 1, 10) = ?",
          [agentId, todayStr]
      );
      totalUSD = (resUSD.first['total'] as num?)?.toDouble() ?? 0.0;
    }

    // --- B. CALCUL SEMAINE (Graphique - On combine tout en équivalent FC pour simplifier le graph) ---
    // (Ou on affiche juste le volume des ventes pour faire simple)
    for (int i = 6; i >= 0; i--) {
      DateTime d = now.subtract(Duration(days: i));
      String dayStr = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      String dayLabel = "${d.day}/${d.month}";

      // Pour le graphique, on compte juste le NOMBRE de tickets pour éviter la confusion des devises
      final resDay = await db.rawQuery(
          'SELECT COUNT(*) as cnt FROM $table WHERE user_id = ? AND substr($dateCol, 1, 10) = ?',
          [agentId, dayStr]
      );

      weeklyData.add({
        'day': dayLabel,
        'amount': (resDay.first['cnt'] as num?)?.toDouble() ?? 0.0 // On affiche le nombre de ventes sur le graph
      });
    }

    return {
      'today_count': todayCount,
      'total_fc': totalFC,   // <--- Nouveau
      'total_usd': totalUSD, // <--- Nouveau
      'weekly_data': weeklyData
    };
  }
  // --- STATISTIQUES POUR DASHBOARD (CORRIGÉ & ROBUSTE) ---
  /*Future<Map<String, dynamic>> getAgentStats(int agentId, String type) async {
    final db = await database;

    String table = "";
    String dateCol = "datecreate"; // La colonne contenant la date

    if (type == 'PEAGE') table = 'peages';
    else if (type == 'EMBARQUEMENT') table = 'embarquements';
    else if (type == 'TAXE') table = 'taxes';

    DateTime now = DateTime.now();
    // Format YYYY-MM-DD pour la recherche SQL
    String todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    double totalFC = 0.0;
    double totalUSD = 0.0;
    int todayCount = 0;
    List<Map<String, dynamic>> weeklyData = [];

    // --- A. CALCUL DU JOUR (AUJOURD'HUI) ---
    if (type == 'TAXE') {
      // 1. On compte les tickets (Taxes)
      // Utilisation de LIKE '$todayStr%' pour être plus robuste sur le format de date
      final resCount = await db.rawQuery(
          "SELECT COUNT(*) as cnt FROM taxes WHERE user_id = ? AND datecreate LIKE '$todayStr%'",
          [agentId]
      );
      todayCount = (resCount.first['cnt'] as num?)?.toInt() ?? 0;

      // 2. On somme la colonne 'total_fc' de la table ACTES (Peu importe la devise de paiement)
      // Cela garantit que même si payé en USD, on a la valeur en FC
      final resFC = await db.rawQuery('''
        SELECT SUM(l.total_fc) as total
        FROM taxes t
        JOIN actes l ON l.taxe_local_id = t.id 
        WHERE t.user_id = ? AND t.datecreate LIKE '$todayStr%'
      ''', [agentId]);
      totalFC = (resFC.first['total'] as num?)?.toDouble() ?? 0.0;

      // 3. On somme la colonne 'total_usd' de la table ACTES
      final resUSD = await db.rawQuery('''
        SELECT SUM(l.total_usd) as total
        FROM taxes t
        JOIN actes l ON l.taxe_local_id = t.id 
        WHERE t.user_id = ? AND t.datecreate LIKE '$todayStr%'
      ''', [agentId]);
      totalUSD = (resUSD.first['total'] as num?)?.toDouble() ?? 0.0;

    } else {
      // PEAGE & EMBARQUEMENT
      // Ici on garde l'ancienne logique car ces tables n'ont pas forcément total_fc/total_usd (à vérifier)
      // Si elles ne les ont pas, on se base sur la devise.

      final resCount = await db.rawQuery(
          "SELECT COUNT(*) as cnt FROM $table WHERE user_id = ? AND $dateCol LIKE '$todayStr%'",
          [agentId]
      );
      todayCount = (resCount.first['cnt'] as num?)?.toInt() ?? 0;

      // Somme FC (Basé sur la devise déclarée)
      final resFC = await db.rawQuery(
          "SELECT SUM(montant) as total FROM $table WHERE user_id = ? AND devise = 'FC' AND $dateCol LIKE '$todayStr%'",
          [agentId]
      );
      totalFC = (resFC.first['total'] as num?)?.toDouble() ?? 0.0;

      // Somme USD
      final resUSD = await db.rawQuery(
          "SELECT SUM(montant) as total FROM $table WHERE user_id = ? AND devise = 'USD' AND $dateCol LIKE '$todayStr%'",
          [agentId]
      );
      totalUSD = (resUSD.first['total'] as num?)?.toDouble() ?? 0.0;
    }

    // --- B. CALCUL SEMAINE (Graphique) ---
    for (int i = 6; i >= 0; i--) {
      DateTime d = now.subtract(Duration(days: i));
      String dayStr = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      String dayLabel = "${d.day}/${d.month}";

      final resDay = await db.rawQuery(
          "SELECT COUNT(*) as cnt FROM $table WHERE user_id = ? AND $dateCol LIKE '$dayStr%'",
          [agentId]
      );

      weeklyData.add({
        'day': dayLabel,
        'amount': (resDay.first['cnt'] as num?)?.toDouble() ?? 0.0
      });
    }

    return {
      'today_count': todayCount,
      'total_fc': totalFC,
      'total_usd': totalUSD,
      'weekly_data': weeklyData
    };
  }*/
  // --- MÉTHODES PÉAGE ---

  Future<int> insertPeage(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert('peages', row);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedPeages() async {
    final db = await database;
    return await db.query('peages', where: 'is_synced = ?', whereArgs: [0]);
  }

  Future<void> markAsSynced(List<int> ids) async {
    final db = await database;
    await db.rawUpdate('UPDATE peages SET is_synced = 1 WHERE id IN (${ids.join(',')})');
  }

  // Récupérer l'historique des Péages pour un agent
  Future<List<Map<String, dynamic>>> getPeageHistory(int userId) async {
    final db = await database;
    // Maintenant que la colonne user_id existe, cette requête va fonctionner
    return await db.query(
        'peages',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'id DESC',
        limit: 50
    );
  }

  // --- MÉTHODES EMBARQUEMENT ---

  Future<int> insertEmbarquement(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert('embarquements', row);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedEmbarquements() async {
    final db = await database;
    return await db.query('embarquements', where: 'is_synced = ?', whereArgs: [0]);
  }

  Future<void> markEmbarquementsAsSynced(List<int> ids) async {
    final db = await database;
    await db.rawUpdate('UPDATE embarquements SET is_synced = 1 WHERE id IN (${ids.join(',')})');
  }

  // Récupérer l'historique des Embarquements pour un agent
  Future<List<Map<String, dynamic>>> getEmbarquementHistory(int userId) async {
    final db = await database;
    // Maintenant que la colonne user_id existe, cette requête va fonctionner
    return await db.query(
        'embarquements',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'id DESC',
        limit: 50
    );
  }

  // --- MÉTHODES POUR ASSUJETTIS ---

  // Créer un assujetti
  Future<int> insertAssujetti(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert('assujettis', row);
  }

  // Récupérer la liste pour le Dropdown
  // Récupérer la liste COMPLÈTE pour le Dropdown et l'impression
  Future<List<Map<String, dynamic>>> getAllAssujettis(int userId) async {
    final db = await database;

    // CORRECTION : On fait des LEFT JOIN pour récupérer les noms
    return await db.rawQuery('''
      SELECT a.*, 
             t.nom as territoire_nom, 
             q.nom as quartier_nom
      FROM assujettis a
      LEFT JOIN territoires t ON a.territoire_id = t.id
      LEFT JOIN quartiers q ON a.quartier_id = q.id
      WHERE a.user_id = ?
      ORDER BY a.id DESC
    ''', [userId]);
  }

  // Récupérer tous les territoires
  Future<List<Map<String, dynamic>>> getTerritoires() async {
    return await (await database).query('territoires');
  }

  // Récupérer les quartiers d'un territoire spécifique
  Future<List<Map<String, dynamic>>> getQuartiers(int territoireId) async {
    return await (await database).query('quartiers', where: 'territoire_id = ?', whereArgs: [territoireId]);
  }

  // Pour la synchro des assujettis
  Future<List<Map<String, dynamic>>> getUnsyncedAssujettis() async {
    return await (await database).query('assujettis', where: 'is_synced = ?', whereArgs: [0]);
  }

  Future<void> markAssujettisAsSynced(List<int> ids) async {
    final db = await database;
    await db.rawUpdate('UPDATE assujettis SET is_synced = 1 WHERE id IN (${ids.join(',')})');
  }

  // Récupérer l'historique (Jointure Taxes + Assujettis)
  Future<List<Map<String, dynamic>>> getTaxHistory(int isSynced) async {
    final db = await database;
    // On sélectionne la Taxe et le Nom/Postnom de l'assujetti
    return await db.rawQuery('''
      SELECT t.id, t.datecreate, t.type, t.devise, 
             a.nom, a.postnom, a.telephone, a.adresse,
             terr.nom as territoire_nom, 
             quart.nom as quartier_nom
      FROM taxes t
      LEFT JOIN assujettis a ON t.assujetti_id = a.id
      LEFT JOIN territoires terr ON a.territoire_id = terr.id
      LEFT JOIN quartiers quart ON a.quartier_id = quart.id
      WHERE t.is_synced = ?
      ORDER BY t.id DESC
    ''', [isSynced]);
  }

  // Supprimer une taxe (en cas d'erreur avant synchro)
  Future<void> deleteTax(int id) async {
    final db = await database;
    // On supprime l'entête et les lignes liées (si ta DB gère les cascades c'est auto, sinon on force)
    await db.delete('taxes', where: 'id = ?', whereArgs: [id]);
    // On suppose que ta table de lignes s'appelle 'lignes_taxes' ou similaire
    // await db.delete('lignes_taxes', where: 'taxe_id = ?', whereArgs: [id]);
  }
}