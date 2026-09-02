// services/backend_auth_service.dart
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class BackendAuthService {
  // ✅ NOW PUBLIC - accessible from anywhere
  static const String baseUrl = 'https://drink-quick-cal-kja1.onrender.com';

  // ✅ CORRECT ENDPOINTS - Using public baseUrl
  static const String _loginEndpoint = '$baseUrl/api/auth/login';
  static const String _registerEndpoint = '$baseUrl/api/auth/register';
  static const String _logoutEndpoint = '$baseUrl/api/auth/logout';
  static const String _currentUserEndpoint = '$baseUrl/api/auth/me';
  static const String _testEndpoint = '$baseUrl/api/test';
  static const String _healthEndpoint = '$baseUrl/health';
  static const String _drinksEndpoint = '$baseUrl/api/drinks';
  static const String _usersEndpoint = '$baseUrl/api/users';

  static const Duration _backendTimeout = Duration(seconds: 60);

  void printEndpoints() {
    debugPrint('🔗 Backend URLs:');
    debugPrint('   Base URL: $baseUrl');
    debugPrint('   Login: $_loginEndpoint');
    debugPrint('   Register: $_registerEndpoint');
    debugPrint('   Test: $_testEndpoint');
    debugPrint('   Health: $_healthEndpoint');
    debugPrint('   Drinks: $_drinksEndpoint');
    debugPrint('   Users: $_usersEndpoint');
  }

  Future<Map<String, dynamic>> testBackend() async {
    debugPrint('🔌 Testing backend connection to: $baseUrl');

    final testUrls = [
      {'url': baseUrl, 'name': 'Root'},
      {'url': _healthEndpoint, 'name': 'Health'},
      {'url': _testEndpoint, 'name': 'Test API'},
      {'url': _loginEndpoint, 'name': 'Login'},
      {'url': _registerEndpoint, 'name': 'Register'},
      {'url': _drinksEndpoint, 'name': 'Drinks'},
      {'url': _usersEndpoint, 'name': 'Users'},
    ];

    final results = <Map<String, dynamic>>[];

    for (final test in testUrls) {
      try {
        debugPrint('\n🔗 Testing ${test['name']}: ${test['url']}');

        final response = await http.get(
          Uri.parse(test['url']!),
          headers: {
            'Accept': 'application/json',
            // /api/drinks and /api/users now require a session; 401 means
            // the endpoint EXISTS and is protected — still "reachable".
          },
        ).timeout(_backendTimeout);

        // 200 = open endpoint, 401 = protected endpoint that exists.
        // Both prove the backend is up; only network errors / true 404s
        // indicate connectivity problems.
        final success = response.statusCode == 200 ||
            response.statusCode == 401;

        final statusMessage = success ? '✅ Accessible' : '⚠️ Blocked';

        results.add({
          'name': test['name'],
          'url': test['url'],
          'success': success,
          'statusCode': response.statusCode,
          'message': statusMessage,
          'response': response.body.length > 100
              ? '${response.body.substring(0, 100)}...'
              : response.body,
        });

        debugPrint('   Status: ${response.statusCode}');
        debugPrint(
            '   Response: ${response.body.length > 50 ? '${response.body.substring(0, 50)}...' : response.body}');
      } catch (e) {
        debugPrint('   ❌ Error: $e');
        final errorMsg = e is TimeoutException
            ? '⚠️ Timeout - Backend might be waking up (takes 30-60s on free tier)'
            : '❌ Failed: $e';

        results.add({
          'name': test['name'],
          'url': test['url'],
          'success': false,
          'error': e.toString(),
          'message': errorMsg,
        });
      }
    }

    final essentialEndpoints = results
        .where((r) => r['name'] == 'Test API' || r['name'] == 'Drinks')
        .toList();

    final atLeastOneAccessible =
        essentialEndpoints.any((r) => r['success'] == true);

    return {
      'success': atLeastOneAccessible,
      'results': results,
      'message': atLeastOneAccessible
          ? '✅ Backend is accessible!'
          : '⚠️ Backend connection issues - might be waking up',
      'backendUrl': baseUrl,
    };
  }

  Future<bool> wakeUpBackend() async {
    debugPrint('🌅 Attempting to wake up backend...');

    for (int attempt = 1; attempt <= 3; attempt++) {
      final timeout = Duration(seconds: attempt * 20);
      debugPrint(
          'Attempt $attempt/3 with ${timeout.inSeconds} second timeout...');

      try {
        final response = await http.get(
          Uri.parse(_testEndpoint),
          headers: {'Accept': 'application/json'},
        ).timeout(timeout);

        if (response.statusCode == 200) {
          debugPrint('✅ Backend is awake!');
          return true;
        }
      } catch (e) {
        debugPrint('Attempt $attempt failed: $e');
        if (attempt < 3) {
          await Future.delayed(const Duration(seconds: 5));
        }
      }
    }

    debugPrint('❌ Failed to wake backend after 3 attempts');
    return false;
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required Map<String, String> securityQuestions,
    String? phone,
    bool registerAsManager = false,
    String? companyId,
    String? companyName,
    String? companyCode,
  }) async {
    debugPrint('👤 REGISTER REQUEST');
    debugPrint('🔗 Endpoint: $_registerEndpoint');
    debugPrint('📝 Username: $username');
    debugPrint('📧 Email: $email');
    debugPrint('🔐 Password: ${'*' * password.length}');

    try {
      final isAwake = await wakeUpBackend();
      if (!isAwake) {
        return {
          'success': false,
          'message':
              '❌ Backend is taking too long to start. Please try again in 30 seconds.',
          'backendStarting': true,
        };
      }

      final body = jsonEncode({
        'username': username,
        'email': email,
        'password': password,
        'phone': phone,
        'registerAsManager': registerAsManager,
        'companyId': companyId,
        'companyName': companyName,
        'companyCode': companyCode,
        'securityQuestions': securityQuestions,
      });

      final response = await http
          .post(
            Uri.parse(_registerEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(_backendTimeout);

      debugPrint('📨 Response Status: ${response.statusCode}');
      debugPrint('📨 Response Body: ${response.body}');

      Map<String, dynamic> responseData = {};
      if (response.body.isNotEmpty) {
        try {
          responseData = jsonDecode(response.body);
        } catch (e) {
          debugPrint('⚠️ JSON Parse Error: $e');
          responseData = {'raw': response.body};
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // ✅ Token is nested under data in the live backend:
        //    { status, message, data: { user, token, refreshToken } }
        String? token;
        String? refreshToken;

        if (responseData['token'] != null) {
          token = responseData['token'].toString();
        } else if (responseData['data'] is Map) {
          final innerData = Map<String, dynamic>.from(responseData['data']);
          token = innerData['token']?.toString();
          refreshToken = innerData['refreshToken']?.toString();
        }

        if (token != null && token.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', token);

          if (refreshToken != null && refreshToken.isNotEmpty) {
            await prefs.setString('refresh_token', refreshToken);
          } else if (responseData['refreshToken'] != null) {
            await prefs.setString(
                'refresh_token', responseData['refreshToken'].toString());
          }
        }

        final successMessage = responseData['message']?.toString() ??
            'Registration successful! 🎉';

        return {
          'success': true,
          'data': responseData,
          'message': successMessage,
          'statusCode': response.statusCode,
        };
      } else {
        String errorMessage = 'Registration failed';

        // ✅ Preferred: the live backend returns a clear top-level message
        //    (e.g. "Username already taken", "Email already registered").
        if (responseData['message'] != null) {
          errorMessage = responseData['message'].toString();
        } else if (responseData['error'] != null) {
          errorMessage = responseData['error'].toString();
        } else if (responseData['errors'] is List &&
            (responseData['errors'] as List).isNotEmpty) {
          final first = (responseData['errors'] as List).first;
          if (first is Map && first['message'] != null) {
            errorMessage = first['message'].toString();
          }
        }

        return {
          'success': false,
          'message': errorMessage,
          'statusCode': response.statusCode,
          'data': responseData,
        };
      }
    } catch (e) {
      debugPrint('❌ REGISTER ERROR: $e');

      String errorMessage = 'Network error: $e';
      if (e is TimeoutException) {
        errorMessage =
            'Backend is taking too long to respond. Please wait and try again.';
      }

      return {
        'success': false,
        'message': errorMessage,
        'error': e.toString(),
        'backendStarting': e is TimeoutException,
      };
    }
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    String? deviceId,
    String? deviceName,
  }) async {
    debugPrint('🔑 LOGIN REQUEST');
    debugPrint('🔗 Endpoint: $_loginEndpoint');
    debugPrint('👤 Username/Email: $username');

    try {
      final isAwake = await wakeUpBackend();
      if (!isAwake) {
        return {
          'success': false,
          'message':
              '❌ Backend is starting up. Please try again in 30 seconds.',
          'backendStarting': true,
        };
      }

      final body = jsonEncode({
        'username': username,
        'password': password,
        'deviceId': deviceId,
        'deviceName': deviceName,
      });

      debugPrint('📤 Sending login request to: $_loginEndpoint');
      debugPrint('📤 Request body: ${'*' * password.length} (password hidden)');

      final response = await http
          .post(
            Uri.parse(_loginEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(_backendTimeout);

      debugPrint('📨 Response Status: ${response.statusCode}');
      debugPrint('📨 Full Response Body: ${response.body}');

      Map<String, dynamic> responseData = {};
      if (response.body.isNotEmpty) {
        try {
          responseData = jsonDecode(response.body);

          debugPrint('📊 Response Data Structure:');
          debugPrint('   Type: ${responseData.runtimeType}');
          debugPrint('   Keys: ${responseData.keys}');
          if (responseData.containsKey('user')) {
            debugPrint(
                '   User data type: ${responseData['user'].runtimeType}');
            if (responseData['user'] is Map) {
              debugPrint('   User keys: ${(responseData['user'] as Map).keys}');
              debugPrint('   User values: ${responseData['user']}');
            }
          }
        } catch (e) {
          debugPrint('⚠️ JSON Parse Error: $e');
          responseData = {'raw': response.body};
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (responseData['token'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', responseData['token']);

          if (responseData['refreshToken'] != null) {
            await prefs.setString(
                'refresh_token', responseData['refreshToken']);
          }
        }

        return {
          'success': true,
          'data': responseData,
          'message': 'Login successful! ✅',
          'statusCode': response.statusCode,
        };
      } else {
        String errorMessage = 'Login failed';
        if (responseData['message'] != null) {
          errorMessage = responseData['message'];
        }

        return {
          'success': false,
          'message': '❌ $errorMessage',
          'statusCode': response.statusCode,
          'data': responseData,
        };
      }
    } catch (e) {
      debugPrint('❌ LOGIN ERROR: $e');

      String errorMessage = 'Network error: $e';
      if (e is TimeoutException) {
        errorMessage = 'Backend is starting up. Please wait and try again.';
      }

      return {
        'success': false,
        'message': errorMessage,
        'error': e.toString(),
        'backendStarting': e is TimeoutException,
      };
    }
  }

  // ============================================================
  // ✅ FIXED: Get current user
  // ============================================================
  Future<User?> getCurrentUser() async {
    try {
      final token = await _getToken();
      if (token == null) {
        debugPrint('❌ No auth token found');
        return null;
      }

      debugPrint('🔍 Getting current user with token...');
      final response = await http.get(
        Uri.parse(_currentUserEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_backendTimeout);

      debugPrint('📨 Current user response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('📨 Current user data: $data');

        // ✅ Try multiple data structures
        Map<String, dynamic>? userData;

        if (data['data'] != null && data['data']['user'] != null) {
          userData = data['data']['user'] as Map<String, dynamic>;
        } else if (data['user'] != null) {
          userData = data['user'] as Map<String, dynamic>;
        } else if (data['username'] != null) {
          userData = data;
        }

        if (userData != null) {
          debugPrint('✅ Found current user: ${userData['username']}');
          return User.fromJson(userData);
        }
      }

      debugPrint('⚠️ Failed to get current user: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('❌ Get current user error: $e');
      return null;
    }
  }

  // ============================================================
  // ✅ NEW: Get user by username (for pending approval flow)
  // ============================================================
  Future<User?> getUserByUsername(String username) async {
    try {
      final token = await _getToken();
      if (token == null) {
        debugPrint('❌ getUserByUsername: No auth token found');
        return null;
      }

      debugPrint('🔍 Getting user by username: $username');

      final response = await http.get(
        Uri.parse('$_usersEndpoint?username=$username'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_backendTimeout);

      debugPrint('📨 getUserByUsername response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('📨 getUserByUsername data: $data');

        // ✅ Try multiple data structures
        Map<String, dynamic>? userData;

        if (data['data'] != null && data['data']['users'] != null) {
          final users = data['data']['users'] as List;
          if (users.isNotEmpty) {
            userData = users.first as Map<String, dynamic>;
          }
        } else if (data['user'] != null) {
          userData = data['user'] as Map<String, dynamic>;
        } else if (data['users'] != null) {
          final users = data['users'] as List;
          if (users.isNotEmpty) {
            userData = users.first as Map<String, dynamic>;
          }
        } else if (data['username'] != null) {
          userData = data;
        }

        if (userData != null) {
          debugPrint('✅ Found user data: ${userData['username']}');
          return User.fromJson(userData);
        }
      }

      debugPrint('⚠️ getUserByUsername: User not found');
      return null;
    } catch (e) {
      debugPrint('❌ getUserByUsername error: $e');
      return null;
    }
  }

  // ============================================================
  // ✅ NEW: Get user by ID
  // ============================================================
  Future<User?> getUserById(String userId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        debugPrint('❌ getUserById: No auth token found');
        return null;
      }

      debugPrint('🔍 Getting user by ID: $userId');

      final response = await http.get(
        Uri.parse('$_usersEndpoint/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_backendTimeout);

      debugPrint('📨 getUserById response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // ✅ Try multiple data structures
        Map<String, dynamic>? userData;

        if (data['data'] != null && data['data']['user'] != null) {
          userData = data['data']['user'] as Map<String, dynamic>;
        } else if (data['user'] != null) {
          userData = data['user'] as Map<String, dynamic>;
        } else if (data['username'] != null) {
          userData = data;
        }

        if (userData != null) {
          debugPrint('✅ Found user data: ${userData['username']}');
          return User.fromJson(userData);
        }
      }

      debugPrint('⚠️ getUserById: User not found');
      return null;
    } catch (e) {
      debugPrint('❌ getUserById error: $e');
      return null;
    }
  }

  // ✅ Check approval status (for Staff)
  Future<Map<String, dynamic>> checkApprovalStatus(String requestToken) async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/check-approval?token=$requestToken'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(_backendTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'status': 'error', 'message': 'Failed to check approval status'};
    } catch (e) {
      debugPrint('❌ Check approval error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // ✅ Get pending requests (for Manager)
  Future<Map<String, dynamic>> getPendingRequests() async {
    try {
      final token = await _getToken();
      if (token == null) {
        return {'status': 'error', 'message': 'Not authenticated'};
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/pending-requests'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_backendTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'status': 'error', 'message': 'Failed to get pending requests'};
    } catch (e) {
      debugPrint('❌ Get pending requests error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // ✅ Approve or reject login (Manager)
  Future<Map<String, dynamic>> approveLogin({
    required String requestToken,
    required bool approved,
    required String managerId,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        return {'status': 'error', 'message': 'Not authenticated'};
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/approve-login'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'requestToken': requestToken,
              'approved': approved,
              'managerId': managerId,
            }),
          )
          .timeout(_backendTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'status': 'error', 'message': 'Failed to process approval'};
    } catch (e) {
      debugPrint('❌ Approve login error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // 🔐 Get pending company JOIN requests (owner verification flow)
  Future<Map<String, dynamic>> getPendingJoins() async {
    try {
      final token = await _getToken();
      if (token == null) {
        return {'status': 'error', 'message': 'Not authenticated'};
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/pending-joins'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_backendTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      final body = jsonDecode(response.body);
      return {'status': 'error', 'message': body['message'] ?? 'Failed to get join requests'};
    } catch (e) {
      debugPrint('❌ Get pending joins error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // 🔐 Approve/reject a company JOIN request.
  //    Owners must pass the [code] emailed to them; Administrators override.
  Future<Map<String, dynamic>> approveJoin({
    required int requestId,
    required bool approved,
    String? code,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        return {'status': 'error', 'message': 'Not authenticated'};
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/approve-join/$requestId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'approved': approved,
              if (code != null && code.isNotEmpty) 'code': code,
            }),
          )
          .timeout(_backendTimeout);

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return body;
      }
      return {'status': 'error', 'message': body['message'] ?? 'Failed to process join request'};
    } catch (e) {
      debugPrint('❌ Approve join error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> logout() async {
    try {
      final token = await _getToken();

      if (token != null) {
        await http.post(
          Uri.parse(_logoutEndpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ).timeout(_backendTimeout);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('refresh_token');

      return {
        'success': true,
        'message': 'Logged out successfully',
      };
    } catch (e) {
      debugPrint('Logout error: $e');
      return {
        'success': false,
        'message': 'Logout error: $e',
      };
    }
  }

  // ============================================================
  // ✅ ADD THIS MISSING METHOD
  // ============================================================
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    debugPrint(
        '🔑 Retrieved token: ${token != null ? 'Yes (${token.length} chars)' : 'No'}');
    return token;
  }
}

// ============================================================
// ✅ Extended User class with role and companyId
// ============================================================
class User {
  final String id;
  final String username;
  final String email;
  final Map<String, String> securityAnswers;
  final String? role;
  final int? companyId;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.securityAnswers,
    this.role,
    this.companyId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'securityAnswers': securityAnswers,
      'role': role,
      'companyId': companyId,
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

    // ✅ Extract role and companyId
    String? role = json['role']?.toString();
    int? companyId;

    if (json['companyId'] != null) {
      companyId = json['companyId'] is int
          ? json['companyId']
          : int.tryParse(json['companyId'].toString());
    } else if (json['company_id'] != null) {
      companyId = json['company_id'] is int
          ? json['company_id']
          : int.tryParse(json['company_id'].toString());
    }

    return User(
      id: id.isNotEmpty ? id : 'temp_${DateTime.now().millisecondsSinceEpoch}',
      username: json['username']?.toString() ?? 'Unknown',
      email: json['email']?.toString() ?? 'unknown@example.com',
      securityAnswers: Map<String, String>.from(
          json['securityAnswers'] ?? json['securityQuestions'] ?? {}),
      role: role,
      companyId: companyId,
    );
  }
}
