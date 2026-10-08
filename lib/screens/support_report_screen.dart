// screens/support_report_screen.dart
// "Report a problem": bug reports and complaints from anyone signed in, including
// staff. The screen sends the user's words plus an automatic context block, so
// support receives something actionable.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drinks_calculator_fixed/providers/auth_provider.dart';
import 'package:drinks_calculator_fixed/services/support_service.dart';
import 'package:drinks_calculator_fixed/utils/helpers.dart';
import 'package:drinks_calculator_fixed/utils/i18n.dart';

class SupportReportScreen extends StatefulWidget {
  const SupportReportScreen({super.key});

  @override
  State<SupportReportScreen> createState() => _SupportReportScreenState();
}

class _SupportReportScreenState extends State<SupportReportScreen> {
  static const List<String> _categories = ['bug', 'complaint', 'idea', 'other'];

  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String _category = 'bug';
  bool _sending = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'bug':
        return t('supportCatBug');
      case 'complaint':
        return t('supportCatComplaint');
      case 'idea':
        return t('supportCatIdea');
      default:
        return t('supportCatOther');
    }
  }

  Future<void> _send() async {
    final message = _messageController.text.trim();
    if (message.length < 10) {
      Helpers.showToast(t('supportMessageTooShort'), isError: true);
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final role = auth.user?.role ?? '';
    final locale = Localizations.localeOf(context).languageCode;

    setState(() => _sending = true);
    try {
      final result = await SupportService.sendReport(
        category: _category,
        subject: _subjectController.text.trim(),
        message: message,
        context: SupportService.buildContext(
          screen: 'support_report',
          role: role,
          locale: locale,
        ),
      );

      if (!mounted) return;
      if (result['success'] == true) {
        final reference = (result['reference'] ?? '').toString();
        Helpers.showToast('${t('supportSent')} $reference');
        Navigator.of(context).pop();
      } else {
        Helpers.showToast(
          (result['error'] ?? t('supportFailed')).toString(),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('supportReportTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t('supportReportIntro'),
            style: TextStyle(fontSize: 13, color: theme.hintColor),
          ),
          const SizedBox(height: 16),
          Text(t('supportCategoryLabel'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _categories
                .map((category) => ChoiceChip(
                      label: Text(_categoryLabel(category)),
                      selected: _category == category,
                      onSelected: _sending
                          ? null
                          : (_) => setState(() => _category = category),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _subjectController,
            enabled: !_sending,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: t('supportSubjectLabel'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _messageController,
            enabled: !_sending,
            minLines: 5,
            maxLines: 10,
            maxLength: 4000,
            decoration: InputDecoration(
              labelText: t('supportMessageLabel'),
              helperText: t('supportMessageHint'),
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send, size: 18),
              label: Text(_sending ? t('supportSending') : t('supportSend')),
            ),
          ),
        ],
      ),
    );
  }
}
