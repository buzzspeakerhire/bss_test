// lib/services/controller_bridge.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'control_communication_service.dart';
import 'fader_communication.dart';

/// A bridge service that ensures UI components always receive device updates
class ControllerBridge {
  // Singleton pattern
  static final ControllerBridge _instance = ControllerBridge._internal();
  factory ControllerBridge() => _instance;
  
  // Services
  final _faderComm = FaderCommunication();
  final _controlService = ControlCommunicationService();
  
  // Value notifiers for UI components to observe
  final Map<String, ValueNotifier<double>> faderNotifiers = {};
  final Map<String, ValueNotifier<bool>> buttonNotifiers = {};
  
  // Subscriptions
  List<StreamSubscription> _subscriptions = [];
  
  // Private constructor
  ControllerBridge._internal() {
    debugPrint('ControllerBridge: Initializing...');
    _initialize();
  }
  
  // Initialize and connect services
  void _initialize() {
    try {
      // Listen to fader updates from the device
      var faderSub = _controlService.onFaderUpdate.listen((data) {
        _handleFaderUpdate(data);
      });
      _subscriptions.add(faderSub);
      
      // Listen to button updates from the device
      var buttonSub = _controlService.onButtonUpdate.listen((data) {
        _handleButtonUpdate(data);
      });
      _subscriptions.add(buttonSub);
      
      // Also use FaderCommunication as backup
      var faderCommSub = _faderComm.onFaderUpdate.listen((data) {
        _handleFaderUpdate(data);
      });
      _subscriptions.add(faderCommSub);
      
      var buttonCommSub = _faderComm.onButtonUpdate.listen((data) {
        _handleButtonUpdate(data);
      });
      _subscriptions.add(buttonCommSub);
      
      debugPrint('ControllerBridge: All listeners registered');
    } catch (e) {
      debugPrint('ControllerBridge initialization error: $e');
    }
  }
  
  // Get or create a fader value notifier for a specific address/paramId
  ValueNotifier<double> getFaderNotifier(String address, String paramId) {
    final key = '${address.toLowerCase()}:${paramId.toLowerCase()}';
    if (!faderNotifiers.containsKey(key)) {
      faderNotifiers[key] = ValueNotifier<double>(0.5);
      debugPrint('ControllerBridge: Created fader notifier for $key');
    }
    return faderNotifiers[key]!;
  }
  
  // Get or create a button value notifier for a specific address/paramId
  ValueNotifier<bool> getButtonNotifier(String address, String paramId) {
    final key = '${address.toLowerCase()}:${paramId.toLowerCase()}';
    if (!buttonNotifiers.containsKey(key)) {
      buttonNotifiers[key] = ValueNotifier<bool>(false);
      debugPrint('ControllerBridge: Created button notifier for $key');
    }
    return buttonNotifiers[key]!;
  }
  
  // Handle fader update from any source
  void _handleFaderUpdate(Map<String, dynamic> data) {
    try {
      final address = (data['address'] as String).toLowerCase();
      final paramId = (data['paramId'] as String).toLowerCase();
      final value = data['value'] as double;
      
      final key = '$address:$paramId';
      
      debugPrint('ControllerBridge: Received fader update for $key = $value');
      
      if (faderNotifiers.containsKey(key)) {
        debugPrint('ControllerBridge: Updating fader notifier for $key');
        faderNotifiers[key]!.value = value;
      } else {
        // Create a new notifier if one doesn't exist
        faderNotifiers[key] = ValueNotifier<double>(value);
        debugPrint('ControllerBridge: Created new fader notifier for $key');
      }
    } catch (e) {
      debugPrint('ControllerBridge: Error handling fader update: $e');
    }
  }
  
  // Handle button update from any source
  void _handleButtonUpdate(Map<String, dynamic> data) {
    try {
      final address = (data['address'] as String).toLowerCase();
      final paramId = (data['paramId'] as String).toLowerCase();
      final state = data['state'] as bool? ?? data['value'] == 1;
      
      final key = '$address:$paramId';
      
      debugPrint('ControllerBridge: Received button update for $key = $state');
      
      if (buttonNotifiers.containsKey(key)) {
        debugPrint('ControllerBridge: Updating button notifier for $key');
        buttonNotifiers[key]!.value = state;
      } else {
        // Create a new notifier if one doesn't exist
        buttonNotifiers[key] = ValueNotifier<bool>(state);
        debugPrint('ControllerBridge: Created new button notifier for $key');
      }
    } catch (e) {
      debugPrint('ControllerBridge: Error handling button update: $e');
    }
  }
  
  // Send a fader value to the device
  void sendFaderValue(String address, String paramId, double value) {
    try {
      debugPrint('ControllerBridge: Sending fader value for $address:$paramId = $value');
      _controlService.setFaderValue(address, paramId, value);
      
      // Also update local notifier
      final key = '${address.toLowerCase()}:${paramId.toLowerCase()}';
      if (faderNotifiers.containsKey(key)) {
        faderNotifiers[key]!.value = value;
      }
    } catch (e) {
      debugPrint('ControllerBridge: Error sending fader value: $e');
    }
  }
  
  // Send a button state to the device
  void sendButtonState(String address, String paramId, bool state) {
    try {
      debugPrint('ControllerBridge: Sending button state for $address:$paramId = $state');
      _controlService.setButtonState(address, paramId, state);
      
      // Also update local notifier
      final key = '${address.toLowerCase()}:${paramId.toLowerCase()}';
      if (buttonNotifiers.containsKey(key)) {
        buttonNotifiers[key]!.value = state;
      }
    } catch (e) {
      debugPrint('ControllerBridge: Error sending button state: $e');
    }
  }
  
  // Dispose of resources
  void dispose() {
    try {
      for (var sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      
      // Clear notifiers
      for (var notifier in faderNotifiers.values) {
        notifier.dispose();
      }
      faderNotifiers.clear();
      
      for (var notifier in buttonNotifiers.values) {
        notifier.dispose();
      }
      buttonNotifiers.clear();
      
      debugPrint('ControllerBridge: Disposed');
    } catch (e) {
      debugPrint('ControllerBridge: Error disposing: $e');
    }
  }
}