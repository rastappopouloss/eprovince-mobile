import 'dart:typed_data';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TaxePrinterService {
  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  // --- LOGIQUE SPÉCIALE Q2i (Connexion) ---
  Future<bool> _connectToQ2iPrinter() async {
    bool? isConnected = await bluetooth.isConnected;
    if (isConnected == true) return true;

    try {
      List<BluetoothDevice> bondedDevices = await bluetooth.getBondedDevices();
      BluetoothDevice? targetDevice;

      final prefs = await SharedPreferences.getInstance();
      final String? savedAddress = prefs.getString('printer_address');

      if (savedAddress != null) {
        try {
          targetDevice = bondedDevices.firstWhere((d) => d.address == savedAddress);
        } catch (e) { /* Pas trouvée */ }
      }

      if (targetDevice == null) {
        try {
          targetDevice = bondedDevices.firstWhere((d) {
            String name = (d.name ?? "").toLowerCase();
            return name.contains("innerprinter") ||
                name.contains("iposprinter") ||
                name.contains("printer") ||
                name.contains("bluetooth printer");
          });
          if (targetDevice != null && targetDevice.address != null) {
            await prefs.setString('printer_address', targetDevice.address!);
          }
        } catch (e) { /* Pas trouvée */ }
      }

      if (targetDevice != null) {
        await bluetooth.connect(targetDevice);
        return true;
      }

      if (bondedDevices.length == 1) {
        await bluetooth.connect(bondedDevices.first);
        return true;
      }

    } catch (e) {
      print("Erreur connexion Q2i: $e");
    }
    return false;
  }

  // --- FONCTION DE NETTOYAGE DES CARACTÈRES SPÉCIAUX ---
  String _cleanText(String input) {
    if (input.isEmpty) return "";

    // 1. Mettre en majuscules pour uniformiser
    String output = input.toUpperCase();

    // 2. Remplacer les accents manuellement (Le plus fiable sur les imprimantes chinoises)
    const withDia = 'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
    const withoutDia = 'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';

    for (int i = 0; i < withDia.length; i++) {
      output = output.replaceAll(withDia[i], withoutDia[i]);
    }

    // 3. Remplacer les symboles monétaires ou spéciaux qui bugguent souvent
    output = output.replaceAll('€', 'EUR');
    // Le symbole FC passe généralement bien en texte simple, sinon mettre 'FC'

    return output;
  }

  String _formatPrice(double price, String devise) {
    if (devise == 'USD') {
      return price.toStringAsFixed(5);
    }
    return price.toStringAsFixed(2);
  }

  Future<void> printTicket({
    required Map<String, dynamic> taxData,
    required Map<String, dynamic> assujetti,
    required Map<String, dynamic> agent,
    required List<Map<String, dynamic>> lignes,
    required String provEntete,
    required String provCode,
  }) async {

    // CONNEXION AUTO
    bool connected = await _connectToQ2iPrinter();

    if (!connected) {
      throw Exception("Imprimante interne non détectée.");
    }

    // Configuration 58mm
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    // --- MISE EN PAGE DU TICKET NETTOYÉE ---

    // 1. En-tête
    bytes += generator.text('REP. DEM. DU CONGO', styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text(_cleanText(provCode), styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));

    // ProvEntete est souvent "PROVINCE DU ...", on s'assure qu'il est clean
    bytes += generator.text(_cleanText(provEntete), styles: const PosStyles(align: PosAlign.center, bold: true));

    bytes += generator.hr(ch: '-');

    // 2. Titre
    bytes += generator.text('QUITTANCE N: ${taxData['id']}', styles: const PosStyles(align: PosAlign.center, height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generator.feed(1);

    // 3. QR Code
    bytes += generator.qrcode('ID:${taxData['id']}|MNT:${_calculateTotal(lignes)}', size: QRSize.size4);
    bytes += generator.feed(1);

    // 4. Info Client (Nettoyage des noms)
    String clientNom = _cleanText("${assujetti['nom']} ${assujetti['postnom']}");
    String zone = _cleanText("${assujetti['territoire_nom'] ?? '-'} / ${assujetti['quartier_nom'] ?? '-'}");

    bytes += generator.text('CLIENT: $clientNom', styles: const PosStyles(bold: true));
    bytes += generator.text('ZONE: $zone', styles: const PosStyles(fontType: PosFontType.fontB));
    bytes += generator.hr(ch: '.');

    // 5. Détails
    bytes += generator.text('DETAILS', styles: const PosStyles(bold: true, underline: true));
    double totalGeneral = 0;

    for (var ligne in lignes) {
      double totalLigne = (ligne['total'] as num).toDouble();
      totalGeneral += totalLigne;

      // On récupère la devise de la transaction
      String deviseTicket = taxData['devise'] ?? 'FC';

      // Nettoyage des libellés
      String article = _cleanText(ligne['article_nom'] ?? '');
      String nature = _cleanText(ligne['nature_nom'] ?? '');

      // Impression Secteur
      if (article.isNotEmpty) {
        bytes += generator.text('SEC: $article', styles: const PosStyles(bold: false, fontType: PosFontType.fontB));
      }

      // Impression Nature
      bytes += generator.text('- $nature', styles: const PosStyles(bold: true, fontType: PosFontType.fontB));

      // Impression Chiffres
      bytes += generator.row([
        PosColumn(
            text: '  ${ligne['nombre']} x ${ligne['taux']}',
            width: 7,
            styles: const PosStyles(fontType: PosFontType.fontB)
        ),
        PosColumn(
          // ICI : ON UTILISE LE FORMATAGE
            text: '${_formatPrice(totalLigne, deviseTicket)} $deviseTicket',
            width: 5,
            styles: const PosStyles(align: PosAlign.right, bold: true)
        ),
      ]);
    }

    bytes += generator.hr(ch: '=');

    // 6. Total
    String deviseTicket = taxData['devise'] ?? 'FC';

    bytes += generator.text(
        'TOTAL: ${_formatPrice(totalGeneral, deviseTicket)} $deviseTicket',
        styles: const PosStyles(align: PosAlign.center, height: PosTextSize.size2, width: PosTextSize.size2, bold: true)
    );

    bytes += generator.feed(1);

    // 7. Footer
    String agentNom = _cleanText(agent['nom'] ?? '');
    bytes += generator.text('TAXATEUR: $agentNom', styles: const PosStyles(fontType: PosFontType.fontB));
    bytes += generator.text('DATE: ${_formatDate(DateTime.now())}', styles: const PosStyles(fontType: PosFontType.fontB));

    bytes += generator.feed(1);
    bytes += generator.text('En foi de quoi, ce document est delivre', styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));
    bytes += generator.text('pour servir et valoir ce que de droit.', styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));

    bytes += generator.feed(2);
    bytes += generator.cut();

    try {
      await bluetooth.writeBytes(Uint8List.fromList(bytes));
    } catch (e) {
      throw Exception("Erreur impression Q2i : $e");
    }
  }

  double _calculateTotal(List lines) {
    return lines.fold(0.0, (sum, item) => sum + (item['total'] as num).toDouble());
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }
}