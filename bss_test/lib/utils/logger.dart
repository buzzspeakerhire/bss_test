import 'dart:async';
import 'package:flutter/foundation.dart';

/// Simple logging service with stream support
class Logger {
  // Singleton instance
  static final Logger _instance = Logger._internal();
  factory Logger() => _instance;
  Logger._internal();
  
  // Log storage
  final List<String> _logMessages = [];
  final int _maxLogMessages = 200;
  
  // Stream controller
  final _logStreamController = StreamController<String>.broadcast();
  
  // Public getters
  Stream<String> get onLog => _logStreamController.stream;
  List<String> get logs => List.unmodifiable(_logMessages);
  
  // Add a log message
  void log(String message) {
    final timestamp = DateTime.now().toString().split('.')[0];
    final logMessage = "$timestamp: $message";
    
    // Add to internal storage with limit
    _logMessages.add(logMessage);
    if (_logMessages.length > _maxLogMessages) {
      _logMessages.removeAt(0);
    }
    
    // Send to stream
    _logStreamController.add(logMessage);
    
    // Also output to console in debug mode
    if (kDebugMode) {
      debugPrint(logMessage);
    }
  }
  
  // Clear all logs
  void clear() {
    _logMessages.clear();
    // Send an empty message to indicate cleared
    _logStreamController.add('');
  }
  
  // Clean up resources
  void dispose() {
    _logStreamController.close();
  }
}