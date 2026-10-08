// screens/admin_support_reports_screen.dart
// The reading half of the app's "Report a problem": every bug report and complaint that
// was stored and emailed, listed so it can be worked through and closed off.
//
// Admin-only, authenticated exactly like the rest of the admin panel: the platform admin
// password travels as a Bearer token against /api/admin/*.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../utils/helpers.dart';
import '../utils/i18n.dart';

class AdminSupportReportsScreen extends StatefulWidget {
  const AdminSupportReportsScreen({super.key, required this.adminToken});

  /// The platform admin password, as entered in the admin panel.
  final String adminToken;

  @override
  State<AdminSupportReportsScreen> createState() =>
      _AdminSupportReportsScreenState();
}

class _AdminSupportReportsScreenState extends State<AdminSupportReportsScreen> {
  static const List<String> _statuses = ['new', 'read', 'resolved'];

  static const Map<String, IconData> _categoryIcons = {
    'bug': Icons.bug_report_outlined,
    'complaint': Icons.sentiment_dissatisfied_outlined,
    'idea': Icons.lightbulb_outline,
    'other': Icons.help_outline,
  };

  List<Map<String, dynamic>> _reports = [];
  Map<String, int> _counts = {'new': 0, 'read': 0, 'resolved': 0};
  String _filter = 'all';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${widget.adminToken}',
        'Content-Type': 'application/json',
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(ApiConfig.adminSupportReports).replace(
        queryParameters: _filter == 'all' ? null : {'status': _filter},
      );
      final response = await http.get(uri, headers: _headers);
      final body = jsonDecode(response.body);

      if (response.statusCode == 200 && body is Map && body['success'] == true) {
        final data = body['data'] as Map? ?? const {};
        final list = data['reports'] as List? ?? const [];
        final counts = data['counts'] as Map? ?? const {};
        if (mounted) {
          setState(() {
            _reports =
                list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            _counts = {
              for (final status in _statuses)
                status: ((counts[status] as num?) ?? 0).toInt(),
            };
          });
        }
      } else if (mounted) {
        setState(() => _error =
            (body is Map ? body['message'] : null)?.toString() ??
                'HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Move a report to [status], recording a note when one is given.
  Future<void> _update(String reference, String status, {String? note}) async {
    try {
      final response = await http.patch(
        Uri.parse(ApiConfig.adminSupportReport(reference)),
        headers: _headers,
        body: jsonEncode({
          'status': status,
          if (note != null && note.trim().isNotEmpty)
            'resolutionNote': note.trim(),
        }),
      );
      final body = jsonDecode(response.body);
      if (response.statusCode == 200 && body is Map && body['success'] == true) {
        if (!mounted) return;
        Navigator.of(context).pop(); // close the detail sheet
        Helpers.showToast(t('supportUpdated'));
        await _load();
      } else {
        Helpers.showToast(
          (body is Map ? body['message'] : null)?.toString() ?? t('error'),
          isError: true,
        );
      }
    } catch (e) {
      Helpers.showToast('$e', isError: true);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'read':
        return t('supportStatusRead');
      case 'resolved':
        return t('supportStatusResolved');
      default:
        return t('supportStatusNew');
    }
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

  Color _statusColor(String status) {
    switch (status) {
      case 'read':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      default:
        return Colors.orange;
    }
  }

  /// "2026-10-07 14:32" — a support inbox does not need a date library.
  String _stamp(dynamic raw) {
    if (raw == null) return '';
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return raw.toString();
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  /// The full report: the user's own words first, then the context the app attached.
  void _openDetail(Map<String, dynamic> report) {
    final reference = report['reference']?.toString() ?? '';
    final status = report['status']?.toString() ?? 'new';
    final noteController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              Icon(_categoryIcons[report['category']] ?? Icons.help_outline),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _categoryLabel(report['category']?.toString() ?? 'other'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Chip(
                label: Text(_statusLabel(status)),
                labelStyle:
                    TextStyle(color: _statusColor(status), fontSize: 12),
                side: BorderSide(
                    color: _statusColor(status).withValues(alpha: 0.4)),
                backgroundColor: _statusColor(status).withValues(alpha: 0.1),
              ),
            ]),
            const SizedBox(height: 4),
            Text('#$reference',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 16),
            if ((report['subject'] ?? '').toString().isNotEmpty) ...[
              Text(report['subject'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
            ],
            Text(report['message']?.toString() ?? ''),
            const SizedBox(height: 20),
            Text(t('supportContext'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              [
                if ((report['company_name'] ?? '').toString().isNotEmpty)
                  '🏢 ${report['company_name']}',
                if ((report['username'] ?? '').toString().isNotEmpty)
                  '👤 ${report['username']}',
                if ((report['platform'] ?? '').toString().isNotEmpty)
                  '📱 ${report['platform']}',
                if ((report['app_version'] ?? '').toString().isNotEmpty)
                  '🔖 ${report['app_version']}',
                if ((report['screen'] ?? '').toString().isNotEmpty)
                  '🖥 ${report['screen']}',
                '🕒 ${_stamp(report['created_at'])}',
              ].join('\n'),
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            if ((report['resolution_note'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(t('supportResolutionNote'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(report['resolution_note'].toString(),
                  style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 20),
            if (status == 'new')
              OutlinedButton.icon(
                onPressed: () =>
                    _update(reference, 'read', note: noteController.text),
                icon: const Icon(Icons.done, size: 18),
                label: Text(t('supportMarkRead')),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: noteController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: t('supportResolutionNote'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () =>
                  _update(reference, 'resolved', note: noteController.text),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: Text(t('supportMarkResolved')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('adminSupportReportsTitle')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(t('supportFilterAll')),
                  selected: _filter == 'all',
                  onSelected: (_) => setState(() {
                    _filter = 'all';
                    _load();
                  }),
                ),
                for (final status in _statuses)
                  ChoiceChip(
                    label: Text(
                        '${_statusLabel(status)} (${_counts[status] ?? 0})'),
                    selected: _filter == status,
                    onSelected: (_) => setState(() {
                      _filter = status;
                      _load();
                    }),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  color: Theme.of(context).colorScheme.error, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: _load, child: Text(t('adminSupportReportsTitle'))),
            ],
          ),
        ),
      );
    }

    if (_reports.isEmpty) {
      return Center(
        child: Text(t('supportNoReports'),
            style: TextStyle(color: Colors.grey[600])),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _reports.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final report = _reports[index];
          final status = report['status']?.toString() ?? 'new';
          final message = report['message']?.toString() ?? '';
          final preview =
              message.length > 90 ? '${message.substring(0, 90)}…' : message;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: _statusColor(status).withValues(alpha: 0.15),
              child: Icon(
                _categoryIcons[report['category']] ?? Icons.help_outline,
                color: _statusColor(status),
                size: 20,
              ),
            ),
            title: Text(
              (report['subject'] ?? '').toString().isNotEmpty
                  ? report['subject'].toString()
                  : preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                if ((report['company_name'] ?? '').toString().isNotEmpty)
                  report['company_name'].toString(),
                _statusLabel(status),
                _stamp(report['created_at']),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: status == 'new'
                ? Icon(Icons.fiber_new, color: _statusColor(status))
                : null,
            onTap: () => _openDetail(report),
          );
        },
      ),
    );
  }
}