// screens/auth_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:drinks_calculator_fixed/providers/auth_provider.dart';
import 'package:drinks_calculator_fixed/config/api_config.dart';
import 'calculator_screen.dart';
import 'dart:async';

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();

  bool _showLoginPassword = false;
  bool _showSignupPassword = false;
  bool _showSignupConfirmPassword = false;

  bool _isLoggingIn = false;
  bool _isSigningUp = false;
  bool _isSendingCode = false;
  bool _isVerifyingCode = false;
  bool _isResettingPassword = false;
  bool _isResettingWithSecurity = false;
  bool _registerAsManager = false;

  bool _isCheckingConnectivity = false;
  bool _hasInternetConnection = true;
  StreamSubscription? _connectivitySubscription;

  bool _codeSent = false;
  bool _codeVerified = false;
  bool _useEmailCode = true;
  final _phoneController = TextEditingController();
  // phone number
  String _selectedCountry = 'CM';
  String _selectedCountryCode = '+237';
  final List<Map<String, String>> _countries = [
    {
      'code': 'CM',
      'name': 'Cameroon',
      'dial': '+237',
      'flag': '🇨🇲',
      'format': '6XX XXX XXX'
    },
    {
      'code': 'NG',
      'name': 'Nigeria',
      'dial': '+234',
      'flag': '🇳🇬',
      'format': 'XXX XXX XXXX'
    },
  ];
  final _inviteCodeController = TextEditingController();
  final _newCompanyNameController = TextEditingController();
  final _newCompanyCodeController = TextEditingController();
  final _newCompanyAddressController = TextEditingController();
  String? _verifiedCompanyId;

  String? _verifiedCompanyName;
  bool _createNewCompany = false;
  bool _isVerifyingCode2 = false;
  final _loginUsernameController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  final _signupUsernameController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _securityAnswer1Controller = TextEditingController();
  final _securityAnswer2Controller = TextEditingController();

  final _forgotEmailController = TextEditingController();
  final _resetCodeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmNewPasswordController = TextEditingController();

  final _forgotUsernameController = TextEditingController();
  final _forgotSecurity1Controller = TextEditingController();
  final _forgotSecurity2Controller = TextEditingController();

  AuthMode _authMode = AuthMode.login;
  String _passwordStrength = '';

  @override
  void initState() {
    super.initState();
    _checkConnectivity();

    _startListeningToConnectivity();
  }

  void _startListeningToConnectivity() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      final hasConnection = result != ConnectivityResult.none;

      if (mounted && hasConnection != _hasInternetConnection) {
        setState(() {
          _hasInternetConnection = hasConnection;
          _isCheckingConnectivity = false;
        });

        // Auto-retry login/signup if user was waiting
        if (hasConnection) {
          // If user was trying to login
          if (_isLoggingIn) {
            _handleLogin();
          }
          // If user was trying to signup
          if (_isSigningUp) {
            _handleSignup();
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _loginUsernameController.dispose();
    _loginPasswordController.dispose();
    _connectivitySubscription?.cancel();
    _signupUsernameController.dispose();
    _signupEmailController.dispose();
    _signupPasswordController.dispose();
    _confirmPasswordController.dispose();
    _securityAnswer1Controller.dispose();
    _securityAnswer2Controller.dispose();
    _forgotEmailController.dispose();
    _resetCodeController.dispose();
    _newPasswordController.dispose();
    _confirmNewPasswordController.dispose();
    _forgotUsernameController.dispose();
    _forgotSecurity1Controller.dispose();
    _forgotSecurity2Controller.dispose();
    _phoneController.dispose();
    _inviteCodeController.dispose();
    _newCompanyNameController.dispose();
    _newCompanyCodeController.dispose();
    _newCompanyAddressController.dispose();
    super.dispose();
  }

  String _formatPhoneNumber(String phone, String countryCode) {
    if (phone.isEmpty) return '';
    String digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    final dialCode = _selectedCountryCode.replaceAll('+', '');
    if (digits.startsWith(dialCode)) {
      digits = digits.substring(dialCode.length);
    }
    switch (countryCode) {
      case 'CM':
        if (digits.length >= 9)
          return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6, 9)}';
        if (digits.length >= 6)
          return '${digits.substring(0, 3)} ${digits.substring(3)}';
        if (digits.length >= 3) return digits.substring(0, 3);
        break;
      case 'NG':
        if (digits.length >= 10)
          return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
        if (digits.length >= 6)
          return '${digits.substring(0, 3)} ${digits.substring(3)}';
        if (digits.length >= 3) return digits.substring(0, 3);
        break;
      case 'US':
        if (digits.length >= 10)
          return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
        if (digits.length >= 6)
          return '${digits.substring(0, 3)}-${digits.substring(3)}';
        if (digits.length >= 3) return digits.substring(0, 3);
        break;
      default:
        final buffer = StringBuffer();
        for (int i = 0; i < digits.length; i++) {
          if (i > 0 && i % 3 == 0) buffer.write(' ');
          buffer.write(digits[i]);
        }
        return buffer.toString();
    }
    return digits;
  }

  Future<void> _checkConnectivity() async {
    setState(() => _isCheckingConnectivity = true);
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      setState(() => _hasInternetConnection =
          connectivityResult != ConnectivityResult.none);
    } catch (e) {
      setState(() => _hasInternetConnection = false);
    }
    setState(() => _isCheckingConnectivity = false);
  }

  void _checkPasswordStrength(String password) {
    int strength = 0;
    if (password.length >= 6) strength++;
    if (password.contains(RegExp(r'[a-z]')) &&
        password.contains(RegExp(r'[A-Z]'))) strength++;
    if (password.contains(RegExp(r'\d'))) strength++;
    if (password.contains(RegExp(r'[^a-zA-Z\d]'))) strength++;
    setState(() {
      if (password.isEmpty)
        _passwordStrength = '';
      else if (strength <= 1)
        _passwordStrength = 'Weak password';
      else if (strength <= 3)
        _passwordStrength = 'Medium strength password';
      else
        _passwordStrength = 'Strong password';
    });
  }

  void _switchAuthMode(AuthMode mode) {
    setState(() {
      _authMode = mode;
      _passwordStrength = '';
      _codeSent = false;
      _codeVerified = false;
      _useEmailCode = true;
      _isLoggingIn = false;
      _isSigningUp = false;
      _isSendingCode = false;
      _isVerifyingCode = false;
      _isResettingPassword = false;
      _isResettingWithSecurity = false;

      // Clear ALL fields
      _loginUsernameController.clear();
      _loginPasswordController.clear();
      _signupUsernameController.clear();
      _signupEmailController.clear();
      _signupPasswordController.clear();
      _confirmPasswordController.clear();
      _securityAnswer1Controller.clear();
      _securityAnswer2Controller.clear();
      _forgotEmailController.clear();
      _resetCodeController.clear();
      _newPasswordController.clear();
      _confirmNewPasswordController.clear();
      _forgotUsernameController.clear();
      _forgotSecurity1Controller.clear();
      _forgotSecurity2Controller.clear();
      _phoneController.clear();
      _inviteCodeController.clear();
      _newCompanyNameController.clear();
      _newCompanyCodeController.clear();
      _newCompanyAddressController.clear();

      // Reset manager signup options
      _registerAsManager = false;
      _createNewCompany = false;
      _verifiedCompanyId = null;
      _verifiedCompanyName = null;
    });
  }

  // ========== EMAIL CODE PASSWORD RESET ==========
  Future<void> _sendResetCode() async {
    if (_forgotEmailController.text.isEmpty) {
      _showErrorDialog('Error', 'Enter your email', Icons.error, Colors.red);
      return;
    }
    setState(() => _isSendingCode = true);
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/auth/send-reset-code'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'email': _forgotEmailController.text.trim()}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        setState(() => _codeSent = true);
        _showSuccessDialog(
            'Code Sent!',
            'Check your email for the 6-digit code.\n\nIf you don\'t see it, check spam or try again.',
            Icons.email,
            Colors.green,
            () {});
      } else {
        final data = json.decode(response.body);
        _showErrorDialog(
            'Server Error',
            data['message'] ?? 'Failed to send code. Try again.',
            Icons.error,
            Colors.red);
      }
    } on http.ClientException catch (e) {
      _showErrorDialog(
          'Network Error',
          'Cannot reach server. Check your internet connection and try again.',
          Icons.wifi_off,
          Colors.orange);
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        _showErrorDialog(
            'Connection Slow',
            'Server taking too long. Try again in a moment.',
            Icons.hourglass_empty,
            Colors.orange);
      } else {
        _showErrorDialog('Error', 'Something went wrong. Try again.',
            Icons.error, Colors.red);
      }
    }
    setState(() => _isSendingCode = false);
  }

  Future<void> _verifyResetCode() async {
    if (_resetCodeController.text.isEmpty) {
      _showErrorDialog(
          'Error', 'Enter the 6-digit code', Icons.error, Colors.red);
      return;
    }
    setState(() => _isVerifyingCode = true);
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/auth/verify-reset-code'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'email': _forgotEmailController.text.trim(),
              'code': _resetCodeController.text.trim()
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        setState(() => _codeVerified = true);
      } else {
        final data = json.decode(response.body);
        _showErrorDialog(
            'Invalid Code',
            data['message'] ?? 'The code is incorrect or expired.',
            Icons.error,
            Colors.red);
      }
    } on http.ClientException catch (e) {
      _showErrorDialog(
          'Network Error',
          'Cannot reach server. Check your connection.',
          Icons.wifi_off,
          Colors.orange);
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        _showErrorDialog(
            'Connection Slow',
            'Server taking too long. Try again.',
            Icons.hourglass_empty,
            Colors.orange);
      } else {
        _showErrorDialog('Error', 'Something went wrong. Try again.',
            Icons.error, Colors.red);
      }
    }
    setState(() => _isVerifyingCode = false);
  }

  Future<void> _resetPasswordWithCode() async {
    if (_newPasswordController.text != _confirmNewPasswordController.text) {
      _showErrorDialog(
          'Error', 'Passwords do not match', Icons.error, Colors.red);
      return;
    }
    if (_newPasswordController.text.length < 6) {
      _showErrorDialog('Error', 'Password must be at least 6 characters',
          Icons.error, Colors.red);
      return;
    }
    setState(() => _isResettingPassword = true);
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/auth/reset-password-code'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'email': _forgotEmailController.text.trim(),
              'code': _resetCodeController.text.trim(),
              'newPassword': _newPasswordController.text,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        _showSuccessDialog(
            'Success!',
            'Password reset! Please login with your new password.',
            Icons.check_circle,
            Colors.green,
            () => _switchAuthMode(AuthMode.login));
      } else {
        final data = json.decode(response.body);
        _showErrorDialog(
            'Error',
            data['message'] ?? 'Failed to reset password.',
            Icons.error,
            Colors.red);
      }
    } on http.ClientException catch (e) {
      _showErrorDialog(
          'Network Error',
          'Cannot reach server. Check your connection.',
          Icons.wifi_off,
          Colors.orange);
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        _showErrorDialog(
            'Connection Slow',
            'Server taking too long. Try again.',
            Icons.hourglass_empty,
            Colors.orange);
      } else {
        _showErrorDialog('Error', 'Something went wrong. Try again.',
            Icons.error, Colors.red);
      }
    }
    setState(() => _isResettingPassword = false);
  }

  // ========== SECURITY QUESTIONS PASSWORD RESET ==========
  Future<void> _resetPasswordWithSecurity() async {
    if (_forgotUsernameController.text.isEmpty ||
        _forgotEmailController.text.isEmpty) {
      _showErrorDialog('Error', 'Fill all fields', Icons.error, Colors.red);
      return;
    }
    if (_newPasswordController.text != _confirmNewPasswordController.text) {
      _showErrorDialog(
          'Error', 'Passwords do not match', Icons.error, Colors.red);
      return;
    }
    if (_newPasswordController.text.length < 6) {
      _showErrorDialog('Error', 'Password must be at least 6 characters',
          Icons.error, Colors.red);
      return;
    }
    setState(() => _isResettingWithSecurity = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.resetPassword(
        _forgotUsernameController.text.trim(),
        _forgotEmailController.text.trim(),
        _forgotSecurity1Controller.text.trim(),
        _forgotSecurity2Controller.text.trim(),
        _newPasswordController.text,
      );
      if (mounted) setState(() => _isResettingWithSecurity = false);
      if (success) {
        _showSuccessDialog(
            'Password Reset',
            'Password reset! You can now login.',
            Icons.lock_open,
            Colors.green, () {
          _switchAuthMode(AuthMode.login);
          _loginUsernameController.text = _forgotUsernameController.text;
        });
      } else {
        _showErrorDialog(
            'Reset Failed',
            'Security answers incorrect or user not found',
            Icons.security,
            Colors.red);
      }
    } catch (e) {
      if (mounted) setState(() => _isResettingWithSecurity = false);
      _showErrorDialog(
          'Error', 'An error occurred', Icons.error, Colors.orange);
    }
  }

  // ========== LOGIN / SIGNUP ==========
  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    await _checkConnectivity();
    if (!_hasInternetConnection) {
      _showNoInternetDialog();
      return;
    }
    setState(() => _isLoggingIn = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.login(
          _loginUsernameController.text.trim(), _loginPasswordController.text);
      if (mounted) setState(() => _isLoggingIn = false);
      if (success) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const CalculatorScreen()),
          );
        }
      } else {
        final errorMsg = authProvider.error ?? 'Invalid username or password';

        if (mounted) {
          // ✅ Handle email verification error from provider
          if (errorMsg.startsWith('EMAIL_NOT_VERIFIED|')) {
            final message = errorMsg.replaceFirst('EMAIL_NOT_VERIFIED|', '');
            _showVerificationRequiredDialog(message);
          } else if (errorMsg.contains('verify') ||
              errorMsg.contains('Verify')) {
            _showVerificationRequiredDialog(errorMsg);
          } else {
            _showErrorDialog(
                'Login Failed', errorMsg, Icons.error_outline, Colors.red);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoggingIn = false);
        if (e.toString().contains('SocketException') ||
            e.toString().contains('Connection refused')) {
          _showErrorDialog(
              'No Internet',
              'Please check your connection and try again.',
              Icons.wifi_off,
              Colors.orange);
        } else if (e.toString().contains('Timeout')) {
          _showErrorDialog(
              'Connection Slow',
              'Server taking too long. Try again.',
              Icons.hourglass_empty,
              Colors.orange);
        } else {
          _showErrorDialog('Error', 'Something went wrong. Try again.',
              Icons.error, Colors.red);
        }
      }
    }
  }

  Future<void> _handleSignup() async {
    if (!_signupFormKey.currentState!.validate()) return;
    if (_signupPasswordController.text != _confirmPasswordController.text) {
      _showErrorDialog(
          'Error', 'Passwords do not match', Icons.error_outline, Colors.red);
      return;
    }
    await _checkConnectivity();
    if (!_hasInternetConnection) {
      _showNoInternetDialog();
      return;
    }
    setState(() => _isSigningUp = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.signup(
        _signupUsernameController.text.trim(),
        _signupEmailController.text.trim(),
        _signupPasswordController.text,
        _securityAnswer1Controller.text.trim(),
        _securityAnswer2Controller.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : '$_selectedCountryCode${_phoneController.text.replaceAll(RegExp(r'[^\d]'), '')}',
        registerAsManager: _registerAsManager,
        companyId: _verifiedCompanyId,
        companyName: _newCompanyNameController.text.trim().isEmpty
            ? null
            : _newCompanyNameController.text.trim(),
        companyCode: _newCompanyCodeController.text.trim().isEmpty
            ? null
            : _newCompanyCodeController.text.trim(),
        companyAddress: _newCompanyAddressController.text.trim().isEmpty
            ? null
            : _newCompanyAddressController.text.trim(),
      );
      if (mounted) setState(() => _isSigningUp = false);
      if (success) {
        if (mounted) {
          _showSuccessDialog(
              'Verify Your Email',
              'Account created! We have sent a verification email to ${_signupEmailController.text.trim()}.\n\nPlease check your inbox and click the verify button to activate your account.',
              Icons.mark_email_read,
              Colors.blue, () {
            _switchAuthMode(AuthMode.login);
            _loginUsernameController.text = _signupUsernameController.text;
          });
        }
      } else {
        if (mounted) {
          final errorMsg =
              authProvider.error ?? 'Registration failed. Please try again.';
          _showErrorDialog(
              'Signup Failed', errorMsg, Icons.person_off, Colors.red);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSigningUp = false);
        _showErrorDialog(
            'Error', 'An error occurred', Icons.error, Colors.orange);
      }
    }
  }

// ========== VERIFICATION REQUIRED DIALOG ==========
  void _showVerificationRequiredDialog(String message) {
    final email = _loginUsernameController.text.trim();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.mark_email_unread, color: Colors.orange, size: 28),
            const SizedBox(width: 10),
            const Text('Email Not Verified'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.email, size: 60, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Text(
                    'Check your inbox for the verification email.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '📧 $email',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Don\'t see it? Check spam or request a new one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _resendVerificationEmail(email);
            },
            icon: const Icon(Icons.email, size: 18),
            label: const Text('Resend Email'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

// ========== RESEND VERIFICATION EMAIL ==========
  Future<void> _resendVerificationEmail(String email) async {
    setState(() => _isSendingCode = true);

    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/auth/resend-verification'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'email': email}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _showSuccessDialog(
          '✅ Email Sent!',
          data['message'] ?? 'Verification email resent to $email',
          Icons.email,
          Colors.green,
          () {},
        );
      } else {
        final data = json.decode(response.body);
        _showErrorDialog(
          'Failed',
          data['message'] ?? 'Could not resend verification email.',
          Icons.error,
          Colors.red,
        );
      }
    } catch (e) {
      if (e is http.ClientException) {
        _showErrorDialog(
          'Network Error',
          'Cannot reach server. Check your connection.',
          Icons.wifi_off,
          Colors.orange,
        );
      } else if (e.toString().contains('Timeout')) {
        _showErrorDialog(
          'Connection Slow',
          'Server taking too long. Try again.',
          Icons.hourglass_empty,
          Colors.orange,
        );
      } else {
        _showErrorDialog(
          'Error',
          'Something went wrong. Try again.',
          Icons.error,
          Colors.red,
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  // ========== DIALOGS ==========
  void _showNoInternetDialog() {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              icon: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.wifi_off,
                      size: 36, color: Colors.orange)),
              title: const Text('No Internet Connection',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.orange)),
              content: const Text(
                  'Please check your internet connection and try again.',
                  textAlign: TextAlign.center),
              actions: [
                ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _checkConnectivity();
                    },
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange)),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
              ],
            ));
  }

  void _showErrorDialog(
      String title, String message, IconData icon, Color color) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              icon: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(icon, size: 36, color: color)),
              title: Text(title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              content: Text(message, textAlign: TextAlign.center),
              actions: [
                ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(backgroundColor: color),
                    child: const Text('OK'))
              ],
            ));
  }

  void _showSuccessDialog(String title, String message, IconData icon,
      Color color, VoidCallback onOk) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              icon: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(icon, size: 36, color: color)),
              title: Text(title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              content: Text(message, textAlign: TextAlign.center),
              actions: [
                ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onOk();
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: color),
                    child: const Text('OK'))
              ],
            ));
  }

  // ========== BUILD ==========
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)])),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const SizedBox(height: 20),
                Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                        color: Colors.white.withAlpha(25),
                        borderRadius: BorderRadius.circular(25),
                        image: const DecorationImage(
                            image: AssetImage('assets/icons/icon.png'),
                            fit: BoxFit.contain))),
                const SizedBox(height: 10),
                const Text('Drinks Quick Cal',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const Text('Professional Drink Ordering & Management',
                    style: TextStyle(fontSize: 16, color: Colors.white70)),
                _buildConnectionStatus(),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Expanded(child: _buildAuthTab('Login', AuthMode.login)),
                    Expanded(child: _buildAuthTab('Sign Up', AuthMode.signup)),
                  ]),
                ),
                const SizedBox(height: 20),
                Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: _buildAuthForm())),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    if (_isCheckingConnectivity) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 8),
          Text('Checking...',
              style: TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );
    }

    if (!_hasInternetConnection) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off, size: 16, color: Colors.white),
          SizedBox(width: 8),
          Text('No Internet',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ]),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildAuthTab(String text, AuthMode mode) => GestureDetector(
        onTap:
            (_isLoggingIn || _isSigningUp) ? null : () => _switchAuthMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _authMode == mode
                ? const Color(0xFF667EEA)
                : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _authMode == mode
                    ? Colors.white
                    : (_isLoggingIn || _isSigningUp)
                        ? Colors.grey
                        : const Color(0xFF7F8C8D),
              ),
            ),
          ),
        ),
      );

  Widget _buildAuthForm() {
    switch (_authMode) {
      case AuthMode.login:
        return Stack(
          children: [
            _buildLoginForm(),
            if (_isLoggingIn) _buildLoadingOverlay(),
          ],
        );
      case AuthMode.signup:
        return Stack(
          children: [
            _buildSignupForm(),
            if (_isSigningUp) _buildLoadingOverlay(),
          ],
        );
      case AuthMode.forgot:
        return _buildForgotForm();
    }
  }

  Widget _buildLoadingOverlay() {
    return IgnorePointer(
      ignoring: true, // ✅ Blocks all taps
      child: Container(
        color: Colors.black.withOpacity(0.3),
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Please wait...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
        key: _loginFormKey,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!_hasInternetConnection) ...[
            _buildOfflineWarning(),
            const SizedBox(height: 16)
          ],
          TextFormField(
              enabled: !_isLoggingIn,
              controller: _loginUsernameController,
              decoration: const InputDecoration(
                  labelText: 'Username', prefixIcon: Icon(Icons.person)),
              validator: (v) =>
                  v?.isEmpty == true ? 'Please enter username' : null),
          const SizedBox(height: 16),
          TextFormField(
              enabled: !_isLoggingIn,
              controller: _loginPasswordController,
              obscureText: !_showLoginPassword,
              decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                      icon: Icon(_showLoginPassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () => setState(
                          () => _showLoginPassword = !_showLoginPassword))),
              validator: (v) =>
                  v?.isEmpty == true ? 'Please enter password' : null),
          const SizedBox(height: 10),
          Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: _isLoggingIn
                      ? null
                      : () => _switchAuthMode(AuthMode.forgot),
                  child: const Text('Forgot Password?'))),
          const SizedBox(height: 20),
          ElevatedButton(
              onPressed: _isLoggingIn ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _hasInternetConnection
                      ? const Color(0xFF667EEA)
                      : Colors.grey,
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _isLoggingIn
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white)),
                          SizedBox(width: 10),
                          Text('Logging in...')
                        ])
                  : Text(_hasInternetConnection
                      ? 'Login'
                      : 'No Internet Connection')),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text("Don't have an account?"),
            TextButton(
                onPressed: _isLoggingIn
                    ? null
                    : () => _switchAuthMode(AuthMode.signup),
                child: const Text('Sign up here'))
          ]),
        ]));
  }

  Widget _buildSignupForm() {
    return Form(
        key: _signupFormKey,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!_hasInternetConnection) ...[
            _buildOfflineWarning(),
            const SizedBox(height: 16)
          ],
          TextFormField(
              enabled: !_isSigningUp,
              controller: _signupUsernameController,
              decoration: const InputDecoration(
                  labelText: 'Username', prefixIcon: Icon(Icons.person)),
              validator: (v) => v?.isEmpty == true
                  ? 'Username is required'
                  : v!.length < 3
                      ? 'Min 3 characters'
                      : null),
          const SizedBox(height: 16),
          TextFormField(
              enabled: !_isSigningUp,
              controller: _signupEmailController,
              decoration: const InputDecoration(
                  labelText: 'Email', prefixIcon: Icon(Icons.email)),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v?.isEmpty == true
                  ? 'Email is required'
                  : !v!.contains('@')
                      ? 'Invalid email'
                      : null),
          const SizedBox(height: 16),
          // Phone Number
          // Country Selection
          DropdownButtonFormField<String>(
            value: _selectedCountry,
            decoration: const InputDecoration(
              labelText: 'Country',
              prefixIcon: Icon(Icons.public),
              border: OutlineInputBorder(),
            ),
            items: _countries.map((country) {
              return DropdownMenuItem<String>(
                value: country['code'],
                child: Row(
                  children: [
                    Text(country['flag']!,
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text('${country['name']} (${country['dial']})'),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedCountry = value;
                  final country =
                      _countries.firstWhere((c) => c['code'] == value);
                  _selectedCountryCode = country['dial']!;
                });
              }
            },
          ),
          const SizedBox(height: 16),

          // Phone Number with Country Code
          TextFormField(
            enabled: !_isSigningUp,
            controller: _phoneController,
            decoration: InputDecoration(
              labelText: 'Phone Number',
              hintText: _countries
                  .firstWhere((c) => c['code'] == _selectedCountry)['format'],
              prefixIcon: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Text(
                  _selectedCountryCode,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF667EEA),
                      fontSize: 14),
                ),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            onChanged: (value) {
              // Don't format while typing - only store
            },
            validator: (v) {
              if (v == null || v!.isEmpty) return 'Phone number required';
              final digits = v.replaceAll(RegExp(r'[^\d]'), '');
              if (_selectedCountry == 'CM') {
                if (digits.isNotEmpty && !digits.startsWith('6')) {
                  return 'Cameroon numbers must start with 6';
                }
                if (digits.length != 9) {
                  return 'Cameroon numbers must be 9 digits';
                }
              }
              if (_selectedCountry == 'NG' && digits.length != 10) {
                return 'Nigeria numbers must be 10 digits';
              }
              return null;
            },
          ),
          const SizedBox(height: 4),
          Text(
            'Format: ${_countries.firstWhere((c) => c['code'] == _selectedCountry)['format']}',
            style: const TextStyle(
                fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          TextFormField(
              enabled: !_isSigningUp,
              controller: _signupPasswordController,
              obscureText: !_showSignupPassword,
              onChanged: _checkPasswordStrength,
              decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                      icon: Icon(_showSignupPassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () => setState(
                          () => _showSignupPassword = !_showSignupPassword))),
              validator: (v) => v?.isEmpty == true
                  ? 'Required'
                  : v!.length < 6
                      ? 'Min 6 characters'
                      : null),
          if (_passwordStrength.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_passwordStrength,
                    style: TextStyle(
                        color: _passwordStrength.contains('Weak')
                            ? Colors.red
                            : _passwordStrength.contains('Medium')
                                ? Colors.orange
                                : Colors.green,
                        fontSize: 12))),
          const SizedBox(height: 16),
          TextFormField(
              enabled: !_isSigningUp,
              controller: _confirmPasswordController,
              obscureText: !_showSignupConfirmPassword,
              decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                      icon: Icon(_showSignupConfirmPassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () => setState(() =>
                          _showSignupConfirmPassword =
                              !_showSignupConfirmPassword))),
              validator: (v) => v?.isEmpty == true ? 'Required' : null),
          const SizedBox(height: 20),
          const Text('Security Questions',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          TextFormField(
              enabled: !_isSigningUp,
              controller: _securityAnswer1Controller,
              decoration: const InputDecoration(
                  labelText: "What was your first pet's name?"),
              validator: (v) =>
                  v?.isEmpty == true ? 'pet name required' : null),
          const SizedBox(height: 16),
          TextFormField(
              enabled: !_isSigningUp,
              controller: _securityAnswer2Controller,
              decoration: const InputDecoration(
                  labelText: 'What city were you born in?'),
              validator: (v) => v?.isEmpty == true ? 'city is required' : null),
          const SizedBox(height: 20),

// Register as Manager Toggle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _registerAsManager
                    ? [Colors.orange.shade400, Colors.deepOrange.shade400]
                    : [Colors.grey.shade300, Colors.grey.shade400],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: _registerAsManager
                  ? [
                      BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ]
                  : [],
            ),
            child: SwitchListTile(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _registerAsManager
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _registerAsManager
                          ? Icons.business
                          : Icons.business_outlined,
                      size: 18,
                      color: _registerAsManager ? Colors.white : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Register as Business Manager',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _registerAsManager
                          ? Colors.white
                          : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(left: 34),
                child: Text(
                  'Manage your own company and staff',
                  style: TextStyle(
                    fontSize: 11,
                    color: _registerAsManager
                        ? Colors.white.withValues(alpha: 0.8)
                        : Colors.grey,
                  ),
                ),
              ),
              value: _registerAsManager,
              onChanged: (v) => setState(() {
                _registerAsManager = v;
                _createNewCompany = false;
                _verifiedCompanyId = null;
              }),
              activeColor: Colors.white,
              activeTrackColor: Colors.white.withValues(alpha: 0.3),
              inactiveThumbColor: Colors.grey,
              inactiveTrackColor: Colors.grey.shade200,
            ),
          ),

          if (_registerAsManager) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ========== OPTION 1: INVITE CODE (only show if NOT creating new company) ==========
                    if (!_createNewCompany) ...[
                      if (_verifiedCompanyId == null) ...[
                        // INVITE CODE FIELD
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              enabled: !_isSigningUp,
                              controller: _inviteCodeController,
                              decoration: const InputDecoration(
                                  labelText: 'Company Invite Code',
                                  hintText: 'e.g., MYBIZ',
                                  border: OutlineInputBorder()),
                              textCapitalization: TextCapitalization.characters,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _isVerifyingCode
                                ? null
                                : () async {
                                    setState(() => _isVerifyingCode = true);
                                    try {
                                      final response = await http
                                          .post(
                                            Uri.parse(
                                                '${ApiConfig.baseUrl}/api/companies/verify-code'),
                                            headers: {
                                              'Content-Type': 'application/json'
                                            },
                                            body: json.encode({
                                              'code': _inviteCodeController.text
                                                  .trim()
                                            }),
                                          )
                                          .timeout(const Duration(seconds: 10));
                                      if (response.statusCode == 200) {
                                        final data = json.decode(response.body);
                                        setState(() {
                                          _verifiedCompanyId = data['data']
                                                  ['company']['id']
                                              .toString();
                                          _verifiedCompanyName =
                                              data['data']['company']['name'];
                                        });
                                      } else {
                                        _showErrorDialog(
                                            'Invalid Code',
                                            'Company not found',
                                            Icons.error,
                                            Colors.red);
                                      }
                                    } catch (e) {
                                      _showErrorDialog(
                                          'Error',
                                          'Could not verify',
                                          Icons.error,
                                          Colors.red);
                                    }
                                    setState(() => _isVerifyingCode = false);
                                  },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange),
                            child: _isVerifyingCode
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Text('Verify'),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Text('— OR —',
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 11)),
                        TextButton(
                          onPressed: () => setState(() {
                            _createNewCompany = true;
                            _verifiedCompanyId = null;
                            _verifiedCompanyName = null;
                            _inviteCodeController.clear();
                          }),
                          child: const Text('Create New Company'),
                        ),
                      ] else ...[
                        // VERIFIED COMPANY BADGE
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green)),
                          child: Row(children: [
                            const Icon(Icons.check_circle,
                                color: Colors.green, size: 18),
                            const SizedBox(width: 8),
                            Text('Joining: $_verifiedCompanyName',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => setState(() {
                                _verifiedCompanyId = null;
                                _verifiedCompanyName = null;
                                _inviteCodeController.clear();
                              }),
                            ),
                          ]),
                        ),
                      ],
                    ],

                    // ========== OPTION 2: CREATE NEW COMPANY (only show if create is clicked) ==========
                    if (_createNewCompany) ...[
                      const SizedBox(height: 8),
                      Text('— OR —',
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 11)),
                      TextButton(
                        onPressed: () => setState(() {
                          _createNewCompany = false;
                          _newCompanyNameController.clear();
                          _newCompanyCodeController.clear();
                        }),
                        child: const Text('Use Invite Code Instead'),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        enabled: !_isSigningUp,
                        controller: _newCompanyNameController,
                        decoration: const InputDecoration(
                            labelText: 'Company Name *',
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        enabled: !_isSigningUp,
                        controller: _newCompanyCodeController,
                        decoration: const InputDecoration(
                            labelText: 'Company Code *',
                            hintText: 'e.g., MYTEX',
                            border: OutlineInputBorder()),
                        textCapitalization: TextCapitalization.characters,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        enabled: !_isSigningUp,
                        controller: _newCompanyAddressController,
                        decoration: const InputDecoration(
                            labelText: 'Company Address',
                            hintText: 'Street, city, region',
                            prefixIcon: Icon(Icons.location_on_outlined),
                            border: OutlineInputBorder()),
                        textCapitalization: TextCapitalization.words,
                      ),
                    ],
                  ]),
            ),
          ],

          ElevatedButton(
              onPressed: _isSigningUp ? null : _handleSignup,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _hasInternetConnection
                      ? const Color(0xFF667EEA)
                      : Colors.grey,
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _isSigningUp
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white)),
                          SizedBox(width: 10),
                          Text('Creating...')
                        ])
                  : Text(_hasInternetConnection
                      ? 'Create Account'
                      : 'No Internet Connection')),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('Already have an account?'),
            TextButton(
                onPressed:
                    _isSigningUp ? null : () => _switchAuthMode(AuthMode.login),
                child: const Text('Login here'))
          ]),
        ]));
  }

  Widget _buildForgotForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!_hasInternetConnection) ...[
        _buildOfflineWarning(),
        const SizedBox(height: 16)
      ],
      Container(
        decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Expanded(
              child: GestureDetector(
                  onTap: () => setState(() {
                        _useEmailCode = true;
                        _codeSent = false;
                        _codeVerified = false;
                      }),
                  child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                          color: _useEmailCode
                              ? const Color(0xFF667EEA)
                              : const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(10)),
                      child: Center(
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.email,
                            size: 16,
                            color: _useEmailCode
                                ? Colors.white
                                : const Color(0xFF7F8C8D)),
                        const SizedBox(width: 6),
                        Text('Email Code',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _useEmailCode
                                    ? Colors.white
                                    : const Color(0xFF7F8C8D)))
                      ]))))),
          Expanded(
              child: GestureDetector(
                  onTap: () => setState(() => _useEmailCode = false),
                  child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                          color: !_useEmailCode
                              ? const Color(0xFF667EEA)
                              : const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(10)),
                      child: Center(
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.security,
                            size: 16,
                            color: !_useEmailCode
                                ? Colors.white
                                : const Color(0xFF7F8C8D)),
                        const SizedBox(width: 6),
                        Text('Security Q\'s',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: !_useEmailCode
                                    ? Colors.white
                                    : const Color(0xFF7F8C8D)))
                      ]))))),
        ]),
      ),
      const SizedBox(height: 20),
      if (_useEmailCode) ...[
        if (!_codeSent) ...[
          const Icon(Icons.email_outlined, size: 50, color: Color(0xFF667EEA)),
          const SizedBox(height: 12),
          const Text('Reset via Email Code',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 8),
          const Text('Enter your email to receive a 6-digit code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 20),
          TextFormField(
              enabled: !_isSendingCode,
              controller: _forgotEmailController,
              decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 20),
          ElevatedButton(
              onPressed: _isSendingCode ? null : _sendResetCode,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _isSendingCode
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Send Reset Code',
                      style: TextStyle(color: Colors.white))),
        ] else if (!_codeVerified) ...[
          const Icon(Icons.pin, size: 50, color: Color(0xFF667EEA)),
          const SizedBox(height: 12),
          const Text('Enter Reset Code',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 8),
          Text('Code sent to ${_forgotEmailController.text}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 20),
          TextFormField(
              enabled: !_isVerifyingCode,
              controller: _resetCodeController,
              decoration: const InputDecoration(
                  labelText: '6-digit code',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8)),
          const SizedBox(height: 20),
          ElevatedButton(
              onPressed: _isVerifyingCode ? null : _verifyResetCode,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _isVerifyingCode
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Verify Code',
                      style: TextStyle(color: Colors.white))),
          TextButton(
              onPressed: () => setState(() {
                    _codeSent = false;
                    _resetCodeController.clear();
                  }),
              child: const Text('Try different email')),
        ] else ...[
          const Icon(Icons.lock_open, size: 50, color: Colors.green),
          const SizedBox(height: 12),
          const Text('Set New Password',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 20),
          TextFormField(
              enabled: !_isResettingPassword,
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'New Password',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextFormField(
              enabled: !_isResettingPassword,
              controller: _confirmNewPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder())),
          const SizedBox(height: 20),
          ElevatedButton(
              onPressed: _isResettingPassword ? null : _resetPasswordWithCode,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _isResettingPassword
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Reset Password',
                      style: TextStyle(color: Colors.white))),
        ],
      ] else ...[
        const Icon(Icons.security, size: 50, color: Color(0xFF667EEA)),
        const SizedBox(height: 12),
        const Text('Reset via Security Questions',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        const SizedBox(height: 20),
        TextFormField(
            enabled: !_isResettingWithSecurity,
            controller: _forgotUsernameController,
            decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder()),
            validator: (v) => v?.isEmpty == true ? 'Required' : null),
        const SizedBox(height: 16),
        TextFormField(
            enabled: !_isResettingWithSecurity,
            controller: _forgotEmailController,
            decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email),
                border: OutlineInputBorder()),
            validator: (v) => v?.isEmpty == true ? 'Required' : null),
        const SizedBox(height: 20),
        TextFormField(
            enabled: !_isResettingWithSecurity,
            controller: _forgotSecurity1Controller,
            decoration: const InputDecoration(
                labelText: "What was your first pet's name?",
                border: OutlineInputBorder()),
            validator: (v) => v?.isEmpty == true ? 'Required' : null),
        const SizedBox(height: 16),
        TextFormField(
            enabled: !_isResettingWithSecurity,
            controller: _forgotSecurity2Controller,
            decoration: const InputDecoration(
                labelText: 'What city were you born in?',
                border: OutlineInputBorder()),
            validator: (v) => v?.isEmpty == true ? 'Required' : null),
        const SizedBox(height: 20),
        TextFormField(
            enabled: !_isResettingWithSecurity,
            controller: _newPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'New Password',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder())),
        const SizedBox(height: 16),
        TextFormField(
            enabled: !_isResettingWithSecurity,
            controller: _confirmNewPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder())),
        const SizedBox(height: 20),
        ElevatedButton(
            onPressed:
                _isResettingWithSecurity ? null : _resetPasswordWithSecurity,
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _isResettingWithSecurity
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Reset Password',
                    style: TextStyle(color: Colors.white))),
      ],
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('Remember password?'),
        TextButton(
            onPressed: () => _switchAuthMode(AuthMode.login),
            child: const Text('Login'))
      ]),
    ]);
  }

  Widget _buildOfflineWarning() {
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withOpacity(0.3))),
        child: Row(children: [
          Icon(Icons.info_outline, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text('Requires internet connection',
                  style: TextStyle(color: Colors.orange[800], fontSize: 12)))
        ]));
  }
}

enum AuthMode { login, signup, forgot }
