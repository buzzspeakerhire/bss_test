import 'dart:async';
import 'package:flutter/foundation.dart';

// A global event system for fader and button communication
class FaderCommunication {
  // Singleton instance
  static final FaderCommunication _instance = FaderCommunication._internal();
  
  factory FaderCommunication() {
    return _instance;
  }
  
  FaderCommunication._internal();
  
  // Stream controllers
  final _faderMovedController = StreamController<Map<String, dynamic>>.broadcast();
  final _faderUpdateController = StreamController<Map<String, dynamic>>.broadcast();
  final _buttonStateController = StreamController<Map<String, dynamic>>.broadcast();
  final _buttonUpdateController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  
  // Public streams
  Stream<Map<String, dynamic>> get onFaderMoved => _faderMovedController.stream;
  Stream<Map<String, dynamic>> get onFaderUpdate => _faderUpdateController.stream;
  Stream<Map<String, dynamic>> get onButtonStateChanged => _buttonStateController.stream;
  Stream<Map<String, dynamic>> get onButtonUpdate => _buttonUpdateController.stream;
  Stream<bool> get onConnectionChanged => _connectionStateController.stream;
  
  // Connection state
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  // Methods to trigger events
  void reportFaderMoved(String address, String paramId, double value) {
    try {
      debugPrint('FaderCommunication: Reporting fader moved - $address, $paramId, $value');
      _safeAddToStream(_faderMovedController, {
        'address': address,
        'paramId': paramId,
        'value': value,
      });
    } catch (e) {
      debugPrint('Error reporting fader moved: $e');
    }
  }
  
  void updateFaderFromDevice(String address, String paramId, double value) {
    try {
      debugPrint('FaderCommunication: Updating fader from device - $address, $paramId, $value');
      _safeAddToStream(_faderUpdateController, {
        'address': address,
        'paramId': paramId,
        'value': value,
      });
    } catch (e) {
      debugPrint('Error updating fader from device: $e');
    }
  }
  
  void reportButtonStateChanged(String address, String paramId, bool state) {
    try {
      debugPrint('FaderCommunication: Reporting button state changed - $address, $paramId, $state');
      _safeAddToStream(_buttonStateController, {
        'address': address,
        'paramId': paramId,
        'state': state,
      });
    } catch (e) {
      debugPrint('Error reporting button state changed: $e');
    }
  }
  
  void updateButtonFromDevice(String address, String paramId, bool state) {
    try {
      debugPrint('FaderCommunication: Updating button from device - $address, $paramId, $state');
      _safeAddToStream(_buttonUpdateController, {
        'address': address,
        'paramId': paramId,
        'state': state,
      });
    } catch (e) {
      debugPrint('Error updating button from device: $e');
    }
  }
  
  void setConnectionState(bool connected) {
    try {
      if (_isConnected != connected) {
        debugPrint('FaderCommunication: Connection state changed to $connected');
        _isConnected = connected;
        _safeAddToStream(_connectionStateController, connected);
      }
    } catch (e) {
      debugPrint('Error setting connection state: $e');
    }
  }
  
  // Helper method to safely add data to a stream without blocking
  void _safeAddToStream<T>(StreamController<T> controller, T data) {
    if (!controller.isClosed) {
      try {
        controller.add(data);
      } catch (e) {
        debugPrint('Error adding to stream: $e');
      }
    }
  }
  
  void dispose() {
    try {
      _faderMovedController.close();
      _faderUpdateController.close();
      _buttonStateController.close();
      _buttonUpdateController.close();
      _connectionStateController.close();
    } catch (e) {
      debugPrint('Error disposing FaderCommunication: $e');
    }
  }
}