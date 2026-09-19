// utils/export_helper.dart
// Inventory report export: a dialog lets the user pick the sections (checkboxes)
// and the format, then the professional builder in inventory_report_files.dart
// produces a PDF (company name + charts), an Excel workbook or a CSV, which is
// saved and shared.
//
// PDF/Excel/CSV all carry the company name and the reporting period, and every
// label is localized (EN/FR) through the app's `t`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/drink_model.dart';
import '../models/inventory_model.dart';
import '../widgets/export_options_dialog.dart';
import 'company_name_helper.dart';
import 'i18n.dart';
import 'inventory_report_files.dart';

class ExportHelper {
  /// Exports [report] in the format and with the sections the user chooses.
  ///
  /// [drinks] supplies the batch dates for the expiry section (optional).
  static Future<void> exportInventoryReport(
    InventoryReport report,
    BuildContext context, {
    List<Drink> drinks = const [],
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final selection = await showExportOptionsDialog(
      context,
      sections: const [
        ExportSectionOption(labelKey: 'exp_summary', value: true),
        ExportSectionOption(labelKey: 'inv_unitsPerCategory', value: true),
        ExportSectionOption(labelKey: 'exp_currentStockHeader', value: true),
        ExportSectionOption(labelKey: 'exp_lowStockItems', value: true),
        ExportSectionOption(labelKey: 'expiryAlertTitle', value: true),
        ExportSectionOption(labelKey: 'exp_transactionsHeader', value: true),
      ],
      title: t('exp_inventoryReport'),
    );
    if (selection == null) return;

    final options = optionsFromSelection(selection.selection);
    if (options.isEmpty) {
      _toast(messenger, t('exportSelectOne'), isError: true);
      return;
    }

    try {
      final companyName = await CompanyNameHelper.resolve();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final dir = await _outputDirectory();

      switch (selection.format) {
        case 'pdf':
          final bytes = await InventoryReportFiles.buildPdf(
            report: report,
            t: t,
            companyName: companyName,
            drinks: drinks,
            options: options,
          );
          await _saveAndShare(
            dir,
            'Inventory_Report_$stamp.pdf',
            bytes,
            messenger,
          );
          break;
        case 'excel':
          final bytes = InventoryReportFiles.buildExcel(
            report: report,
            t: t,
            companyName: companyName,
            drinks: drinks,
            options: options,
          );
          if (bytes == null) throw Exception('Excel export failed');
          await _saveAndShare(
            dir,
            'Inventory_Report_$stamp.xlsx',
            bytes,
            messenger,
          );
          break;
        default:
          final csv = InventoryReportFiles.buildCsv(
            report: report,
            t: t,
            companyName: companyName,
            drinks: drinks,
            options: options,
          );
          await _saveAndShare(
            dir,
            'Inventory_Report_$stamp.csv',
            csv.codeUnits,
            messenger,
            text: csv,
          );
          break;
      }
    } catch (e) {
      _toast(messenger, '${t('refreshFailed')}: $e', isError: true);
    }
  }

  /// Maps the checkbox state (in dialog order) to the export options.
  static InventoryExportOptions optionsFromSelection(List<bool> selected) {
    bool at(int i) => i < selected.length && selected[i];
    return InventoryExportOptions(
      summary: at(0),
      charts: at(1),
      currentStock: at(2),
      lowStock: at(3),
      expiry: at(4),
      transactions: at(5),
    );
  }
/// Writes the file and opens the platform share sheet.
  static Future<void> _saveAndShare(
    Directory dir,
    String fileName,
    List<int> bytes,
    ScaffoldMessengerState messenger, {
    String? text,
  }) async {
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    _toast(
      messenger,
      '${t('exp_inventoryReport')} — ${t('exportSaved')}: $fileName',
    );

    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      subject: t('exp_inventoryReport'),
      text: text ?? t('exp_inventoryReport'),
    ));
  }

  /// Android: the public Download folder (easy to find). Anywhere else (and on
  /// web, where dart:io is unavailable): the app documents directory.
  static Future<Directory> _outputDirectory() async {
    try {
      if (Platform.isAndroid) {
        final downloads = Directory(
            '/storage/emulated/0/Download/Drink_Quick/Inventory_Reports');
        if (!await downloads.exists()) {
          await downloads.create(recursive: true);
        }
        return downloads;
      }
    } catch (_) {
      // Platform not supported (web/desktop) - fall through to app documents.
    }

    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/Inventory_Reports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static void _toast(ScaffoldMessengerState messenger, String message,
      {bool isError = false}) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ));
  }
}