// screens/lock_screen.dart
// COMPLETE FIXED VERSION

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:drinks_calculator_fixed/services/secure_storage_service.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';
import 'package:drinks_calculator_fixed/utils/helpers.dart';
import '../main.dart' as app; // ✅ Import for navigatorKey
import '../screens/auth_screen.dart'; // ✅ Import AuthScreen

class LockScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;
  final bool isBackgroundLock;
  final String? sessionTerminatedMessage;
  final String? previousDevice;
  final String? userId;

  const LockScreen({
    super.key,
    required this.onAuthenticated,
    this.isBackgroundLock = false,
    this.sessionTerminatedMessage,
    this.previousDevice,
    this.userId,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  // ========== BIOMETRIC ==========
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isAuthenticating = false;
  bool _canCheckBiometrics = false;
  bool _isBiometricSupported = false;
  bool _hasEnrolledBiometrics = false;
  String _biometricType = 'Biometric';

  // ========== PIN ==========
  bool _isPinMode = false;
  String _pinInput = '';
  String _savedPin = '';
  bool _isPinSetup = false;
  int _pinAttempts = 0;
  static const int _maxPinAttempts = 5;
  bool _isLocked = false;
  Timer? _lockTimer;
  bool _isAuthenticated = false;

  // ========== BIOMETRIC SETTINGS ==========
  bool _biometricEnabled = true;
  static const String _biometricEnabledKey = 'biometric_enabled';

  // ========== PIN SETUP ==========
  String _pinConfirm = '';
  String? _pinSetupError;

  // ============================================================
  // 🔐 LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeLockScreen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // 🔐 BIOMETRIC SUPPORT CHECK
  // ============================================================

  Future<void> _checkBiometricSupport() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final enrolled = await _localAuth.getAvailableBiometrics();

      String biometricType = 'Biometric';
      if (enrolled.contains(BiometricType.face)) {
        biometricType = 'Face ID';
      } else if (enrolled.contains(BiometricType.fingerprint)) {
        biometricType = 'Fingerprint';
      } else if (enrolled.contains(BiometricType.iris)) {
        biometricType = 'Iris Scan';
      }

      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_biometricEnabledKey) ?? true;

      setState(() {
        _isBiometricSupported = isSupported;
        _canCheckBiometrics = canCheck && isSupported && enrolled.isNotEmpty;
        _hasEnrolledBiometrics = enrolled.isNotEmpty;
        _biometricType = biometricType;
        _biometricEnabled = enabled;
      });

      debugPrint('🔐 Biometric Support:');
      debugPrint('   Supported: $_isBiometricSupported');
      debugPrint('   Can Check: $_canCheckBiometrics');
      debugPrint('   Enrolled: $_hasEnrolledBiometrics');
      debugPrint('   Type: $_biometricType');
      debugPrint('   Enabled: $_biometricEnabled');
    } catch (e) {
      debugPrint('❌ Biometric check error: $e');
      setState(() {
        _canCheckBiometrics = false;
        _isBiometricSupported = false;
        _hasEnrolledBiometrics = false;
      });
    }
  }

  // ============================================================
  // 🔐 BIOMETRIC AUTHENTICATION
  // ============================================================

  Future<void> _authenticateWithBiometric() async {
    if (_isAuthenticating || _isLocked || _isAuthenticated) return;

    if (!_biometricEnabled) {
      setState(() => _isPinMode = true);
      return;
    }

    if (!_canCheckBiometrics) {
      setState(() => _isPinMode = true);
      return;
    }

    setState(() => _isAuthenticating = true);

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: widget.isBackgroundLock
            ? 'Authenticate to return to the app'
            : 'Authenticate to access your business data',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );

      if (authenticated && mounted) {
        await _handleSuccessfulAuthentication();
      } else if (mounted) {
        setState(() {
          _isPinMode = true;
          _isAuthenticating = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Biometric authentication error: $e');

      if (e.toString().contains('locked out')) {
        setState(() {
          _isLocked = true;
          _isAuthenticating = false;
        });
        _startLockTimer();
      } else {
        setState(() {
          _isPinMode = true;
          _isAuthenticating = false;
        });
      }
    } finally {
      if (mounted && !_isAuthenticated) {
        setState(() => _isAuthenticating = false);
      }
    }
  }

  // ============================================================
  // 🔐 BIOMETRIC SETTINGS TOGGLE
  // ============================================================

  Future<void> _toggleBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _biometricEnabled = !_biometricEnabled;
    });
    await prefs.setBool(_biometricEnabledKey, _biometricEnabled);

    if (!_biometricEnabled) {
      setState(() => _isPinMode = true);
    } else {
      _authenticateWithBiometric();
    }
  }

  // ============================================================
  // 🔑 PIN METHODS
  // ============================================================

  Future<void> _loadSavedPin() async {
    String pin = '';

    if (widget.userId != null && widget.userId!.isNotEmpty) {
      pin = await SecureStorageService.readPin(userId: widget.userId!) ?? '';
    } else {
      pin = await SecureStorageService.readPin() ?? '';
    }

    setState(() {
      _savedPin = pin;
      _isPinSetup = pin.isNotEmpty;

      if (_savedPin.isEmpty && !widget.isBackgroundLock) {
        _isPinMode = true;
        _isPinSetup = false;
      }
    });
  }

  Future<void> _handlePinEntry(String value) async {
    if (_isAuthenticating || _isLocked || _isAuthenticated) return;

    if (value == 'delete') {
      setState(() {
        if (_pinInput.isNotEmpty) {
          _pinInput = _pinInput.substring(0, _pinInput.length - 1);
        }
      });
      return;
    }

    if (value.isEmpty) {
      return;
    }

    if (_pinInput.length < 6) {
      setState(() => _pinInput += value);

      if (_pinInput.length == 6) {
        await _verifyPin();
      }
    }
  }

  Future<void> _verifyPin() async {
    if (_isAuthenticating || _isLocked || _isAuthenticated) return;

    if (_pinInput == _savedPin) {
      await _handleSuccessfulAuthentication();
    } else {
      _pinAttempts++;
      final remaining = _maxPinAttempts - _pinAttempts;

      setState(() {
        _pinInput = '';
        if (_pinAttempts >= _maxPinAttempts) {
          _isLocked = true;
          _startLockTimer();
        }
      });

      if (_pinAttempts < _maxPinAttempts) {
        Helpers.showToast(
          'Invalid PIN. $remaining attempts remaining.',
          isError: true,
        );
      } else {
        Helpers.showToast('Too many attempts. Please wait 30 seconds.',
            isError: true);
      }
    }
  }

  void _startLockTimer() {
    _lockTimer?.cancel();
    _lockTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) {
        setState(() {
          _isLocked = false;
          _pinAttempts = 0;
        });
        Helpers.showToast('You can try again now.');

        if (_biometricEnabled && _canCheckBiometrics) {
          _authenticateWithBiometric();
        }
      }
    });
  }

  // ============================================================
  // 🎯 AUTHENTICATION HANDLING
  // ============================================================

  Future<void> _handleSuccessfulAuthentication() async {
    if (_isAuthenticated) return;

    setState(() => _isAuthenticating = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          'last_authenticated', DateTime.now().millisecondsSinceEpoch);

      _pinAttempts = 0;
      _isLocked = false;
      _lockTimer?.cancel();
      _isAuthenticated = true;

      LockService().unlock();
      widget.onAuthenticated();
    } catch (e) {
      debugPrint('❌ Authentication completion error: $e');
      setState(() => _isAuthenticated = false);
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  // ============================================================
  // 🔐 PIN SETUP
  // ============================================================

  Future<void> _handlePinSetup(String value) async {
    if (_isAuthenticating || _isLocked) return;

    if (value == 'delete') {
      setState(() {
        if (_pinInput.isNotEmpty) {
          _pinInput = _pinInput.substring(0, _pinInput.length - 1);
        }
        _pinSetupError = null;
      });
      return;
    }

    if (value.isEmpty) {
      return;
    }

    if (_pinInput.length < 6) {
      setState(() => _pinInput += value);

      if (_pinInput.length == 6) {
        if (_pinConfirm.isEmpty) {
          setState(() {
            _pinConfirm = _pinInput;
            _pinInput = '';
          });
        } else {
          if (_pinInput == _pinConfirm) {
            await _savePin(_pinInput);
          } else {
            setState(() {
              _pinSetupError = 'PINs do not match. Please try again.';
              _pinInput = '';
              _pinConfirm = '';
            });
          }
        }
      }
    }
  }

  Future<void> _savePin(String pin) async {
    try {
      if (widget.userId != null && widget.userId!.isNotEmpty) {
        await SecureStorageService.savePin(pin, userId: widget.userId!);
      } else {
        await SecureStorageService.savePin(pin);
      }

      setState(() {
        _savedPin = pin;
        _isPinSetup = true;
        _isPinMode = true;
        _pinInput = '';
        _pinConfirm = '';
        _pinSetupError = null;
        _pinAttempts = 0;
      });

      await _handleSuccessfulAuthentication();
    } catch (e) {
      setState(() {
        _pinSetupError = 'Failed to save PIN. Please try again.';
      });
      debugPrint('❌ PIN save error: $e');
    }
  }

  // ============================================================
  // ✅✅✅ FIXED: SESSION TERMINATED DIALOG
  // ============================================================

  void _showSessionTerminatedDialog() {
    // The lock screen is rendered as a top-level overlay (sibling of the
    // Navigator), so its own context has no Navigator ancestor. Always show
    // the dialog from the root navigator context.
    final navigatorContext = app.navigatorKey.currentContext;
    if (!mounted || navigatorContext == null) return;

    debugPrint('🔴🔴🔴 SHOWING SESSION TERMINATED DIALOG 🔴🔴🔴');
    debugPrint('   Previous Device: ${widget.previousDevice}');
    debugPrint('   Message: ${widget.sessionTerminatedMessage}');

    showDialog(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orange, size: 28),
            const SizedBox(width: 10),
            const Text('Session Terminated'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phonelink_erase, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              widget.sessionTerminatedMessage ??
                  'Your account is now active on another device.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            if (widget.previousDevice != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      '📱 Previous Device:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.previousDevice!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'You will be redirected to the login screen.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                debugPrint('🔴 User clicked "Login Again"');

                // ✅ 1. Clear the session
                await SecureStorageService.clearSession();

                // ✅ 2. Pop the dialog
                if (mounted) {
                  Navigator.of(dialogContext).pop();
                }

                // ✅ 3. Navigate to AuthScreen and remove all routes
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final navContext = app.navigatorKey.currentContext;
                  if (navContext != null && navContext.mounted) {
                    // ✅ Use pushAndRemoveUntil to clear the entire stack
                    Navigator.of(navContext).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const AuthScreen(),
                      ),
                      (route) => false, // ✅ Remove all previous routes
                    );
                  } else {
                    // ✅ Fallback: Use the dialog context
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => const AuthScreen(),
                        ),
                        (route) => false,
                      );
                    }
                  }
                });

                // ✅ 4. Call onAuthenticated to unlock the lock screen
                widget.onAuthenticated();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.login, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Login Again',
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

  // ============================================================
  // 🏗️ RESPONSIVE UI BUILDERS
  // ============================================================

  // ✅ Responsive Sizing Helper
  double _getResponsiveSize(BuildContext context,
      {required double mobile, double? tablet, double? desktop}) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return mobile;
    if (width < 1200) return tablet ?? mobile * 1.2;
    return desktop ?? mobile * 1.4;
  }

  Widget _buildBiometricPrompt(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.all(isMobile ? 20 : 28),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _biometricType == 'Face ID'
                      ? Icons.face_retouching_natural
                      : Icons.fingerprint,
                  size: isMobile ? 48 : 64,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Use $_biometricType',
                style: TextStyle(
                  fontSize: isMobile ? 18 : 24,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isAuthenticating
                    ? 'Authenticating...'
                    : isMobile
                        ? 'Touch the sensor to authenticate'
                        : 'Touch the sensor or look at your device to authenticate',
                style: TextStyle(
                  fontSize: isMobile ? 14 : 16,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              if (_isAuthenticating)
                Padding(
                  padding: EdgeInsets.all(isMobile ? 16 : 24),
                  child: SizedBox(
                    width: isMobile ? 24 : 32,
                    height: isMobile ? 24 : 32,
                    child: const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isAuthenticating
                    ? null
                    : () {
                        setState(() => _isPinMode = true);
                      },
                child: Text(
                  'Use PIN instead',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: isMobile ? 14 : 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPinDisplay(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;
    final dotSize = isMobile ? 16.0 : 20.0;
    final containerSize = isMobile ? 40.0 : 50.0;
    final spacing = isMobile ? 8.0 : 12.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        final isFilled = index < _pinInput.length;
        return Container(
          margin: EdgeInsets.symmetric(horizontal: spacing),
          width: containerSize,
          height: containerSize,
          decoration: BoxDecoration(
            color:
                isFilled ? Colors.white : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
            border: Border.all(
              color:
                  isFilled ? Colors.white : Colors.white.withValues(alpha: 0.3),
              width: isMobile ? 2 : 3,
            ),
          ),
          child: Center(
            child: isFilled
                ? Container(
                    width: dotSize,
                    height: dotSize,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
          ),
        );
      }),
    );
  }

  Widget _buildPinPad(BuildContext context) {
    final isDisabled = _isLocked || _isAuthenticating || _isAuthenticated;
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;
    final buttonSize = isMobile ? 64.0 : 76.0;
    final fontSize = isMobile ? 24.0 : 28.0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPinButton(context, '1', isDisabled, buttonSize, fontSize),
            _buildPinButton(context, '2', isDisabled, buttonSize, fontSize),
            _buildPinButton(context, '3', isDisabled, buttonSize, fontSize),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPinButton(context, '4', isDisabled, buttonSize, fontSize),
            _buildPinButton(context, '5', isDisabled, buttonSize, fontSize),
            _buildPinButton(context, '6', isDisabled, buttonSize, fontSize),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPinButton(context, '7', isDisabled, buttonSize, fontSize),
            _buildPinButton(context, '8', isDisabled, buttonSize, fontSize),
            _buildPinButton(context, '9', isDisabled, buttonSize, fontSize),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: buttonSize, height: buttonSize),
            _buildPinButton(context, '0', isDisabled, buttonSize, fontSize),
            _buildPinButton(
                context, 'delete', isDisabled, buttonSize, fontSize),
          ],
        ),
      ],
    );
  }

  Widget _buildPinButton(
    BuildContext context,
    String value,
    bool isDisabled,
    double buttonSize,
    double fontSize,
  ) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (value.isEmpty) {
      return SizedBox(width: buttonSize, height: buttonSize);
    }

    final bool isDelete = value == 'delete';

    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: InkWell(
        onTap: isDisabled
            ? null
            : () {
                if (!_isPinSetup) {
                  _handlePinSetup(value);
                } else {
                  _handlePinEntry(value);
                }
              },
        borderRadius: BorderRadius.circular(buttonSize / 2),
        child: Center(
          child: isDelete
              ? Icon(
                  Icons.backspace,
                  color: isDisabled ? Colors.white38 : Colors.white,
                  size: isMobile ? 24 : 30,
                )
              : Text(
                  value,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: isDisabled ? Colors.white38 : Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildLockedMessage(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, color: Colors.red, size: 24),
          SizedBox(width: isMobile ? 12 : 16),
          Text(
            'Locked for 30 seconds',
            style: TextStyle(
              color: Colors.white,
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricToggle(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Use $_biometricType',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: isMobile ? 14 : 16,
          ),
        ),
        SizedBox(width: isMobile ? 12 : 16),
        Switch(
          value: _biometricEnabled,
          onChanged:
              _isAuthenticating ? null : (_) => _toggleBiometricEnabled(),
          activeColor: Colors.white,
          activeThumbColor: Colors.white,
          inactiveThumbColor: Colors.grey,
        ),
      ],
    );
  }

  // ============================================================
  // 🏗️ MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;
    final isTablet = width >= 600 && width < 1200;

    final padding = isMobile
        ? 24.0
        : isTablet
            ? 32.0
            : 48.0;
    final iconSize = isMobile
        ? 60.0
        : isTablet
            ? 80.0
            : 100.0;
    final titleSize = isMobile
        ? 28.0
        : isTablet
            ? 36.0
            : 42.0;
    final subtitleSize = isMobile
        ? 16.0
        : isTablet
            ? 20.0
            : 22.0;

    if (_isAuthenticated) {
      return const SizedBox.shrink();
    }

    debugPrint(
        '🔐 Build - isPinSetup: $_isPinSetup, isPinMode: $_isPinMode, savedPin: ${_savedPin.isNotEmpty ? "YES" : "NO"}');

    final bool isSetupMode = !_isPinSetup && _savedPin.isEmpty;
    final bool showBiometric = _canCheckBiometrics &&
        _biometricEnabled &&
        !_isPinMode &&
        !isSetupMode &&
        !_isLocked;

    final bool shouldShowSetup =
        _savedPin.isEmpty && !_isPinSetup && !isSetupMode;
    if (shouldShowSetup) {
      debugPrint('🔐 Forcing PIN setup mode');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isPinSetup = false;
            _isPinMode = true;
          });
        }
      });
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [primaryColor, primaryColor.withValues(alpha: 0.7)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.all(padding),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isMobile
                      ? 400
                      : isTablet
                          ? 600
                          : 800,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ========== ICON ==========
                    Container(
                      padding: EdgeInsets.all(iconSize * 0.5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSetupMode || _savedPin.isEmpty
                            ? Icons.pin
                            : (_isLocked
                                ? Icons.lock_outline
                                : (showBiometric
                                    ? (_biometricType == 'Face ID'
                                        ? Icons.face_retouching_natural
                                        : Icons.fingerprint)
                                    : Icons.pin)),
                        size: iconSize,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: isMobile ? 24 : 32),

                    // ========== TITLE ==========
                    Text(
                      isSetupMode || _savedPin.isEmpty
                          ? 'Set Up Your PIN'
                          : _isLocked
                              ? 'Device Locked'
                              : widget.isBackgroundLock
                                  ? 'Welcome Back'
                                  : 'Secure Access',
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isMobile ? 8 : 12),

                    // ========== SUBTITLE ==========
                    Text(
                      isSetupMode || _savedPin.isEmpty
                          ? 'Create a 6-digit PIN for your account'
                          : _isLocked
                              ? 'Too many attempts. Please wait 30 seconds.'
                              : _isAuthenticating
                                  ? 'Authenticating...'
                                  : (showBiometric
                                      ? 'Use ${_biometricType} to unlock'
                                      : 'Enter your PIN'),
                      style: TextStyle(
                        fontSize: subtitleSize,
                        color: _isLocked ? Colors.red.shade300 : Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isMobile ? 32 : 40),

                    // ========== LOADING / LOCKED ==========
                    if (_isAuthenticating && !showBiometric)
                      SizedBox(
                        width: isMobile ? 32 : 40,
                        height: isMobile ? 32 : 40,
                        child: const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      ),

                    if (_isLocked && !_isAuthenticating)
                      _buildLockedMessage(context),

                    // ========== BIOMETRIC PROMPT ==========
                    if (showBiometric && !_isLocked)
                      _buildBiometricPrompt(context),

                    // ========== PIN SETUP ==========
                    if ((isSetupMode || _savedPin.isEmpty) &&
                        !_isAuthenticating) ...[
                      if (_pinSetupError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _pinSetupError!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      Text(
                        _pinConfirm.isNotEmpty
                            ? 'Confirm your PIN'
                            : 'Enter new 6-digit PIN',
                        style: TextStyle(
                          fontSize: isMobile ? 16 : 18,
                          color: Colors.white70,
                        ),
                      ),
                      SizedBox(height: isMobile ? 16 : 24),
                      _buildPinDisplay(context),
                      SizedBox(height: isMobile ? 24 : 32),
                      _buildPinPad(context),
                      SizedBox(height: isMobile ? 8 : 12),
                      TextButton(
                        // ✅ Skip = unlock WITHOUT a PIN. Previously this only
                        // flipped _isPinSetup while _savedPin stayed empty,
                        // which rendered NO actionable UI and left the user
                        // stranded on a dead lock screen. Now it completes
                        // authentication (LockService().unlock + onAuthenticated)
                        // so the user gets in; they can set a PIN later.
                        onPressed: _isAuthenticating
                            ? null
                            : () => _handleSuccessfulAuthentication(),
                        child: Text(
                          'Skip PIN Setup',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: isMobile ? 14 : 16,
                          ),
                        ),
                      ),
                    ],

                    // ========== PIN ENTRY ==========
                    if (_isPinMode &&
                        !_isAuthenticating &&
                        !_isLocked &&
                        _isPinSetup &&
                        _savedPin.isNotEmpty) ...[
                      _buildPinDisplay(context),
                      SizedBox(height: isMobile ? 24 : 32),
                      _buildPinPad(context),
                    ],

                    SizedBox(height: isMobile ? 32 : 40),

                    // ========== BIOMETRIC TOGGLE ==========
                    if (_canCheckBiometrics &&
                        _isPinSetup &&
                        !_isLocked &&
                        !isSetupMode &&
                        !_isAuthenticating &&
                        _savedPin.isNotEmpty)
                      _buildBiometricToggle(context),

                    // ========== SWITCH TO BIOMETRIC ==========
                    if (_isPinMode &&
                        _canCheckBiometrics &&
                        _biometricEnabled &&
                        !_isAuthenticating &&
                        !_isLocked &&
                        _savedPin.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isPinMode = false;
                            _pinInput = '';
                            _authenticateWithBiometric();
                          });
                        },
                        child: Text(
                          'Use $_biometricType instead',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: isMobile ? 14 : 16,
                          ),
                        ),
                      ),

                    // ========== VERSION ==========
                    SizedBox(height: isMobile ? 16 : 24),
                    Text(
                      'Version 1.0.0',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: isMobile ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 🚀 INITIALIZATION
  // ============================================================

  Future<void> _initializeLockScreen() async {
    debugPrint('🔐 Initializing lock screen...');

    await _checkBiometricSupport();
    await _loadSavedPin();

    debugPrint('🔐 Biometric Support: $_canCheckBiometrics');
    debugPrint('🔐 PIN Setup: $_isPinSetup');
    debugPrint('🔐 PIN Mode: $_isPinMode');
    debugPrint('🔐 Saved PIN: ${_savedPin.isNotEmpty ? "YES" : "NO"}');

    if (widget.sessionTerminatedMessage != null) {
      debugPrint('🔐 Session terminated - showing dialog');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showSessionTerminatedDialog();
        }
      });
      return;
    }

    if (!_canCheckBiometrics || !_biometricEnabled) {
      debugPrint('🔐 No biometrics - forcing PIN mode');
      setState(() {
        _isPinMode = true;
        if (_savedPin.isEmpty) {
          _isPinSetup = false;
        } else {
          _isPinSetup = true;
        }
      });
      return;
    }

    if (_canCheckBiometrics &&
        _biometricEnabled &&
        !widget.isBackgroundLock &&
        !_isLocked) {
      debugPrint('🔐 Attempting biometric authentication...');
      _authenticateWithBiometric();
    } else {
      debugPrint('🔐 Falling back to PIN mode');
      setState(() {
        _isPinMode = true;
        if (_savedPin.isEmpty) {
          _isPinSetup = false;
        } else {
          _isPinSetup = true;
        }
      });
    }
  }
}
