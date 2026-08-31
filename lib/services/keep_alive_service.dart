// services/keep_alive_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class KeepAliveService {
  static final KeepAliveService _instance = KeepAliveService._internal();
  factory KeepAliveService() => _instance;
  KeepAliveService._internal();

  Timer? _keepAliveTimer;
  final String _backendUrl = 'https://drink-quick-cal-kja1.onrender.com';
  bool _isRunning = false;
  int _pingCount = 0;

  // Start pinging the backend every 5 minutes to prevent sleep
  void startKeepAlive() {
    if (_isRunning) return;
    
    _isRunning = true;
    print('🚀 Starting keep-alive service...');

    // Ping immediately
    _pingBackend();

    // Then ping every 5 minutes (less than 15 minutes to prevent sleep)
    _keepAliveTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _pingBackend();
    });
  }

  void stopKeepAlive() {
    if (!_isRunning) return;
    
    _isRunning = false;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    print('🛑 Stopping keep-alive service');
  }

  Future<void> _pingBackend() async {
    _pingCount++;
    print('🔔 Keep-alive ping #$_pingCount');
    
    try {
      // Try health endpoint first
      final healthResponse = await http.get(
        Uri.parse('$_backendUrl/health'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (healthResponse.statusCode == 200) {
        print('✅ Keep-alive ping successful');
        return;
      }
    } catch (e) {
      // Health endpoint failed, try test endpoint
      try {
        final testResponse = await http.get(
          Uri.parse('$_backendUrl/api/test'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 10));
        
        if (testResponse.statusCode == 200) {
          print('✅ Keep-alive via /api/test successful');
          return;
        }
      } catch (e2) {
        print('⚠️ Both keep-alive attempts failed');
      }
    }
  }

  // Wake up the backend with multiple attempts
  Future<bool> wakeUpBackend() async {
    print('🌅 Attempting to wake up backend...');
    
    final endpoints = [
      '$_backendUrl/api/test',
      '$_backendUrl/health',
      '$_backendUrl',
    ];
    
    for (int attempt = 1; attempt <= 3; attempt++) {
      final timeout = Duration(seconds: attempt * 20);
      print('Attempt $attempt/3 with ${timeout.inSeconds} second timeout...');
      
      for (final endpoint in endpoints) {
        try {
          print('Trying endpoint: $endpoint');
          final response = await http.get(
            Uri.parse(endpoint),
            headers: {'Accept': 'application/json'},
          ).timeout(timeout);
          
          if (response.statusCode == 200) {
            print('✅ Backend is awake! Responded via: $endpoint');
            return true;
          }
        } catch (e) {
          print('Endpoint $endpoint failed: $e');
        }
      }
      
      if (attempt < 3) {
        print('Waiting 5 seconds before next attempt...');
        await Future.delayed(const Duration(seconds: 5));
      }
    }
    
    print('❌ Failed to wake backend after 3 attempts');
    return false;
  }

  // Check if backend is responsive (quick check)
  Future<bool> isBackendResponsive() async {
    try {
      final response = await http.get(
        Uri.parse('$_backendUrl/api/test'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Save last backend response time
  Future<void> saveLastResponseTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_backend_response', DateTime.now().millisecondsSinceEpoch);
  }

  // Get time since last successful backend response
  Future<Duration> getTimeSinceLastResponse() async {
    final prefs = await SharedPreferences.getInstance();
    final lastResponse = prefs.getInt('last_backend_response');
    
    if (lastResponse == null) {
      return const Duration(days: 365); // Very long time
    }
    
    final lastTime = DateTime.fromMillisecondsSinceEpoch(lastResponse);
    return DateTime.now().difference(lastTime);
  }

  bool get isRunning => _isRunning;
}