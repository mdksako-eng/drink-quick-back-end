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
  bool _isLoading = true;
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
          title: const Text('Login Approvals'),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 4,
          actions: [
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
          child: _isLoading && _pendingRequests.isEmpty
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
