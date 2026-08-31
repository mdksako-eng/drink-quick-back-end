// services/api_client.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class ApiClient {
  static String get baseUrl => ApiConfig.apiBase;
  
  // Generic HTTP methods
  Future<dynamic> get(String endpoint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      
      final response = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
      );
      
      return _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  Future<dynamic> post(String endpoint, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      
      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
        body: json.encode(data),
      );
      
      return _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  Future<dynamic> put(String endpoint, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      
      final response = await http.put(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
        body: json.encode(data),
      );
      
      return _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  Future<dynamic> delete(String endpoint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      
      final response = await http.delete(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
      );
      
      return _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // Handle response
  dynamic _handleResponse(http.Response response) {
    final responseBody = response.body;
    if (responseBody.isEmpty) {
      return null;
    }
    
    final Map<String, dynamic> responseData = json.decode(responseBody);
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return responseData;
    } else {
      throw ApiException(
        message: responseData['message'] ?? 'Request failed with status: ${response.statusCode}',
        statusCode: response.statusCode,
        data: responseData,
      );
    }
  }
  
  // Handle errors
  Exception _handleError(dynamic error) {
    if (error is SocketException) {
      return ApiException(message: 'No internet connection', statusCode: 0);
    } else if (error is http.ClientException) {
      return ApiException(message: 'Failed to connect to server', statusCode: 0);
    }
    return ApiException(message: 'An error occurred: $error', statusCode: 0);
  }
  
  // Test connection
  Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.health),
        headers: {'Content-Type': 'application/json'},
      );
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  
  // New methods that were missing
  Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson != null) {
      return json.decode(userJson) as Map<String, dynamic>;
    }
    return null;
  }
  
  Future<void> saveAuthData(String token, String refreshToken, Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('refresh_token', refreshToken);
    await prefs.setString('user', json.encode(user));
  }
  
  Future<void> clearAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user');
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final dynamic data;
  
  ApiException({required this.message, required this.statusCode, this.data});
  
  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}