// lib/services/global_state.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'control_communication_service.dart';
import 'fader_communication.dart';

// Simple global state manager for control values
class GlobalState extends ChangeNotifier {
  // Singleton instance
  static final GlobalState _instance = GlobalState._internal();
  factory GlobalState() => _instance;
  
  // Services
  final _controlService = ControlCommunicationService();
  final _faderComm = FaderCommunication();
  
  // Timer for periodic UI refresh
  Timer? _refreshTimer;
  
  // State maps - key format is "$address:$paramId"
  final Map<String, double> _faderValues = {};
  final Map<String, bool> _buttonStates = {};
  
  // Stream controllers for value changes
  final _faderValueChangedController = StreamController<Map<String, dynamic>>.broadcast();
  final _buttonStateChangedController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionChangedController = StreamController<bool>.broadcast();
  
  // Stream getters
  Stream<Map<String, dynamic>> get onFaderValueChanged => _faderValueChangedController.stream;
  Stream<Map<String, dynamic>> get onButtonStateChanged => _buttonStateChangedController.stream;
  Stream<bool> get onConnectionChanged => _connectionChangedController.stream;
  
  // Connection state
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  // Debug counter
  int _updateCount = 0;
  
  // Private constructor
  GlobalState._internal() {
    debugPrint('GlobalState: Initializing with direct connections');
    _initializeListeners();
    
    // Start a periodic refresh timer to force UI updates
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      notifyListeners();
    });
  }
  
  // Initialize listeners
  void _initializeListeners() {
    // Listen for connection state changes
    _faderComm.onConnectionChanged.listen((connected) {
      _isConnected = connected;
      debugPrint('GlobalState: Connection state changed to $_isConnected');
      notifyListeners();
      _connectionChangedController.add(connected);
    });
    
    // Listen for fader updates
    _controlService.onFaderUpdate.listen((data) {
      _updateCount++;
      final address = data['address'] as String;
      final paramId = data['paramId'] as String;
      final value = data['value'] as double;
      
      final key = '${address.toLowerCase()}:${paramId.toLowerCase()}';
      _faderValues[key] = value;
      
      debugPrint('GlobalState: Received fader update #$_updateCount for $key = $value');
      notifyListeners();
      
      // Also notify via stream
      _faderValueChangedController.add({
        'address': address,
        'paramId': paramId,
        'value': value
      });
    });
    
    // Also listen for fader updates from FaderCommunication
    _faderComm.onFaderUpdate.listen((data) {
      _updateCount++;
      final address = data['address'] as String;
      final paramId = data['paramId'] as String;
      final value = data['value'] as double;
      
      final key = '${address.toLowerCase()}:${paramId.toLowerCase()}';
      _faderValues[key] = value;
      
      debugPrint('GlobalState: Received fader update from FaderComm #$_updateCount for $key = $value');
      notifyListeners();
      
      // Also notify via stream
      _faderValueChangedController.add({
        'address': address,
        'paramId': paramId,
        'value': value
      });
    });
    
    // Listen for button updates
    _controlService.onButtonUpdate.listen((data) {
      _updateCount++;
      final address = data['address'] as String;
      final paramId = data['paramId'] as String;
      final value = data['value'] ?? 0;
      final state = value != 0; // Convert to boolean
      
      final key = '${address.toLowerCase()}:${paramId.toLowerCase()}';
      _buttonStates[key] = state;
      
      debugPrint('GlobalState: Received button update #$_updateCount for $key = $state');
      notifyListeners();
      
      // Also notify via stream
      _buttonStateChangedController.add({
        'address': address,
        'paramId': paramId,
        'state': state
      });
    });
    
    // Also listen for button updates from FaderCommunication
    _faderComm.onButtonUpdate.listen((data) {
      _updateCount++;
      final address = data['address'] as String;
      final paramId = data['paramId'] as String;
      final state = data['state'] as bool;
      
      final key = '${address.toLowerCase()}:${paramId.toLowerCase()}';
      _buttonStates[key] = state;
      
      debugPrint('GlobalState: Received button update from FaderComm #$_updateCount for $key = $state');
      notifyListeners();
      
      // Also notify via stream
      _buttonStateChangedController.add({
        'address': address,
        'paramId': paramId,
        'state': state
      });
    });
    
    debugPrint('GlobalState: All listeners initialized');
  }
  
  // Get fader value
  double getFaderValue(String address, String paramId) {
    final key = '${address.toLowerCase()}:${paramId.toLowerCase()}';
    return _faderValues[key] ?? 0.5;
  }
  
  // Get button state
  bool getButtonState(String address, String paramId) {
    final key = '${address.toLowerCase()}:${paramId.toLowerCase()}';
    return _buttonStates[key] ?? false;
  }
  
  // Set fader value - both updates local state and sends to device
  void setFaderValue(String address, String paramId, double value) {
    final key = '${address.toLowerCase()}:${paramId.toLowerCase()}';
    _faderValues[key] = value;
    
    // Send to device
    _controlService.setFaderValue(address, paramId, value);
    
    debugPrint('GlobalState: Set fader value for $key = $value');
    notifyListeners();
    
    // Also notify via stream
    _faderValueChangedController.add({
      'address': address,
      'paramId': paramId,
      'value': value
    });
  }
  
  // Set button state - both updates local state and sends to device
  void setButtonState(String address, String paramId, bool state) {
    final key = '${address.toLowerCase()}:${paramId.toLowerCase()}';
    _buttonStates[key] = state;
    
    // Send to device
    _controlService.setButtonState(address, paramId, state);
    
    debugPrint('GlobalState: Set button state for $key = $state');
    notifyListeners();
    
    // Also notify via stream
    _buttonStateChangedController.add({
      'address': address,
      'paramId': paramId,
      'state': state
    });
  }
  
  // Force manual update from device for testing
  void refreshFromDevice() {
    debugPrint('GlobalState: Forcing refresh from device');
    // This would trigger a specific refresh if needed
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    _faderValueChangedController.close();
    _buttonStateChangedController.close();
    _connectionChangedController.close();
    super.dispose();
  }
}