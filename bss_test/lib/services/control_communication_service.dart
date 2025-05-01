import 'dart:async';
import 'package:flutter/material.dart';
import 'connection_service.dart';
import 'bss_protocol_service.dart';
import 'message_processor_service.dart';
import '../utils/logger.dart';
import '../utils/hex_utils.dart';

/// Service for communicating with BSS device controls (faders, buttons, etc.)
class ControlCommunicationService {
  // Singleton instance
  static final ControlCommunicationService _instance = ControlCommunicationService._internal();
  factory ControlCommunicationService() => _instance;
  ControlCommunicationService._internal() {
    _initialize();
  }
  
  // Services
  final _connectionService = ConnectionService();
  final _bssProtocolService = BssProtocolService();
  final _messageProcessorService = MessageProcessorService();
  
  // Stream controllers for control values
  final _faderUpdateController = StreamController<Map<String, dynamic>>.broadcast();
  final _buttonUpdateController = StreamController<Map<String, dynamic>>.broadcast();
  final _meterUpdateController = StreamController<Map<String, dynamic>>.broadcast();
  final _sourceUpdateController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Public streams
  Stream<Map<String, dynamic>> get onFaderUpdate => _faderUpdateController.stream;
  Stream<Map<String, dynamic>> get onButtonUpdate => _buttonUpdateController.stream;
  Stream<Map<String, dynamic>> get onMeterUpdate => _meterUpdateController.stream;
  Stream<Map<String, dynamic>> get onSourceUpdate => _sourceUpdateController.stream;
  
  // Meter refresh timer
  Timer? _meterRefreshTimer;
  bool _autoRefreshMeter = true;
  int _meterRefreshRate = 100; // ms
  
  // Meter monitoring fields
  int _lastMeterUpdateTime = 0;
  double _lastMeterValue = 0.0;
  final int _minUpdateInterval = 16; // ~60fps in milliseconds
  
  // Initialize the service
  void _initialize() async {
    // Initialize the message processor
    await _messageProcessorService.initialize();
    
    // Listen for connection status changes
    _connectionService.onConnectionStatusChanged.listen((isConnected) {
      if (isConnected) {
        // Subscribe to parameters after connection
        _subscribeToParameters();
        
        // Start automatic meter refresh timer if enabled
        if (_autoRefreshMeter) {
          _startMeterRefreshTimer(_meterRefreshRate);
        }
      } else {
        // Cancel meter refresh timer
        _meterRefreshTimer?.cancel();
        _meterRefreshTimer = null;
      }
    });
    
    // Listen for processed messages
    _messageProcessorService.onProcessedMessage.listen((message) {
      _handleProcessedMessage(message);
    });
    
    // Listen for raw data from the connection service
    _connectionService.onDataReceived.listen((data) {
      // Forward to message processor
      _messageProcessorService.processMessage(data.toList());
    });
    
    Logger().log('Control communication service initialized');
  }
  
  // Get connection status
  bool get isConnected => _connectionService.isConnected;
  
  // Connect to the device
  Future<bool> connect({String? ip, int? port}) async {
    return await _connectionService.connect(ip: ip, portNum: port);
  }
  
  // Disconnect from the device
  void disconnect() {
    _connectionService.disconnect();
  }
  
  // Set the fader value
  Future<bool> setFaderValue(String addressHex, String paramIdHex, double normalizedValue) async {
    try {
      final address = _bssProtocolService.parseHiQnetAddress(addressHex);
      final paramId = int.parse(paramIdHex.replaceAll("0x", ""), radix: 16);
      final deviceValue = _bssProtocolService.normalizedToFaderValue(normalizedValue);
      
      final command = _bssProtocolService.generateSetCommand(address, paramId, deviceValue);
      final success = await _connectionService.sendData(command);
      
      if (success) {
        Logger().log('Set fader value: $addressHex, $paramIdHex, ${normalizedValue.toStringAsFixed(3)}');
      }
      
      return success;
    } catch (e) {
      Logger().log('Error setting fader value: $e');
      return false;
    }
  }
  
  // Set the button state
  Future<bool> setButtonState(String addressHex, String paramIdHex, bool state) async {
    try {
      final address = _bssProtocolService.parseHiQnetAddress(addressHex);
      final paramId = int.parse(paramIdHex.replaceAll("0x", ""), radix: 16);
      final value = state ? 1 : 0;
      
      final command = _bssProtocolService.generateSetCommand(address, paramId, value);
      final success = await _connectionService.sendData(command);
      
      if (success) {
        Logger().log('Set button state: $addressHex, $paramIdHex, $state');
      }
      
      return success;
    } catch (e) {
      Logger().log('Error setting button state: $e');
      return false;
    }
  }
  
  // Set the source selector value
  Future<bool> setSourceValue(String addressHex, String paramIdHex, int value) async {
    try {
      final address = _bssProtocolService.parseHiQnetAddress(addressHex);
      final paramId = int.parse(paramIdHex.replaceAll("0x", ""), radix: 16);
      
      final command = _bssProtocolService.generateSetCommand(address, paramId, value);
      final success = await _connectionService.sendData(command);
      
      if (success) {
        Logger().log('Set source value: $addressHex, $paramIdHex, $value');
      }
      
      return success;
    } catch (e) {
      Logger().log('Error setting source value: $e');
      return false;
    }
  }
  
  // Set meter refresh rate
  void setMeterRefreshRate(int refreshRate) {
    _meterRefreshRate = refreshRate;
    if (_autoRefreshMeter && _connectionService.isConnected) {
      _startMeterRefreshTimer(refreshRate);
    }
  }
  
  // Set auto refresh meter flag
  void setAutoRefreshMeter(bool autoRefresh) {
    _autoRefreshMeter = autoRefresh;
    
    if (_autoRefreshMeter && _connectionService.isConnected) {
      // Start the meter refresh timer
      _startMeterRefreshTimer(_meterRefreshRate);
    } else if (!_autoRefreshMeter) {
      // Cancel the timer
      _meterRefreshTimer?.cancel();
      _meterRefreshTimer = null;
    }
  }
  
  // Subscribe to parameters
  Future<void> _subscribeToParameters() async {
    // Note: This would normally use configured addresses for each parameter
    // Here's a stub implementation that would need to be customized
    Logger().log('Subscribing to parameters');
  }
  
  // Start meter refresh timer
  void _startMeterRefreshTimer(int meterRate) {
    // Cancel existing timer if any
    _meterRefreshTimer?.cancel();
    
    // Subscribe to meter parameter with specified rate
    // Note: This implementation is simplified - you'd need to insert actual meter address/paramId
    Logger().log('Started meter refresh timer with rate: $meterRate ms');
  }
  
  // Handle processed messages from the message processor
  void _handleProcessedMessage(Map<String, dynamic> message) {
    if (message['type'] == 'SET' || message['type'] == 'SET_PERCENT') {
      // Extract details
      List<int> address = message['address'];
      int paramId = message['paramId'];
      int value = message['value'];
      
      // Convert address to hex string for comparison
      String addressHex = '0x${address.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}';
      String paramIdHex = '0x${paramId.toRadixString(16)}';
      
      // Determine the control type based on address/paramId and update appropriate streams
      // This is a simplified implementation - actual implementation would check against configured addresses
      
      // For example, if this is a fader update:
      _faderUpdateController.add({
        'address': addressHex,
        'paramId': paramIdHex,
        'value': _bssProtocolService.faderValueToNormalized(value),
        'raw': value
      });
      
      // Similar handling would be done for buttons, meters, and source selectors
    }
  }
  
  // Clean up resources
  void dispose() {
    _meterRefreshTimer?.cancel();
    _faderUpdateController.close();
    _buttonUpdateController.close();
    _meterUpdateController.close();
    _sourceUpdateController.close();
  }
}