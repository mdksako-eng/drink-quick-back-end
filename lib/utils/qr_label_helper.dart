// utils/qr_label_helper.dart
// Generates and prints a QR label for a drink (for shelf/bin/carton labelling).
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/drink_model.dart';
import '../utils/i18n.dart';

/// The machine-readable data encoded in the QR (barcode → id → name).
String qrDataFor(Drink drink) {
  if (drink.barcode.isNotEmpty) return drink.barcode;
  if (drink.id.isNotEmpty) return drink.id;
  return drink.name;
}

/// Shows a QR label dialog for [drink] with a print action.
Future<void> showQrLabelDialog(BuildContext context, Drink drink) {
  final data = qrDataFor(drink);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('qrLabel')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: QrImageView(
              data: data,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(drink.name,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            drink.barcode.isNotEmpty
                ? '${t('barcode')}: ${drink.barcode}'
                : '${t('barcode')}: —',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          Text('${t('unitsPerPack')}: ${drink.unitsPerPack}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
        ElevatedButton.icon(
          onPressed: () => _printLabel(ctx, drink),
          icon: const Icon(Icons.print, size: 18),
          label: Text(t('inv_print')),
        ),
      ],
    ),
  );
}

Future<void> _printLabel(BuildContext context, Drink drink) async {
  final png = await _qrToPng(qrDataFor(drink));
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(60 * PdfPageFormat.mm, 50 * PdfPageFormat.mm),
      margin: const pw.EdgeInsets.all(10),
      build: (_) => pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Image(pw.MemoryImage(png), width: 120, height: 120),
            pw.SizedBox(height: 6),
            pw.Text(drink.name,
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.Text('${t('unitsPerPack')}: ${drink.unitsPerPack}',
                style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ),
    ),
  );
  final bytes = await doc.save();
  if (context.mounted) {
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}

Future<ui.Image> _qrImage(String data) async {
  final painter = QrPainter(
    data: data,
    version: QrVersions.auto,
    gapless: false,
  );
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  const double size = 400;
  painter.paint(canvas, const ui.Size(size, size));
  return recorder.endRecording().toImage(size.toInt(), size.toInt());
}

Future<Uint8List> _qrToPng(String data) async {
  final image = await _qrImage(data);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
