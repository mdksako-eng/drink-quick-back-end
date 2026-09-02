// screens/manager_approval_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../services/backend_auth_service.dart';
import '../utils/helpers.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';

class ManagerApprovalScreen extends StatefulWidget {
  const ManagerApprovalScreen({Key? key}) : super(key: key);

  @override
  State<ManagerApprovalScreen> createState() => _ManagerApprovalScreenState();
}

class _ManagerApprovalScreenState extends State<ManagerApprovalScreen> {
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _pendingJoins = [];
  bool _isLoading = true;
  bool _showJoins = false;
  Timer? _refreshTimer;
  bool _isDisposed = false;

  // Theme settings
  String _primaryColor = '#667EEA';
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadThemeSettings();
    _loadPendingRequests();
    // Auto-refresh every 10 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_isDisposed && mounted) {
        _loadPendingRequests();
        _loadPendingJoins();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadThemeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _primaryColor = prefs.getString('primary_color') ?? '#667EEA';
      _isDarkMode = prefs.getInt('theme_mode') == 1 ||
          (prefs.getInt('theme_mode') == 2 &&
              MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    });
  }

  Color get _primaryColorValue =>
      Color(int.parse(_primaryColor.replaceFirst('#', '0xFF')));

  Future<void> _loadPendingRequests() async {
    if (!mounted || _isDisposed) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final result = await BackendAuthService().getPendingRequests();

      if (!mounted || _isDisposed) return;

      if (result['status'] == 'success') {
        setState(() {
          _pendingRequests =
              List<Map<String, dynamic>>.from(result['requests'] ?? []);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        if (result['message'] != null) {
          Helpers.showToast(result['message'], isError: true);
        }
      }
    } catch (e) {
      print('Error loading requests: $e');
      if (mounted && !_isDisposed) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleApproval(String requestToken, bool approved) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user == null) {
      Helpers.showToast('User not authenticated', isError: true);
      return;
    }

    // Show loading indicator
    setState(() => _isLoading = true);

    try {
      final result = await BackendAuthService().approveLogin(
        requestToken: requestToken,
        approved: approved,
        managerId: user.id,
      );

      if (!mounted) return;

      if (result['status'] == 'success') {
        if (approved) {
          Helpers.showToast('✅ Login approved! Old session terminated.');
        } else {
          Helpers.showToast('❌ Login request rejected');
        }
        // Refresh the list
        await _loadPendingRequests();
      } else {
        Helpers.showToast(result['message'] ?? 'Error processing approval',
            isError: true);
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Approval error: $e');
      Helpers.showToast('Error: $e', isError: true);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 🔐 Load pending company join requests (owner verification)
  Future<void> _loadPendingJoins() async {
    if (!mounted || _isDisposed) return;
    try {
      final result = await BackendAuthService().getPendingJoins();
      if (!mounted || _isDisposed) return;
      if (result['status'] == 'success') {
        setState(() {
          _pendingJoins = List<Map<String, dynamic>>.from(result['requests'] ?? []);
        });
      }
    } catch (e) {
      print('Error loading join requests: $e');
    }
  }

  // 🔐 Approve (with emailed code) or reject a join request
  Future<void> _handleJoinAction(Map<String, dynamic> request, bool approve, {String? code}) async {
    setState(() => _isLoading = true);
    try {
      final result = await BackendAuthService().approveJoin(
        requestId: request['id'] is int ? request['id'] : int.tryParse('${request['id']}') ?? 0,
        approved: approve,
        code: code,
      );
      if (!mounted || _isDisposed) return;
      if (result['status'] == 'success') {
        Helpers.showToast(approve ? '✅ ${result['message'] ?? 'Member approved'}' : '🚫 ${result['message'] ?? 'Request rejected'}');
      } else {
        Helpers.showToast(result['message'] ?? 'Error processing request', isError: true);
      }
      await _loadPendingJoins();
      if (mounted && !_isDisposed) setState(() => _isLoading = false);
    } catch (e) {
      print('Join approval error: $e');
      if (mounted && !_isDisposed) setState(() => _isLoading = false);
      Helpers.showToast('Error: $e', isError: true);
    }
  }

  // 🔐 Ask the owner for the verification code emailed to them, then approve
  Future<void> _showCodeDialog(Map<String, dynamic> request) async {
    final codeController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Verification Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Approve ${request['username']} as ${request['requestedRole']}?\n\nEnter the 6-digit code sent to the company owner\'s email:'),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Code',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      await _handleJoinAction(request, true, code: codeController.text.trim());
    }
  }

  Widget _buildJoinsList(ThemeData theme) {
    if (_pendingJoins.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.how_to_reg, size: 60, color: Colors.green),
            const SizedBox(height: 16),
            const Text('No pending join requests',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('New members appear here for owner verification',
                style: TextStyle(color: theme.hintColor)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingJoins.length,
      itemBuilder: (context, index) {
        final request = _pendingJoins[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.orange.shade100,
                      child: Text(
                        (request['username'] ?? '?').toString().substring(0, 1).toUpperCase(),
                        style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${request['username'] ?? 'Unknown'}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('${request['email'] ?? ''}',
                              style: TextStyle(color: theme.hintColor, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${request['requestedRole'] ?? 'Staff'}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Wants to join • ${_getTimeAgo('${request['createdAt'] ?? request['created_at'] ?? ''}')}',
                    style: TextStyle(color: theme.hintColor)),
                const SizedBox(height: 4),
                Text('Verify with the code emailed to the company owner',
                    style: TextStyle(color: theme.hintColor, fontSize: 12, fontStyle: FontStyle.italic)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showCodeDialog(request),
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _handleJoinAction(request, false),
                        icon: const Icon(Icons.close, color: Colors.white),
                        label: const Text('Reject'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getTimeAgo(String timeStr) {
    try {
      final time = DateTime.parse(timeStr);
      final now = DateTime.now();
      final diff = now.difference(time);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
      return '${(diff.inDays / 30).floor()}mo ago';
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = _primaryColorValue;
    final primaryColorLight = primaryColor.withValues(alpha: 0.1);
    final primaryColorVeryLight = primaryColor.withValues(alpha: 0.05);

    return GestureDetector(
      onTap: () => LockService().resetTimer(),
      onPanDown: (_) => LockService().resetTimer(),
      onScaleStart: (_) => LockService().resetTimer(),
      onLongPress: () => LockService().resetTimer(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_showJoins ? 'Join Requests' : 'Login Approvals'),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 4,
          actions: [
            // 🔐 Toggle between login approvals and join requests
            TextButton.icon(
              onPressed: () => setState(() => _showJoins = !_showJoins),
              icon: Icon(_showJoins ? Icons.login : Icons.how_to_reg,
                  color: Colors.white, size: 18),
              label: Text(_showJoins ? 'Logins' : 'Joins${_pendingJoins.isNotEmpty ? ' (${_pendingJoins.length})' : ''}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _loadPendingRequests,
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: theme.brightness == Brightness.dark
                  ? [Colors.grey[900]!, Colors.grey[800]!]
                  : [Colors.grey[50]!, Colors.white],
            ),
          ),
          child: _showJoins
              ? _buildJoinsList(theme)
              : _isLoading && _pendingRequests.isEmpty
              ? Center(
                  child: CircularProgressIndicator(
                    color: primaryColor,
                  ),
                )
              : _pendingRequests.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 60,
                            color: Colors.green,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No pending requests',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'All staff members are logged in correctly',
                            style: TextStyle(
                              color: theme.hintColor,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _loadPendingRequests,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadPendingRequests,
                      color: primaryColor,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _pendingRequests.length,
                        itemBuilder: (context, index) {
                          final request = _pendingRequests[index];
                          final timeAgo =
                              _getTimeAgo(request['request_time'] ?? '');

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                            color: theme.cardColor,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: primaryColorLight,
                                        child: Icon(
                                          Icons.person,
                                          color: primaryColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              request['username'] ?? 'Staff',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: theme
                                                    .textTheme.bodyLarge?.color,
                                              ),
                                            ),
                                            Text(
                                              'Device: ${request['device_name'] ?? 'Unknown'}',
                                              style: TextStyle(
                                                color: theme.hintColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: primaryColorLight,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          timeAgo,
                                          style: TextStyle(
                                            color: primaryColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Requested to log in on new device',
                                    style: TextStyle(
                                      color: theme.hintColor,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _handleApproval(
                                            request['request_token'] ?? '',
                                            true,
                                          ),
                                          icon: const Icon(Icons.check,
                                              color: Colors.white),
                                          label: const Text('Approve'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _handleApproval(
                                            request['request_token'] ?? '',
                                            false,
                                          ),
                                          icon: const Icon(Icons.close,
                                              color: Colors.white),
                                          label: const Text('Reject'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ),
    );
  }
}
