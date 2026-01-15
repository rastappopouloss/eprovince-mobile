import 'dart:typed_data';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';

class PrinterService {
  static final PrinterService _instance = PrinterService._internal();
  factory PrinterService() => _instance;
  PrinterService._internal();

  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  // --- FONCTION MAGIQUE DE NETTOYAGE ---
  // Enlève les accents et met en majuscule pour éviter les "Ã©"
  String _cleanText(String input) {
    if (input.isEmpty) return "";
    String output = input.toUpperCase();

    // Remplacement manuel des accents courants
    output = output.replaceAll('É', 'E');
    output = output.replaceAll('È', 'E');
    output = output.replaceAll('Ê', 'E');
    output = output.replaceAll('Ë', 'E');
    output = output.replaceAll('À', 'A');
    output = output.replaceAll('Â', 'A');
    output = output.replaceAll('Î', 'I');
    output = output.replaceAll('Ï', 'I');
    output = output.replaceAll('Ô', 'O');
    output = output.replaceAll('Û', 'U');
    output = output.replaceAll('Ù', 'U');
    output = output.replaceAll('Ç', 'C');

    return output;
  }
  // -------------------------------------

  Future<List<BluetoothDevice>> getBondedDevices() async {
    return await bluetooth.getBondedDevices();
  }

  Future<bool> connect(BluetoothDevice device) async {
    if ((await bluetooth.isConnected) == true) return true;
    try {
      return await bluetooth.connect(device) ?? false;
    } catch (e) {
      return false;
    }
  }

  // --- TICKET PÉAGE (CORRIGÉ & SANS ACCENTS) ---
  Future<void> printTicket(
      Map<String, dynamic> data,
      String agentName,
      String posteName,
      String provNom,
      String provCode,
      String provEntete
      ) async {

    if ((await bluetooth.isConnected) != true) throw Exception("Non connecté");

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    // EN-TÊTE
    bytes += generator.text('REPUBLIQUE DEMOCRATIQUE DU CONGO',
        styles: const PosStyles(align: PosAlign.center, bold: true, fontType: PosFontType.fontB));

    bytes += generator.text(_cleanText(provNom),
        styles: const PosStyles(align: PosAlign.center, bold: true, fontType: PosFontType.fontB));

    if (provEntete.isNotEmpty) {
      bytes += generator.text(_cleanText('$provCode - $provEntete'),
          styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));
    }

    bytes += generator.text('TAXE SUR LE PEAGE',
        styles: const PosStyles(align: PosAlign.center, bold: true, reverse: true));

    bytes += generator.hr();

    // DÉTAILS
    // CORRECTION ALIGNEMENT : On force Font B pour que "Beach ALUNGULU" rentre
    bytes += generator.row([
      PosColumn(
          text: _cleanText(posteName), // Nettoyage accents
          width: 7, // On donne plus de place au nom (7/12)
          styles: const PosStyles(bold: true, fontType: PosFontType.fontB)
      ),
      PosColumn(
          text: DateFormat('dd/MM HH:mm').format(DateTime.parse(data['datecreate'])),
          width: 5, // La date prend moins de place (5/12)
          styles: const PosStyles(align: PosAlign.right, fontType: PosFontType.fontB)
      ),
    ]);

    // CORRECTION ACCENTS CATEGORIE (ex: PEAGE ROUTE MOTO)
    bytes += generator.text('CATEGORIE:', styles: const PosStyles(align: PosAlign.left, underline: true, fontType: PosFontType.fontB));
    bytes += generator.text(_cleanText(data['categorie']),
        styles: const PosStyles(align: PosAlign.left, bold: true));

    // PLAQUE
    bytes += generator.row([
      PosColumn(text: 'PLAQUE:', width: 4, styles: const PosStyles(height: PosTextSize.size2, bold: true, fontType: PosFontType.fontB)),
      PosColumn(text: _cleanText(data['immatriculation'] ?? "---"), width: 8, styles: const PosStyles(align: PosAlign.right, height: PosTextSize.size2, width: PosTextSize.size2, bold: true)),
    ]);

    // Sachet
    if (data['num_sachet'] != null && data['num_sachet'].toString().isNotEmpty) {
      bytes += generator.text('Sachet: ${_cleanText(data['num_sachet'])}', styles: const PosStyles(align: PosAlign.left, fontType: PosFontType.fontB));
    }

    bytes += generator.hr();

    // MONTANT
    bytes += generator.text(
        'TOTAL: ${data['montant']} ${_cleanText(data['devise'])}',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)
    );

    // QR & FOOTER
    bytes += generator.text('Ag: ${_cleanText(agentName)}', styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));

    String qrData = "C:${_cleanText(data['categorie'])}|P:${_cleanText(data['immatriculation'])}|M:${data['montant']}|D:${_cleanText(data['devise'])}";
    bytes += generator.qrcode(qrData, size: QRSize.size4, align: PosAlign.center);

    bytes += generator.text(
      "Document securise",
      styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB),
    );

    bytes += generator.feed(2);
    bytes += generator.cut();

    await bluetooth.writeBytes(Uint8List.fromList(bytes));
  }

  // --- TICKET EMBARQUEMENT (CORRIGÉ & SANS ACCENTS) ---
  Future<void> printEmbarquementTicket(
      Map<String, dynamic> data,
      String agentName,
      String aeroportName,
      String provNom,
      String provCode,
      String provEntete
      ) async {

    if ((await bluetooth.isConnected) != true) throw Exception("Non connecté");

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    bytes += generator.text('REPUBLIQUE DEMOCRATIQUE DU CONGO',
        styles: const PosStyles(align: PosAlign.center, bold: true, fontType: PosFontType.fontB));

    bytes += generator.text(_cleanText(provNom),
        styles: const PosStyles(align: PosAlign.center, bold: true, fontType: PosFontType.fontB));

    bytes += generator.text("TAXE D'EMBARQUEMENT",
        styles: const PosStyles(align: PosAlign.center, bold: true, reverse: true));

    bytes += generator.hr();

    // CORRECTION : AEROPORT
    // On met tout en FontB pour éviter que "AEROPORT" soit coupé
    bytes += generator.text(_cleanText(aeroportName),
        styles: const PosStyles(align: PosAlign.center, bold: true, fontType: PosFontType.fontB));

    bytes += generator.text(DateFormat('dd/MM HH:mm').format(DateTime.parse(data['datecreate'])),
        styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));

    bytes += generator.hr();

    bytes += generator.text('PASSAGER:', styles: const PosStyles(align: PosAlign.left, underline: true, fontType: PosFontType.fontB));
    bytes += generator.text(_cleanText(data['passager']),
        styles: const PosStyles(align: PosAlign.left, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));

    bytes += generator.feed(1);

    bytes += generator.row([
      PosColumn(text: 'VOL: ${_cleanText(data['vol'])}', width: 6, styles: const PosStyles(bold: true, fontType: PosFontType.fontB)),
      PosColumn(text: 'VERS: ${_cleanText(data['destination'])}', width: 6, styles: const PosStyles(align: PosAlign.right, bold: true, fontType: PosFontType.fontB)),
    ]);

    bytes += generator.hr();

    bytes += generator.text(
        'TOTAL: ${data['montant']} ${_cleanText(data['devise'])}',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)
    );

    bytes += generator.text('Ag: ${_cleanText(agentName)}', styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));

    String qrData = "P:${_cleanText(data['passager'])}|V:${_cleanText(data['vol'])}|M:${data['montant']}|D:${_cleanText(data['devise'])}";
    bytes += generator.qrcode(qrData, size: QRSize.size4, align: PosAlign.center);

    bytes += generator.text('Bon voyage - Safari njema',
        styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));

    bytes += generator.feed(2);
    bytes += generator.cut();

    await bluetooth.writeBytes(Uint8List.fromList(bytes));
  }
}