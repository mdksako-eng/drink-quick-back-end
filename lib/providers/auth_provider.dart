// providers/auth_provider.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import '../services/backend_auth_service.dart';
import '../services/supabase_service.dart';
import '../services/secure_storage_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/helpers.dart';
import '../main.dart' as app;
import '../screens/auth_screen.dart';
import '../screens/calculator_screen.dart';

// ============================================================
// User class (unchanged)
// ============================================================
class User {
  final String id;
  final String username;
  final String email;
  final Map<String, String> securityAnswers;
  final String role;
  final int? companyId;
  final bool emailVerified;
  /// True when this user is the founder/owner of their company
  /// (set automatically at company creation, or via DB backfill).
  final bool isOwner;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.securityAnswers,
    this.role = 'Customer',
    this.companyId,
    this.emailVerified = false,
    this.isOwner = false,
  });

  factory User.newUser({
    required String username,
    required String email,
    required Map<String, String> securityAnswers,
    int? companyId,
  }) {
    return User(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      username: username,
      email: email,
      securityAnswers: securityAnswers,
      role: 'Customer',
      companyId: companyId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'securityAnswers': securityAnswers,
      'role': role,
      'companyId': companyId,
      'emailVerified': emailVerified,
      'isOwner': isOwner,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    dynamic idValue = json['id'] ?? json['_id'];
    String id = '';

    if (idValue != null) {
      if (idValue is int) {
        id = idValue.toString();
      } else if (idValue is String) {
        id = idValue;
      }
    }

    return User(
      id: id.isNotEmpty ? id : 'temp_${DateTime.now().millisecondsSinceEpoch}',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      securityAnswers: Map<String, String>.from(
          json['securityAnswers'] ?? json['securityQuestions'] ?? {}),
      role: json['role']?.toString() ?? 'Customer',
      companyId: json['companyId'] ?? json['company_id'],
      emailVerified: json['emailVerified'] ?? json['email_verified'] ?? false,
      isOwner: json['isOwner'] == true || json['is_owner'] == true,
    );
  }

  @override
  String toString() {
    return 'User(id: $id, username: $username, email: $email, role: $role, emailVerified: $emailVerified, isOwner: $isOwner)';
  }
}

class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _error;
  bool _isOnline = true;
  bool _isLoggingOut = false;
  bool _isNotifying = false;
  String? _passwordHash;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // WhatsApp-Style Session Management
  Timer? _sessionCheckTimer;

  static const Duration _sessionCheckInterval = Duration(seconds: 30);
  static const Duration _sessionTimeout = Duration(hours: 8);
  bool _sessionValid = false;
  bool _showSessionTerminatedWarning = false;
  String? _previousDeviceName;

  final BackendAuthService _backendAuth = BackendAuthService();
  bool _isDisposed = false;
  Timer? _approvalTimer;
  int _pendingApprovalsCount = 0;
  int get pendingApprovalsCount => _pendingApprovalsCount;
  Timer? _approvalCountTimer;

  // ✅ NEW: Pending approval state
  String? _pendingUsername;
  String? _pendingPassword;
  String? _pendingRequestToken;
  bool _isPendingApproval = false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isOnline => _isOnline;
  User? get currentUser => _user;
  bool get sessionValid => _sessionValid;
  bool get showSessionTerminatedWarning => _showSessionTerminatedWarning;
  String? get previousDeviceName => _previousDeviceName;

  bool get isAdmin {
    if (_user == null) return false;
    final userRole = _user!.role.toLowerCase().trim();
    return userRole == 'admin' || userRole == 'administrator';
  }

  @override
  void dispose() {
    _isDisposed = true;
    _sessionCheckTimer?.cancel();
    _approvalTimer?.cancel();
    _approvalCountTimer?.cancel();
    super.dispose();
  }

  void _safeNotifyListeners() {
    if (_isDisposed || _isNotifying) return;
    if (!hasListeners) return;

    _isNotifying = true;
    try {
      notifyListeners();
      debugPrint('🔄 AuthProvider notified listeners. User: $_user');
    } catch (e) {
      debugPrint('❌ Error notifying listeners: $e');
    } finally {
      _isNotifying = false;
    }
  }

  void setOnlineStatus(bool isOnline) {
    if (_isDisposed) return;
    _isOnline = isOnline;
    _safeNotifyListeners();
  }

  // ============================================================
  // Helper method to parse company ID
  // ============================================================
  int? _parseCompanyId(Map<String, dynamic> userData) {
    if (userData['companyId'] != null) {
      return int.tryParse(userData['companyId'].toString());
    }
    if (userData['company_id'] != null) {
      return int.tryParse(userData['company_id'].toString());
    }
    return null;
  }

  Future<void> fetchPendingApprovalsCount() async {
    try {
      if (_user == null) {
        _pendingApprovalsCount = 0;
        _safeNotifyListeners();
        return;
      }

      final userRole = _user!.role.toLowerCase().trim();
      if (userRole != 'manager' &&
          userRole != 'administrator' &&
          userRole != 'admin') {
        _pendingApprovalsCount = 0;
        _safeNotifyListeners();
        return;
      }

      final token = await SecureStorageService.getSessionToken();
      if (token == null || token.isEmpty) {
        _pendingApprovalsCount = 0;
        _safeNotifyListeners();
        return;
      }

      final response = await http.get(
        Uri.parse('${BackendAuthService.baseUrl}/api/auth/pending-requests'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final requests = data['requests'] as List? ?? [];
        _pendingApprovalsCount = requests.length;
        debugPrint('📊 Pending approvals: $_pendingApprovalsCount');
      } else {
        _pendingApprovalsCount = 0;
      }
    } catch (e) {
      debugPrint('❌ Error fetching pending approvals: $e');
      _pendingApprovalsCount = 0;
    }
    _safeNotifyListeners();
  }

  void startApprovalCountRefresh() {
    _approvalCountTimer?.cancel();
    _approvalCountTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => fetchPendingApprovalsCount(),
    );
  }

  Future<bool> checkBackendConnection() async {
    try {
      final result = await _backendAuth.testBackend();
      final isConnected = result['success'] == true;
      setOnlineStatus(isConnected);
      return isConnected;
    } catch (e) {
      debugPrint('Backend connection error: $e');
      setOnlineStatus(false);
      return false;
    }
  }

  void _startSessionValidation() {
    _sessionCheckTimer?.cancel();
    _sessionCheckTimer = Timer.periodic(_sessionCheckInterval, (timer) async {
      if (_isLoggingOut || _isDisposed) {
        debugPrint('⏭️ Skipping session check (logging out or disposed)');
        return;
      }
      final isValid = await _validateCurrentSession();
      if (!isValid && !_isDisposed) {
        timer.cancel();
        _handleSessionTerminated();
      }
    });
    _sessionValid = true;
  }

  Future<bool> _validateCurrentSession() async {
    try {
      if (!_hasValidUserId()) {
        debugPrint('🚨 Session validation: Invalid user ID');
        await _forceLogout('Invalid user session. Please login again.');
        return false;
      }
      final session = await SecureStorageService.getSession();
      final sessionCreated = session['sessionCreated'];

      if (sessionCreated != null) {
        final created = DateTime.parse(sessionCreated);
        final age = DateTime.now().difference(created);
        if (age > _sessionTimeout) {
          await _forceLogout('Session expired. Please login again.');
          return false;
        }
      }

      final token = await SecureStorageService.getSessionToken();
      if (token == null || token.isEmpty) {
        return false;
      }

      final baseUrl = BackendAuthService.baseUrl;
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/validate-session'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (data['terminated'] == true) {
        _previousDeviceName = data['previousDeviceName'] ?? 'another device';
        return false;
      }

      return data['valid'] == true;
    } catch (e) {
      return true;
    }
  }

  void _handleSessionTerminated() {
    if (_showSessionTerminatedWarning) {
      debugPrint('⚠️ Session termination already in progress, skipping...');
      return;
    }
    _showSessionTerminatedWarning = true;
    _sessionValid = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        _showSessionTerminatedDialog();
      }
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (!_isDisposed) {
        logout();
        _safeNotifyListeners();
      }
    });
  }

  // ============================================================
  // APPROVAL DIALOG METHODS
  // ============================================================

  void _showApprovalPendingDialog(
      String deviceName, String requestToken, List managers) {
    debugPrint('🔔 ===== SHOWING APPROVAL PENDING DIALOG =====');
    debugPrint('📱 Device Name: $deviceName');
    debugPrint('🔑 Request Token: $requestToken');
    debugPrint('👥 Managers: ${managers.length}');

    _approvalTimer?.cancel();
    _approvalTimer = null;

    BuildContext? context = _getContext();

    if (context == null) {
      debugPrint('⚠️ _getContext() returned null, trying navigatorKey');
      context = app.navigatorKey.currentContext;
    }

    if (context == null) {
      debugPrint('⚠️ navigatorKey.currentContext is null, trying overlay');
      try {
        context = app.navigatorKey.currentState?.overlay?.context;
        debugPrint('📱 Overlay context: ${context != null ? "FOUND" : "NULL"}');
      } catch (e) {
        debugPrint('❌ Error getting overlay context: $e');
      }
    }

    if (context == null) {
      debugPrint(
          '⚠️ Still no context, trying to get from navigator key in AuthProvider');
      context = navigatorKey.currentContext;
    }

    if (context == null) {
      debugPrint('❌ No context available - showing alternative UI');
      _showApprovalAsOverlay(deviceName, requestToken, managers);
      return;
    }

    if (!context.mounted) {
      debugPrint('⚠️ Context is not mounted, waiting for rebuild...');
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_isDisposed) {
          _showApprovalPendingDialog(deviceName, requestToken, managers);
        }
      });
      return;
    }

    _showApprovalDialog(context, deviceName, requestToken, managers);
  }

  void _showApprovalAsOverlay(
      String deviceName, String requestToken, List managers) {
    debugPrint('🔄 Showing approval as overlay...');
    Helpers.showToast('⏳ Waiting for manager approval...');

    _approvalTimer?.cancel();
    _approvalTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        final result = await _backendAuth.checkApprovalStatus(requestToken);
        if (result['status'] == 'success') {
          final status = result['approvalStatus'];
          if (status == 'approved') {
            debugPrint('✅ Auto-check: Login approved!');
            timer.cancel();
            _approvalTimer = null;
            final sessionToken = result['sessionToken'];
            await _completeApprovedLogin(sessionToken);
          } else if (status == 'rejected') {
            debugPrint('❌ Auto-check: Login rejected');
            timer.cancel();
            _approvalTimer = null;
            Helpers.showToast('❌ Login rejected by manager', isError: true);
            _isLoading = false;
            _safeNotifyListeners();
          }
        }
      } catch (e) {
        // Ignore errors, continue polling
      }
    });

    Future.delayed(const Duration(minutes: 15), () {
      if (_approvalTimer != null && _approvalTimer!.isActive) {
        _approvalTimer?.cancel();
        _approvalTimer = null;
        if (!_isDisposed) {
          Helpers.showToast('⏰ Approval request expired. Please try again.',
              isError: true);
          _isLoading = false;
          _safeNotifyListeners();
        }
      }
    });
  }

  void _showApprovalDialog(BuildContext context, String deviceName,
      String requestToken, List managers) {
    debugPrint('📱 Showing approval dialog with context: ${context.hashCode}');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('⏳ Waiting for Approval'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top, size: 60, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'Please wait for manager approval to login on:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                deviceName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Managers: ${managers.map((m) => m['username']).join(', ')}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text(
              'This request will expire in 15 minutes.',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sync, color: Colors.green, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Auto-checking every 10 seconds',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint('🔍 User clicked "Check Status"');
              Navigator.pop(dialogContext);
              _checkApprovalStatus(requestToken);
            },
            child: const Text('Check Status'),
          ),
          TextButton(
            onPressed: () {
              debugPrint('❌ User cancelled approval request');
              Navigator.pop(dialogContext);
              _isLoading = false;
              _safeNotifyListeners();
              Helpers.showToast('Login cancelled');
              _approvalTimer?.cancel();
              _approvalTimer = null;
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ).then((_) {
      debugPrint('📴 Approval dialog closed');
    });

    if (_approvalTimer == null || !_approvalTimer!.isActive) {
      debugPrint('⏰ Starting auto-approval timer...');
      _approvalTimer =
          Timer.periodic(const Duration(seconds: 10), (timer) async {
        try {
          final result = await _backendAuth.checkApprovalStatus(requestToken);
          if (result['status'] == 'success') {
            final status = result['approvalStatus'];
            if (status == 'approved') {
              debugPrint('✅ Auto-check: Login approved!');
              timer.cancel();
              _approvalTimer = null;
              final sessionToken = result['sessionToken'];
              await _completeApprovedLogin(sessionToken);
            } else if (status == 'rejected') {
              debugPrint('❌ Auto-check: Login rejected');
              timer.cancel();
              _approvalTimer = null;
              _showApprovalRejectedDialog();
            }
          }
        } catch (e) {
          // Ignore errors, continue polling
        }
      });

      Future.delayed(const Duration(minutes: 15), () {
        if (_approvalTimer != null && _approvalTimer!.isActive) {
          _approvalTimer?.cancel();
          _approvalTimer = null;
          if (!_isDisposed) {
            Helpers.showToast('⏰ Approval request expired. Please try again.',
                isError: true);
            _isLoading = false;
            _safeNotifyListeners();
          }
        }
      });
    }
  }

  Future<void> _checkApprovalStatus(String requestToken) async {
    debugPrint('🔍 Manual check approval status for: $requestToken');

    _approvalTimer?.cancel();
    _approvalTimer = null;

    _approvalTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        final result = await _backendAuth.checkApprovalStatus(requestToken);

        if (result['status'] == 'success') {
          final status = result['approvalStatus'];

          if (status == 'approved') {
            timer.cancel();
            _approvalTimer = null;
            final sessionToken = result['sessionToken'];
            await _completeApprovedLogin(sessionToken);
            return;
          } else if (status == 'rejected') {
            timer.cancel();
            _approvalTimer = null;
            _showApprovalRejectedDialog();
            return;
          }
        }
      } catch (e) {
        debugPrint('⚠️ Approval poll error: $e');
      }
    });

    Future.delayed(const Duration(minutes: 15), () {
      if (_approvalTimer != null && _approvalTimer!.isActive) {
        _approvalTimer?.cancel();
        _approvalTimer = null;
        if (!_isDisposed) {
          Helpers.showToast('⏰ Approval request expired. Please try again.',
              isError: true);
          _isLoading = false;
          _safeNotifyListeners();
        }
      }
    });
  }

  // ============================================================
  // ✅✅✅ FIXED: Complete approved login - handles _user == null
  // ============================================================
  Future<void> _completeApprovedLogin(String sessionToken) async {
    debugPrint('✅ Completing approved login...');
    debugPrint(
        '   Session Token: ${sessionToken.length > 20 ? sessionToken.substring(0, 20) : sessionToken}...');

    // ✅ If _user is null, create it from pending data
    if (_user == null && _pendingUsername != null) {
      debugPrint('📝 _user is null - creating user from pending data');
      debugPrint('   Pending username: $_pendingUsername');

      // ✅ Try to fetch full user data from backend
      try {
        final backendUser =
            await _backendAuth.getUserByUsername(_pendingUsername!);
        if (backendUser != null) {
          _user = User(
            id: backendUser.id,
            username: backendUser.username,
            email: backendUser.email,
            securityAnswers: backendUser.securityAnswers,
            role: backendUser.role ?? 'Staff',
            companyId: backendUser.companyId,
          );
          debugPrint(
              '✅ User fetched from backend: ${_user!.username} (${_user!.role})');
        } else {
          // ✅ Fallback: Create user from pending data
          _user = User(
            id: 'user_${DateTime.now().millisecondsSinceEpoch}',
            username: _pendingUsername!,
            email: '',
            securityAnswers: {},
            role: 'Staff',
            companyId: null,
          );
          debugPrint(
              '⚠️ Created minimal user from pending data: ${_user!.username}');
        }
      } catch (e) {
        debugPrint('❌ Failed to fetch user data: $e');
        // ✅ Fallback: Create minimal user
        _user = User(
          id: 'user_${DateTime.now().millisecondsSinceEpoch}',
          username: _pendingUsername!,
          email: '',
          securityAnswers: {},
          role: 'Staff',
          companyId: null,
        );
        debugPrint('⚠️ Created fallback user: ${_user!.username}');
      }
    }

    if (_user == null) {
      debugPrint('❌ Cannot complete login - no user data available');
      Helpers.showToast('❌ Login failed: No user data available',
          isError: true);
      _isLoading = false;
      _safeNotifyListeners();
      return;
    }

    debugPrint('✅ Completing login for: ${_user!.username} (${_user!.role})');

    // ✅ Save session
    final deviceFingerprint = await SecureStorageService.getDeviceFingerprint();
    await SecureStorageService.saveSession(
      userId: int.tryParse(_user!.id) ?? 0,
      sessionToken: sessionToken,
      deviceFingerprint: deviceFingerprint,
    );

    // ✅ Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', sessionToken);
    await prefs.setString('user_data', jsonEncode(_user!.toJson()));

    // ✅ Set Supabase context
    final companyId = _user?.companyId;
    final userIdInt = _user?.id != null ? int.tryParse(_user!.id) : null;
    SupabaseService.setCompanyContext(companyId, userIdInt);
    debugPrint(
        '✅ Supabase context set - companyId: $companyId, userId: $userIdInt');

    // ✅ Start session validation
    _startSessionValidation();

    // ✅ Clear pending data
    _pendingUsername = null;
    _pendingPassword = null;
    _pendingRequestToken = null;
    _isPendingApproval = false;

    _isLoading = false;
    _safeNotifyListeners();

    Helpers.showToast('✅ Login approved! Welcome ${_user!.username}.');

    // ✅ Navigate to calculator screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navContext = app.navigatorKey.currentContext;
      if (navContext != null && navContext.mounted) {
        Navigator.of(navContext).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const CalculatorScreen()),
          (route) => false,
        );
      }
    });
  }

  void _showApprovalRejectedDialog() {
    final context = _getContext();
    if (context == null) {
      Helpers.showToast('❌ Login rejected by manager', isError: true);
      _isLoading = false;
      _safeNotifyListeners();
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('❌ Login Rejected'),
        content: const Text(
          'Your login request was rejected by the manager.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _isLoading = false;
              _safeNotifyListeners();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showManagerOverrideDialog() {
    Helpers.showToast('✅ Previous session terminated (Manager override)');
  }

  // ============================================================
  // SESSION TERMINATED DIALOG
  // ============================================================
  void _showSessionTerminatedDialog() {
    debugPrint('🔴🔴🔴 SHOWING SESSION TERMINATED DIALOG 🔴🔴🔴');
    debugPrint('   Previous Device: $_previousDeviceName');

    BuildContext? context = _getContext();

    if (context == null) {
      debugPrint('⚠️ _getContext() returned null, trying navigatorKey');
      context = app.navigatorKey.currentContext;
    }

    if (context == null) {
      debugPrint('⚠️ navigatorKey.currentContext is null, trying overlay');
      try {
        context = app.navigatorKey.currentState?.overlay?.context;
      } catch (e) {
        debugPrint('❌ Error getting overlay context: $e');
      }
    }

    if (context == null) {
      debugPrint('❌ NO CONTEXT AVAILABLE - showing toast instead');
      Helpers.showToast('🔒 Session terminated. Please login again.');
      return;
    }

    if (!context.mounted) {
      debugPrint('⚠️ Context is not mounted, waiting for rebuild...');
      Future.delayed(const Duration(milliseconds: 300), () {
        _showSessionTerminatedDialog();
      });
      return;
    }

    debugPrint('✅ Context available, showing dialog...');

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.cardColor;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.black;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: isDark ? Colors.black87 : Colors.black54,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: cardColor,
        elevation: 4,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: isDark ? 0.2 : 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Session Terminated',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.phonelink_erase,
              size: 60,
              color: isDark ? Colors.red.shade300 : Colors.red.shade700,
            ),
            const SizedBox(height: 16),
            Text(
              _previousDeviceName != null
                  ? 'Your account is now active on another device.\n\n📱 Previous Device: ${_previousDeviceName!}'
                  : 'Your account is now active on another device.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: textColor,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.orange.withValues(alpha: 0.1)
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.orange.withValues(alpha: 0.2)
                      : Colors.orange.shade200,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.security,
                    color: isDark
                        ? Colors.orange.shade300
                        : Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'For security, you have been logged out from this device.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.orange.shade200
                            : Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                debugPrint('🔴 User clicked "OK, Logout"');
                Navigator.pop(dialogContext);
                await logout();

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final navContext = app.navigatorKey.currentContext;
                  if (navContext != null && navContext.mounted) {
                    Navigator.of(navContext).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (context) => const AuthScreen()),
                      (route) => false,
                    );
                  }
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isDark ? Colors.orange.shade700 : Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: isDark ? 0 : 2,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'OK, Logout',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  BuildContext? _getContext() {
    if (navigatorKey.currentContext != null &&
        navigatorKey.currentContext!.mounted) {
      return navigatorKey.currentContext;
    }

    if (app.navigatorKey.currentContext != null &&
        app.navigatorKey.currentContext!.mounted) {
      return app.navigatorKey.currentContext;
    }

    try {
      final overlayContext = app.navigatorKey.currentState?.overlay?.context;
      if (overlayContext != null && overlayContext.mounted) {
        return overlayContext;
      }
    } catch (e) {
      debugPrint('Error getting overlay context: $e');
    }

    return null;
  }

  Future<void> _forceLogout(String message) async {
    if (_isLoggingOut) return;
    _error = message;
    await logout();
    _safeNotifyListeners();
  }

  Future<void> autoLogin() async {
    if (_isDisposed) return;

    debugPrint('🔄 Starting autoLogin...');
    _isLoading = true;
    _safeNotifyListeners();

    try {
      await _loadUserFromStorage();

      if (_user != null) {
        debugPrint('✅ Found user in storage: ${_user!.username}');
        await checkBackendConnection();

        if (_isOnline) {
          final token = await SecureStorageService.getSessionToken();

          if (token != null && token.isNotEmpty) {
            debugPrint('🔑 Found session token, validating...');

            final isValid = await _validateCurrentSession();

            if (isValid) {
              _startSessionValidation();
              _sessionValid = true;
              debugPrint('✅ Session restored successfully');

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('auth_token', token);

              _isLoading = false;
              _safeNotifyListeners();
              return;
            } else {
              debugPrint('❌ Session invalid, clearing...');
              await SecureStorageService.clearSession();
            }
          }

          debugPrint('🌐 Online - attempting backend validation...');
          try {
            final backendUser = await _backendAuth.getCurrentUser();
            if (backendUser != null) {
              _user = User(
                id: backendUser.id,
                username: backendUser.username,
                email: backendUser.email,
                securityAnswers: backendUser.securityAnswers,
                role: _user!.role,
                companyId: _user?.companyId,
              );
              debugPrint('✅ Backend validation successful');
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('user_data', jsonEncode(_user!.toJson()));
            } else {
              debugPrint('⚠️ No user found on backend, using local storage');
            }
          } catch (e) {
            debugPrint('⚠️ Backend validation failed, using local user: $e');
          }
        } else {
          debugPrint('📴 Offline - using local user');
        }
      } else {
        debugPrint('❌ No user found in storage');
      }
    } catch (error) {
      debugPrint('🚨 Auto login error: $error');
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        _safeNotifyListeners();
        debugPrint('✅ AutoLogin completed');
      }
    }
  }

  Future<void> _loadUserFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user_data');
      final passwordHash = prefs.getString('password_hash');

      if (userJson != null && userJson.isNotEmpty) {
        final userMap = jsonDecode(userJson) as Map<String, dynamic>;
        _user = User.fromJson(userMap);
        _passwordHash = passwordHash;
        debugPrint('📂 Loaded user from storage: $_user');
      } else {
        debugPrint('📂 No user data in storage');
      }
    } catch (e) {
      debugPrint('🚨 Load user from storage error: $e');
    }
  }

  bool _hasValidUserId() {
    if (_user == null) return false;
    final id = _user!.id;
    return id.isNotEmpty &&
        !id.startsWith('temp_') &&
        !id.startsWith('offline_');
  }

  String _simpleHash(String password) {
    return (password.hashCode % 1000000).toString();
  }

  Future<void> _setupOfflineStorage() async {
    if (_user == null) return;

    final prefs = await SharedPreferences.getInstance();

    if (_user!.role == 'Customer') {
      debugPrint('📂 Customer user: ${_user!.username}');
    } else if (_user!.companyId != null) {
      await prefs.setInt('last_company_id', _user!.companyId!);
      debugPrint(
          '📂 Company user: ${_user!.username}, company: ${_user!.companyId}');
    }
  }

  Future<String> _getDeviceId() async {
    try {
      if (kIsWeb) {
        return 'web_${DateTime.now().millisecondsSinceEpoch}';
      }
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return 'android_${androidInfo.id}_${androidInfo.device}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return 'ios_${iosInfo.identifierForVendor ?? 'unknown'}';
      }
    } catch (e) {
      // Ignore
    }
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<String> _getDeviceName() async {
    try {
      if (kIsWeb) {
        return 'Web Browser';
      }
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return '${androidInfo.manufacturer} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.name ?? 'iOS Device';
      }
    } catch (e) {
      debugPrint('⚠️ Error getting device name: $e');
    }
    return 'Unknown Device';
  }

  // ============================================================
// ✅ COMPLETE FIXED LOGIN METHOD
// ============================================================
  Future<bool> login(String username, String password) async {
    if (_isDisposed) return false;

    debugPrint('🔑 AuthProvider.login() called for: $username');

    _isLoading = true;
    _error = null;
    _showSessionTerminatedWarning = false;
    _previousDeviceName = null;
    _safeNotifyListeners();

    try {
      final isConnected = await checkBackendConnection();

      if (isConnected) {
        debugPrint('🌐 Online login attempt...');

        final deviceFingerprint =
            await SecureStorageService.getDeviceFingerprint();
        final deviceName = await _getDeviceName();
        final deviceId = await _getDeviceId();

        final fingerprintPreview = deviceFingerprint.length > 10
            ? deviceFingerprint.substring(0, 10)
            : deviceFingerprint;
        debugPrint(
            '📱 Device: $deviceName, Fingerprint: $fingerprintPreview...');

        final result = await _backendAuth.login(
          username: username,
          password: password,
          deviceId: deviceId,
          deviceName: deviceName,
        );

        debugPrint('📨 Login result:');
        debugPrint('   Success: ${result['success']}');
        debugPrint('   Message: ${result['message']}');
        debugPrint('📨 FULL RESULT: $result');

        final data = result['data'];

        // ============================================================
        // ✅ CRITICAL: Check PENDING FIRST
        // ============================================================
        if (data is Map && data['status'] == 'pending') {
          debugPrint('⏳🔴 LOGIN PENDING - Staff needs manager approval');
          debugPrint('   Device: ${data['deviceName']}');
          debugPrint('   Request Token: ${data['requestToken']}');
          debugPrint('   Managers: ${data['managers']?.length ?? 0}');

          _pendingUsername = username;
          _pendingPassword = password;
          _pendingRequestToken = data['requestToken'];
          _isPendingApproval = true;
          debugPrint('📝 Stored pending user data for: $username');

          _isLoading = false;
          _safeNotifyListeners();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showApprovalPendingDialog(
              data['deviceName'] ?? 'Unknown Device',
              data['requestToken'] ?? '',
              data['managers'] ?? [],
            );
          });
          return false;
        }

        // ✅ Previous session terminated (Manager override)
        if (data is Map && data['previousDeviceTerminated'] == true) {
          debugPrint('🔄 Previous session terminated - Manager override');
          _showManagerOverrideDialog();

          // ✅ FIX: Extract session token from nested data
          String sessionToken = '';
          if (data.containsKey('data') && data['data'] is Map) {
            final innerData = Map<String, dynamic>.from(data['data']);
            sessionToken = innerData['sessionToken'] ??
                innerData['token'] ??
                innerData['accessToken'] ??
                '';
          }
          if (sessionToken.isEmpty) {
            sessionToken = data['sessionToken'] ?? data['token'] ?? '';
          }

          if (sessionToken.isNotEmpty && _user != null) {
            final deviceFingerprint =
                await SecureStorageService.getDeviceFingerprint();
            await SecureStorageService.saveSession(
              userId: int.tryParse(_user!.id) ?? 0,
              sessionToken: sessionToken,
              deviceFingerprint: deviceFingerprint,
            );
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('auth_token', sessionToken);
          }

          _startSessionValidation();
          _isLoading = false;
          _safeNotifyListeners();
          return true;
        }

        // ✅ Email not verified
        if (result['code'] == 'EMAIL_NOT_VERIFIED') {
          _isLoading = false;
          _error =
              'EMAIL_NOT_VERIFIED|${result['message'] ?? 'Please verify your email first.'}';
          _safeNotifyListeners();
          return false;
        }

        // ✅ Login failed
        if (result['success'] != true) {
          _error = result['message'] ?? 'Login failed';
          debugPrint('❌ Login failed: $_error');
          _isLoading = false;
          _safeNotifyListeners();
          return false;
        }

        // ============================================================
        // ✅ ACTUAL SUCCESSFUL LOGIN
        // ============================================================
        debugPrint('✅ ACTUAL SUCCESSFUL LOGIN - processing user data...');

        Map<String, dynamic> userData = {};

        // ✅ Extract user data from nested structure
        if (data is Map) {
          // ✅ Try data.data.user first
          if (data.containsKey('data') && data['data'] is Map) {
            final innerData = Map<String, dynamic>.from(data['data']);
            if (innerData.containsKey('user') && innerData['user'] is Map) {
              userData = Map<String, dynamic>.from(innerData['user']);
              debugPrint(
                  '✅ Found user data in data.data.user: ${userData['username']}');
            }
          }

          // ✅ If not found, try data.user
          if (userData.isEmpty &&
              data.containsKey('user') &&
              data['user'] is Map) {
            userData = Map<String, dynamic>.from(data['user']);
            debugPrint(
                '✅ Found user data in data.user: ${userData['username']}');
          }

          // ✅ If not found, try data directly
          if (userData.isEmpty &&
              (data.containsKey('username') || data.containsKey('email'))) {
            userData = Map<String, dynamic>.from(data);
            debugPrint(
                '✅ Found user data directly in data: ${userData['username']}');
          }
        }

        if (userData.isEmpty) {
          debugPrint('❌ No user data found');
          _error = 'Invalid user data received from server';
          _isLoading = false;
          _safeNotifyListeners();
          return false;
        }

        // ✅ Extract user ID
        dynamic idValue = userData['id'] ??
            userData['_id'] ??
            userData['userId'] ??
            userData['user_id'];

        String userId = '';

        if (idValue != null) {
          if (idValue is int) {
            userId = idValue.toString();
            debugPrint('✅ Converted ID from int to string: $userId');
          } else if (idValue is String && idValue.isNotEmpty) {
            userId = idValue;
            debugPrint('✅ Using ID from string: $userId');
          }
        }

        if (userId.isEmpty) {
          debugPrint('❌ No valid user ID found');
          _error = 'Invalid user ID received from server';
          _isLoading = false;
          _safeNotifyListeners();
          return false;
        }

        String role = userData['role']?.toString() ?? 'Customer';
        debugPrint('✅ User role detected: $role');

        _user = User(
          id: userId,
          username: userData['username']?.toString() ?? username,
          email: userData['email']?.toString() ?? '',
          securityAnswers: Map<String, String>.from(
              userData['securityAnswers'] ??
                  userData['securityQuestions'] ??
                  {}),
          role: role,
          companyId: _parseCompanyId(userData),
          emailVerified:
              userData['emailVerified'] ?? userData['email_verified'] ?? false,
        );

        debugPrint('✅ User object created: ${_user!.toJson()}');

        _passwordHash = _simpleHash(password);
        await _setupOfflineStorage();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_data', jsonEncode(_user!.toJson()));
        await prefs.setString('password_hash', _passwordHash!);

        await fetchPendingApprovalsCount();
        startApprovalCountRefresh();

        // ============================================================
        // ✅ FIX: Extract session token from nested data
        // ============================================================
        String sessionToken = '';

        if (data is Map) {
          // ✅ Try data.data.sessionToken first
          if (data.containsKey('data') && data['data'] is Map) {
            final innerData = Map<String, dynamic>.from(data['data']);
            sessionToken = innerData['sessionToken'] ??
                innerData['token'] ??
                innerData['accessToken'] ??
                '';
            if (sessionToken.isNotEmpty) {
              debugPrint('✅ Found sessionToken in data.data');
            }
          }

          // ✅ If not found, try data directly
          if (sessionToken.isEmpty) {
            sessionToken = data['sessionToken'] ??
                data['token'] ??
                data['accessToken'] ??
                data['access_token'] ??
                '';
            if (sessionToken.isNotEmpty) {
              debugPrint('✅ Found sessionToken in data');
            }
          }
        }

        if (sessionToken.isNotEmpty) {
          final tokenPreview = sessionToken.length > 20
              ? sessionToken.substring(0, 20)
              : sessionToken;
          debugPrint('🔑 SESSION TOKEN: FOUND ($tokenPreview...)');
        } else {
          debugPrint('🔑 SESSION TOKEN: EMPTY');
        }

        if (sessionToken.isNotEmpty) {
          await SecureStorageService.saveSession(
            userId: int.tryParse(_user!.id) ?? 0,
            sessionToken: sessionToken,
            deviceFingerprint: deviceFingerprint,
          );

          final savedToken = await SecureStorageService.getSessionToken();
          debugPrint(
              '🔑 SAVED TOKEN: ${savedToken != null && savedToken.isNotEmpty ? "✅ SAVED" : "❌ NOT SAVED"}');

          await prefs.setString('auth_token', sessionToken);
          debugPrint('✅ Auth token saved');
        } else {
          debugPrint('⚠️ No session token to save!');
        }

        final companyId = _user?.companyId;
        final userIdInt = _user?.id != null ? int.tryParse(_user!.id) : null;
        SupabaseService.setCompanyContext(companyId, userIdInt);
        debugPrint(
            '✅ Supabase context set - companyId: $companyId, userId: $userIdInt');

        _error = null;
        debugPrint(
            '✅ Login successful! User: ${_user!.username} (${_user!.role})');

        if (data is Map && data['previousDevice'] != null) {
          _showSessionTerminatedWarning = true;
          _previousDeviceName =
              data['previousDevice']['deviceName'] ?? 'another device';
        }

        _startSessionValidation();

        _isLoading = false;
        _safeNotifyListeners();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          final navContext = app.navigatorKey.currentContext;
          if (navContext != null && navContext.mounted) {
            Navigator.of(navContext).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const CalculatorScreen()),
              (route) => false,
            );
          }
        });

        return true;
      } else {
        // Offline login
        debugPrint('📴 Offline login attempt...');

        await _loadUserFromStorage();

        if (_user != null &&
            (_user!.username == username || _user!.email == username)) {
          if (_passwordHash == null) {
            _passwordHash = _simpleHash(password);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('password_hash', _passwordHash!);
          }

          final inputHash = _simpleHash(password);
          if (inputHash == _passwordHash) {
            debugPrint('✅ Offline login successful: ${_user!.username}');
            _isLoading = false;
            _safeNotifyListeners();
            return true;
          } else {
            _error = 'Invalid password';
            debugPrint('❌ Offline login failed: Invalid password');
            _isLoading = false;
            _safeNotifyListeners();
            return false;
          }
        } else {
          _error = 'User not found in local storage';
          debugPrint('❌ Offline login failed: $_error');
          _isLoading = false;
          _safeNotifyListeners();
          return false;
        }
      }
    } catch (error) {
      debugPrint('🚨 Login error: $error');
      _error = 'Login failed: $error';
      _isLoading = false;
      _safeNotifyListeners();
      return false;
    }
  }

  Future<bool> checkSessionValidity() async {
    return await _validateCurrentSession();
  }

  Map<String, dynamic> getSessionWarningInfo() {
    return {
      'showWarning': _showSessionTerminatedWarning,
      'previousDevice': _previousDeviceName,
      'message': _showSessionTerminatedWarning
          ? 'Your account is now active on another device. You have been logged out from this device.'
          : null,
    };
  }

  void clearSessionWarning() {
    _showSessionTerminatedWarning = false;
    _previousDeviceName = null;
    _safeNotifyListeners();
  }

  Future<bool> signup(String username, String email, String password,
      String securityAnswer1, String securityAnswer2,
      {String? phone,
      bool registerAsManager = false,
      String? companyId,
      String? companyName,
      String? companyCode,
      String? companyAddress}) async {
    if (_isDisposed) return false;

    debugPrint('📝 AuthProvider.signup() called for: $username ($email)');

    _isLoading = true;
    _error = null;
    _showSessionTerminatedWarning = false;
    _safeNotifyListeners();

    try {
      final isConnected = await checkBackendConnection();

      if (!isConnected) {
        _error =
            'No internet connection. Please check your connection and try again.';
        _isLoading = false;
        _safeNotifyListeners();
        return false;
      }

      debugPrint('🌐 Sending registration request to backend...');

      final securityQuestions = <String, String>{
        'question1': securityAnswer1,
        'question2': securityAnswer2,
      };

      final result = await _backendAuth.register(
        username: username.trim(),
        email: email.trim(),
        password: password,
        securityQuestions: securityQuestions,
        phone: phone,
        registerAsManager: registerAsManager,
        companyId: companyId,
        companyName: companyName,
        companyCode: companyCode,
        companyAddress: companyAddress,
      );

      debugPrint(
          '📨 Registration result: success=${result['success']} message=${result['message']}');

      if (result['success'] == true) {
        debugPrint('✅ Registration created for: $username');
        _error = null;
        _isLoading = false;
        _safeNotifyListeners();
        return true;
      }

      // Registration failed — surface the REAL backend message
      // (e.g. "Username already taken" / "Email already registered")
      String message = result['message']?.toString() ?? 'Registration failed';
      message = message.replaceFirst(RegExp(r'^[❌⚠️\s]+'), '').trim();
      _error = message.isNotEmpty
          ? message
          : 'Registration failed. Please try again.';
      debugPrint('❌ Registration failed: $_error');

      _isLoading = false;
      _safeNotifyListeners();
      return false;
    } catch (e) {
      debugPrint('🚨 Signup error: $e');
      _error = 'Something went wrong during registration. Please try again.';
      _isLoading = false;
      _safeNotifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword(
      String username,
      String email,
      String securityAnswer1,
      String securityAnswer2,
      String newPassword) async {
    // ... existing reset password code ...
    return false;
  }

  bool verifyPassword(String inputPassword) {
    if (_user == null || _passwordHash == null) return false;
    final inputHash = _simpleHash(inputPassword);
    return inputHash == _passwordHash;
  }

  Future<void> logout() async {
    if (_isLoggingOut || _isDisposed) {
      debugPrint('🚪 Logout already in progress or disposed, skipping...');
      return;
    }

    _isLoggingOut = true;
    _sessionCheckTimer?.cancel();
    _sessionValid = false;
    if (_isDisposed) return;

    debugPrint('🚪 Logging out...');
    try {
      if (_isOnline) await _backendAuth.logout();
    } catch (e) {
      debugPrint('⚠️ Backend logout error: $e');
    } finally {
      _user = null;
      _passwordHash = null;
      _error = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_data');
      await prefs.remove('password_hash');
      await prefs.remove('auth_token');
      await prefs.remove('refresh_token');
      await prefs.remove('needs_sync_register');
      await prefs.remove('pending_registration');

      SupabaseService.clearContext();
      await SecureStorageService.clearSession();
      debugPrint('✅ Logged out successfully');
      _isLoggingOut = false;
      _safeNotifyListeners();
    }
  }

  Future<bool> checkAuth() async {
    await _loadUserFromStorage();
    if (_user != null) {
      _safeNotifyListeners();
      return true;
    }
    return false;
  }

  void clearError() {
    _error = null;
    _safeNotifyListeners();
  }
}
