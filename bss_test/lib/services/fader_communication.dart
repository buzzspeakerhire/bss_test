import 'dart:async';
import 'package:flutter/foundation.dart';

// A global event system for fader and button communication
class FaderCommunication {
  // Singleton instance
  static final FaderCommunication _instance = FaderCommunication._internal();
  
  factory FaderCommunication() {
    return _instance;
  }
  
  FaderCommunication._internal() {
    debugPrint('FaderCommunication: Creating new instance ${hashCode}');
    // Initialize stream controllers
    _initializeStreamControllers();
  }
  
  // Stream controllers
  late StreamController<Map<String, dynamic>> _faderMovedController;
  late StreamController<Map<String, dynamic>> _faderUpdateController;
  late StreamController<Map<String, dynamic>> _buttonStateController;
  late StreamController<Map<String, dynamic>> _buttonUpdateController;
  late StreamController<bool> _connectionStateController;
  
  // Initialize stream controllers explicitly
  void _initializeStreamControllers() {
    _faderMovedController = StreamController<Map<String, dynamic>>.broadcast();
    _faderUpdateController = StreamController<Map<String, dynamic>>.broadcast();
    _buttonStateController = StreamController<Map<String, dynamic>>.broadcast();
    _buttonUpdateController = StreamController<Map<String, dynamic>>.broadcast();
    _connectionStateController = StreamController<bool>.broadcast();
    
    debugPrint('FaderCommunication: All stream controllers initialized');
  }
  
  // Public streams
  Stream<Map<String, dynamic>> get onFaderMoved => _faderMovedController.stream;
  Stream<Map<String, dynamic>> get onFaderUpdate => _faderUpdateController.stream;
  Stream<Map<String, dynamic>> get onButtonStateChanged => _buttonStateController.stream;
  Stream<Map<String, dynamic>> get onButtonUpdate => _buttonUpdateController.stream;
  Stream<bool> get onConnectionChanged => _connectionStateController.stream;
  
  // Connection state
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  // Debug counter for tracking update events
  int _faderUpdateCount = 0;
  int _buttonUpdateCount = 0;
  
  // Direct event notification system - track functions instead of streams
  final List<Function(Map<String, dynamic>)> _faderMovedListeners = [];
  final List<Function(Map<String, dynamic>)> _faderUpdateListeners = [];
  final List<Function(Map<String, dynamic>)> _buttonStateListeners = [];
  final List<Function(Map<String, dynamic>)> _buttonUpdateListeners = [];
  final List<Function(bool)> _connectionStateListeners = [];
  
  // Add direct listeners
  void addFaderMovedListener(Function(Map<String, dynamic>) listener) {
    _faderMovedListeners.add(listener);
    debugPrint('FaderCommunication: Added fader moved listener, total listeners: ${_faderMovedListeners.length}');
  }
  
  void addFaderUpdateListener(Function(Map<String, dynamic>) listener) {
    _faderUpdateListeners.add(listener);
    debugPrint('FaderCommunication: Added fader update listener, total listeners: ${_faderUpdateListeners.length}');
  }
  
  void addButtonStateListener(Function(Map<String, dynamic>) listener) {
    _buttonStateListeners.add(listener);
    debugPrint('FaderCommunication: Added button state listener, total listeners: ${_buttonStateListeners.length}');
  }
  
  void addButtonUpdateListener(Function(Map<String, dynamic>) listener) {
    _buttonUpdateListeners.add(listener);
    debugPrint('FaderCommunication: Added button update listener, total listeners: ${_buttonUpdateListeners.length}');
  }
  
  void addConnectionStateListener(Function(bool) listener) {
    _connectionStateListeners.add(listener);
    debugPrint('FaderCommunication: Added connection state listener, total listeners: ${_connectionStateListeners.length}');
  }
  
  // Remove direct listeners
  void removeFaderMovedListener(Function(Map<String, dynamic>) listener) {
    _faderMovedListeners.remove(listener);
    debugPrint('FaderCommunication: Removed fader moved listener, total listeners: ${_faderMovedListeners.length}');
  }
  
  void removeFaderUpdateListener(Function(Map<String, dynamic>) listener) {
    _faderUpdateListeners.remove(listener);
    debugPrint('FaderCommunication: Removed fader update listener, total listeners: ${_faderUpdateListeners.length}');
  }
  
  void removeButtonStateListener(Function(Map<String, dynamic>) listener) {
    _buttonStateListeners.remove(listener);
    debugPrint('FaderCommunication: Removed button state listener, total listeners: ${_buttonStateListeners.length}');
  }
  
  void removeButtonUpdateListener(Function(Map<String, dynamic>) listener) {
    _buttonUpdateListeners.remove(listener);
    debugPrint('FaderCommunication: Removed button update listener, total listeners: ${_buttonUpdateListeners.length}');
  }
  
  void removeConnectionStateListener(Function(bool) listener) {
    _connectionStateListeners.remove(listener);
    debugPrint('FaderCommunication: Removed connection state listener, total listeners: ${_connectionStateListeners.length}');
  }
  
  // Methods to trigger events
  void reportFaderMoved(String address, String paramId, double value) {
    try {
      final data = {
        'address': address,
        'paramId': paramId,
        'value': value,
      };
      
      debugPrint('FaderCommunication: Reporting fader moved - $address, $paramId, $value');
      
      // Notify using both systems
      _safeAddToStream(_faderMovedController, data);
      _notifyFaderMovedListeners(data);
    } catch (e) {
      debugPrint('Error reporting fader moved: $e');
    }
  }
  
  void updateFaderFromDevice(String address, String paramId, double value) {
    try {
      _faderUpdateCount++;
      final data = {
        'address': address,
        'paramId': paramId,
        'value': value,
      };
      
      debugPrint('FaderCommunication: Updating fader from device (update #$_faderUpdateCount) - $address, $paramId, $value');
      debugPrint('FaderCommunication: Stream controller has ${_faderUpdateController.hasListener ? "some" : "no"} listeners');
      debugPrint('FaderCommunication: Direct listeners count: ${_faderUpdateListeners.length}');
      
      // Notify using both systems
      _safeAddToStream(_faderUpdateController, data);
      _notifyFaderUpdateListeners(data);
      
      // Force addition of a temporary listener if none exist
      if (!_faderUpdateController.hasListener && _faderUpdateListeners.isEmpty) {
        debugPrint('FaderCommunication: Adding temporary listener to prevent event loss');
        final subscription = _faderUpdateController.stream.listen((data) {
          debugPrint('FaderCommunication: Temporary listener received: $data');
        });
        
        // Cancel after a short delay
        Future.delayed(Duration(milliseconds: 100), () {
          subscription.cancel();
        });
      }
    } catch (e) {
      debugPrint('Error updating fader from device: $e');
    }
  }
  
  void reportButtonStateChanged(String address, String paramId, bool state) {
    try {
      final data = {
        'address': address,
        'paramId': paramId,
        'state': state,
      };
      
      debugPrint('FaderCommunication: Reporting button state changed - $address, $paramId, $state');
      
      // Notify using both systems
      _safeAddToStream(_buttonStateController, data);
      _notifyButtonStateListeners(data);
    } catch (e) {
      debugPrint('Error reporting button state changed: $e');
    }
  }
  
  void updateButtonFromDevice(String address, String paramId, bool state) {
    try {
      _buttonUpdateCount++;
      final data = {
        'address': address,
        'paramId': paramId,
        'state': state,
      };
      
      debugPrint('FaderCommunication: Updating button from device (update #$_buttonUpdateCount) - $address, $paramId, $state');
      debugPrint('FaderCommunication: Stream controller has ${_buttonUpdateController.hasListener ? "some" : "no"} listeners');
      debugPrint('FaderCommunication: Direct listeners count: ${_buttonUpdateListeners.length}');
      
      // Notify using both systems
      _safeAddToStream(_buttonUpdateController, data);
      _notifyButtonUpdateListeners(data);
      
      // Force addition of a temporary listener if none exist
      if (!_buttonUpdateController.hasListener && _buttonUpdateListeners.isEmpty) {
        debugPrint('FaderCommunication: Adding temporary listener to prevent event loss');
        final subscription = _buttonUpdateController.stream.listen((data) {
          debugPrint('FaderCommunication: Temporary listener received: $data');
        });
        
        // Cancel after a short delay
        Future.delayed(Duration(milliseconds: 100), () {
          subscription.cancel();
        });
      }
    } catch (e) {
      debugPrint('Error updating button from device: $e');
    }
  }
  
  void setConnectionState(bool connected) {
    try {
      if (_isConnected != connected) {
        debugPrint('FaderCommunication: Connection state changed to $connected');
        _isConnected = connected;
        
        // Notify using both systems
        _safeAddToStream(_connectionStateController, connected);
        _notifyConnectionStateListeners(connected);
        
        // Reset counters when connection changes
        if (connected) {
          _faderUpdateCount = 0;
          _buttonUpdateCount = 0;
        }
      }
    } catch (e) {
      debugPrint('Error setting connection state: $e');
    }
  }
  
  // Direct notification methods
  void _notifyFaderMovedListeners(Map<String, dynamic> data) {
    for (var listener in _faderMovedListeners) {
      try {
        listener(data);
      } catch (e) {
        debugPrint('Error notifying fader moved listener: $e');
      }
    }
  }
  
  void _notifyFaderUpdateListeners(Map<String, dynamic> data) {
    debugPrint('FaderCommunication: Notifying ${_faderUpdateListeners.length} fader update listeners');
    for (var listener in _faderUpdateListeners) {
      try {
        listener(data);
      } catch (e) {
        debugPrint('Error notifying fader update listener: $e');
      }
    }
  }
  
  void _notifyButtonStateListeners(Map<String, dynamic> data) {
    for (var listener in _buttonStateListeners) {
      try {
        listener(data);
      } catch (e) {
        debugPrint('Error notifying button state listener: $e');
      }
    }
  }
  
  void _notifyButtonUpdateListeners(Map<String, dynamic> data) {
    debugPrint('FaderCommunication: Notifying ${_buttonUpdateListeners.length} button update listeners');
    for (var listener in _buttonUpdateListeners) {
      try {
        listener(data);
      } catch (e) {
        debugPrint('Error notifying button update listener: $e');
      }
    }
  }
  
  void _notifyConnectionStateListeners(bool connected) {
    for (var listener in _connectionStateListeners) {
      try {
        listener(connected);
      } catch (e) {
        debugPrint('Error notifying connection state listener: $e');
      }
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
  
  // Register stream subscription for debugging
  void trackSubscription(StreamSubscription subscription) {
    debugPrint('FaderCommunication: Subscription tracked: ${subscription.hashCode}');
  }
  
  // Unregister stream subscription
  void untrackSubscription(StreamSubscription subscription) {
    debugPrint('FaderCommunication: Subscription untracked: ${subscription.hashCode}');
  }
  
  void dispose() {
    try {
      _faderMovedController.close();
      _faderUpdateController.close();
      _buttonStateController.close();
      _buttonUpdateController.close();
      _connectionStateController.close();
      
      // Clear direct listeners
      _faderMovedListeners.clear();
      _faderUpdateListeners.clear();
      _buttonStateListeners.clear();
      _buttonUpdateListeners.clear();
      _connectionStateListeners.clear();
    } catch (e) {
      debugPrint('Error disposing FaderCommunication: $e');
    }
  }
}