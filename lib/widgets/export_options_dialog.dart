// widgets/export_options_dialog.dart
// Reusable "what do you want in the report?" dialog: a checkbox per section plus
// the three formats. Used by the inventory report (and available to any other
// screen that exports a report).
import 'package:flutter/material.dart';

import '../utils/i18n.dart';

/// One selectable section of the report.
class ExportSectionOption {
  final String labelKey;
  final String? hintKey;
  final bool value;
  const ExportSectionOption({
    required this.labelKey,
    this.hintKey,
    required this.value,
  });
}

/// Shows the dialog and returns the chosen format ('pdf' | 'excel' | 'csv')
/// together with the updated selection, or null when the user cancelled.
Future<ExportDialogResult?> showExportOptionsDialog(
  BuildContext context, {
  required List<ExportSectionOption> sections,
  String? title,
}) {
  var current = List<bool>.from(sections.map((s) => s.value));

  return showDialog<ExportDialogResult>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final nothingSelected = current.every((v) => !v);
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.ios_share, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(child: Text(title ?? t('exportReport'))),
            ]),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t('exportChooseSections'),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(height: 6),
                    for (var i = 0; i < sections.length; i++)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(t(sections[i].labelKey)),
                        subtitle: sections[i].hintKey == null
                            ? null
                            : Text(t(sections[i].hintKey!),
                                style: const TextStyle(fontSize: 11)),
                        value: current[i],
                        onChanged: (v) => setDialogState(
                            () => current[i] = v ?? false),
                      ),
                    if (nothingSelected)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(t('exportSelectOne'),
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ),
            actionsPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            actions: [
              TextButton(
                onPressed: nothingSelected
                    ? null
                    : () => Navigator.pop(
                        ctx, ExportDialogResult('csv', current)),
                child: Text(t('exportCsv')),
              ),
              TextButton(
                onPressed: nothingSelected
                    ? null
                    : () => Navigator.pop(
                        ctx, ExportDialogResult('excel', current)),
                child: Text(t('exportExcel')),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: Text(t('exportPdf')),
                onPressed: nothingSelected
                    ? null
                    : () => Navigator.pop(
                        ctx, ExportDialogResult('pdf', current)),
              ),
            ],
          );
        },
      );
    },
  );
}

class ExportDialogResult {
  /// 'pdf' | 'excel' | 'csv'
  final String format;

  /// The checkbox state, in the order the sections were given.
  final List<bool> selection;

  const ExportDialogResult(this.format, this.selection);
}