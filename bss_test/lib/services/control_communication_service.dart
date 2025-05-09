// lib/services/control_communication_service.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'connection_service.dart';
import 'bss_protocol_service.dart';
import 'message_processor_service.dart';
import 'fader_communication.dart';
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
  final _faderComm = FaderCommunication(); // Store a direct reference to the singleton
  
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
  
  // Text controllers for address and param IDs
  TextEditingController? _faderHiQnetAddressController;
  TextEditingController? _faderParamIdController;
  TextEditingController? _buttonHiQnetAddressController;
  TextEditingController? _buttonParamIdController;
  TextEditingController? _meterHiQnetAddressController;
  TextEditingController? _meterParamIdController;
  TextEditingController? _sourceHiQnetAddressController;
  TextEditingController? _sourceParamIdController;
  
  // Initialize the service
  void _initialize() async {
    try {
      // Initialize the message processor
      await _messageProcessorService.initialize();
      
      Logger().log('Control communication service initializing...');
      
      // Listen for connection status changes
      _connectionService.onConnectionStatusChanged.listen((isConnected) {
        try {
          Logger().log('Connection status changed: $isConnected');
          
          // Update the connection state in the FaderCommunication service
          _faderComm.setConnectionState(isConnected);
          
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
        } catch (e) {
          Logger().log('Error handling connection state change: $e');
        }
      });
      
      // Listen for processed messages from the MessageProcessorService
      _messageProcessorService.onProcessedMessage.listen((message) {
        Logger().log('Received processed message: ${message.toString()}');
        _handleProcessedMessage(message);
      });
      
      // Listen for extracted messages from the connection service
      _connectionService.onMessageExtracted.listen((message) {
        // Forward to message processor
        Logger().log('Extracted message from socket, forwarding to processor');
        _messageProcessorService.processMessage(message);
      });
      
      // Listen for fader move events from UI components
      _faderComm.onFaderMoved.listen((data) {
        try {
          // When a fader is moved in the UI, send the update to the device
          if (_connectionService.isConnected) {
            Logger().log('UI Fader moved: ${data['address']} ${data['paramId']} ${data['value']}');
            setFaderValue(
              data['address'] as String,
              data['paramId'] as String,
              data['value'] as double,
            );
          }
        } catch (e) {
          Logger().log('Error handling fader moved event: $e');
        }
      });
      
      // Listen for button state change events from UI components
      _faderComm.onButtonStateChanged.listen((data) {
        try {
          // When a button state changes in the UI, send the update to the device
          if (_connectionService.isConnected) {
            Logger().log('UI Button state changed: ${data['address']} ${data['paramId']} ${data['state']}');
            setButtonState(
              data['address'] as String,
              data['paramId'] as String,
              data['state'] as bool,
            );
          }
        } catch (e) {
          Logger().log('Error handling button state changed event: $e');
        }
      });
      
      // Add a temporary direct listener to check communication
      _faderComm.addFaderUpdateListener((data) {
        Logger().log('Direct fader update listener received: ${data.toString()}');
      });
      
      _faderComm.addButtonUpdateListener((data) {
        Logger().log('Direct button update listener received: ${data.toString()}');
      });
      
      // Forward fader updates to the FaderCommunication service
      onFaderUpdate.listen((data) {
        try {
          Logger().log('Device fader update received, forwarding to UI: ${data.toString()}');
          _faderComm.updateFaderFromDevice(
            data['address'] as String,
            data['paramId'] as String,
            data['value'] as double,
          );
        } catch (e) {
          Logger().log('Error forwarding fader update: $e');
        }
      });
      
      // Forward button updates to the FaderCommunication service
      onButtonUpdate.listen((data) {
        try {
          Logger().log('Device button update received, forwarding to UI: ${data.toString()}');
          _faderComm.updateButtonFromDevice(
            data['address'] as String,
            data['paramId'] as String,
            data['state'] as bool? ?? data['value'] != 0, // Convert int to bool
          );
        } catch (e) {
          Logger().log('Error forwarding button update: $e');
        }
      });
      
      Logger().log('Control communication service initialized');
    } catch (e) {
      Logger().log('Error initializing control communication service: $e');
    }
  }
  
  // Get connection status
  bool get isConnected => _connectionService.isConnected;
  
  // Connect to the device
  Future<bool> connect({String? ip, int? port}) async {
    try {
      Logger().log('Connecting to ${ip ?? "default"} port ${port ?? "default"}...');
      return await _connectionService.connect(ip: ip, portNum: port);
    } catch (e) {
      Logger().log('Error connecting: $e');
      return false;
    }
  }
  
  // Disconnect from the device
  void disconnect() {
    try {
      Logger().log('Disconnecting from device...');
      _connectionService.disconnect();
    } catch (e) {
      Logger().log('Error disconnecting: $e');
    }
  }
  
  // Set the fader value
  Future<bool> setFaderValue(String addressHex, String paramIdHex, double normalizedValue) async {
    try {
      final address = _bssProtocolService.parseHiQnetAddress(addressHex);
      final paramId = int.parse(paramIdHex.replaceAll("0x", ""), radix: 16);
      final deviceValue = _bssProtocolService.normalizedToFaderValue(normalizedValue);
      
      Logger().log('Setting fader value: $addressHex, $paramIdHex, ${normalizedValue.toStringAsFixed(3)} (device value: $deviceValue)');
      Logger().log('Parsed address: ${address.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}, paramId: ${paramId.toRadixString(16)}');
      
      final command = _bssProtocolService.generateSetCommand(address, paramId, deviceValue);
      
      // Log the generated command
      final commandHex = command.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      Logger().log('Generated command: $commandHex');
      
      // Check connection status before sending
      if (!_connectionService.isConnected) {
        Logger().log('Cannot send command - not connected');
        return false;
      }
      
      final success = await _connectionService.sendData(command);
      
      if (success) {
        Logger().log('Set fader command sent successfully');
        
        // Also update local state through fader communication
        _faderComm.updateFaderFromDevice(addressHex, paramIdHex, normalizedValue);
        
        // Add a small delay then ping the socket to keep connection active
        Future.delayed(const Duration(milliseconds: 100), () {
          _connectionService.pingSocket();
        });
      } else {
        Logger().log('Failed to send fader command');
        
        // Try to reconnect and send again
        Future.delayed(const Duration(milliseconds: 500), () async {
          Logger().log('Attempting reconnect after failed command...');
          final reconnected = await _connectionService.reconnect();
          if (reconnected) {
            Logger().log('Reconnected - attempting to resend command');
            final resendSuccess = await _connectionService.sendData(command);
            Logger().log('Resend result: $resendSuccess');
          }
        });
      }
      
      return success;
    } catch (e) {
      Logger().log('Error setting fader value: $e');
      return false;
    }
  }
  
  // Subscribe to fader value
  Future<bool> subscribeFaderValue(String addressHex, String paramIdHex) async {
    try {
      final address = _bssProtocolService.parseHiQnetAddress(addressHex);
      final paramId = int.parse(paramIdHex.replaceAll("0x", ""), radix: 16);
      
      Logger().log('Subscribing to fader value: $addressHex, $paramIdHex');
      
      final command = _bssProtocolService.generateSubscribeCommand(address, paramId);
      final success = await _connectionService.sendData(command);
      
      if (success) {
        Logger().log('Subscribe fader command sent successfully');
      } else {
        Logger().log('Failed to send subscribe fader command');
      }
      
      return success;
    } catch (e) {
      Logger().log('Error subscribing to fader value: $e');
      return false;
    }
  }
  
  // Set the button state
  Future<bool> setButtonState(String addressHex, String paramIdHex, bool state) async {
    try {
      final address = _bssProtocolService.parseHiQnetAddress(addressHex);
      final paramId = int.parse(paramIdHex.replaceAll("0x", ""), radix: 16);
      final value = state ? 1 : 0;
      
      Logger().log('Setting button state: $addressHex, $paramIdHex, $state (value: $value)');
      
      final command = _bssProtocolService.generateSetCommand(address, paramId, value);
      final success = await _connectionService.sendData(command);
      
      if (success) {
        Logger().log('Set button command sent successfully');
        
        // Also update local state through fader communication
        _faderComm.updateButtonFromDevice(addressHex, paramIdHex, state);
      } else {
        Logger().log('Failed to send button command');
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
  
  // Subscribe to source selector
  Future<bool> subscribeSourceValue(String addressHex, String paramIdHex) async {
    try {
      final address = _bssProtocolService.parseHiQnetAddress(addressHex);
      final paramId = int.parse(paramIdHex.replaceAll("0x", ""), radix: 16);
      
      Logger().log('Subscribing to source value: $addressHex, $paramIdHex');
      
      final command = _bssProtocolService.generateSubscribeCommand(address, paramId);
      final success = await _connectionService.sendData(command);
      
      if (success) {
        Logger().log('Subscribe source command sent successfully');
      } else {
        Logger().log('Failed to send subscribe source command');
      }
      
      return success;
    } catch (e) {
      Logger().log('Error subscribing to source value: $e');
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
  
  // Set controller references for addresses
  void setFaderAddressControllers(TextEditingController addressCtrl, TextEditingController paramIdCtrl) {
    _faderHiQnetAddressController = addressCtrl;
    _faderParamIdController = paramIdCtrl;
  }

  void setButtonAddressControllers(TextEditingController addressCtrl, TextEditingController paramIdCtrl) {
    _buttonHiQnetAddressController = addressCtrl;
    _buttonParamIdController = paramIdCtrl;
  }

  void setMeterAddressControllers(TextEditingController addressCtrl, TextEditingController paramIdCtrl) {
    _meterHiQnetAddressController = addressCtrl;
    _meterParamIdController = paramIdCtrl;
  }

  void setSourceAddressControllers(TextEditingController addressCtrl, TextEditingController paramIdCtrl) {
    _sourceHiQnetAddressController = addressCtrl;
    _sourceParamIdController = paramIdCtrl;
  }
  
  // Subscribe to parameters
  Future<void> _subscribeToParameters() async {
    if (!_connectionService.isConnected) {
      Logger().log('Cannot subscribe to parameters - not connected');
      return;
    }
    
    try {
      Logger().log('Subscribing to parameters...');
      
      // Use a delay between subscription requests to avoid overwhelming the device
      // 1. Subscribe to fader parameter
      final faderAddress = _bssProtocolService.parseHiQnetAddress("0x2D6803000100");
      final faderParamId = 0; // 0x0
      final faderSubscribeCmd = _bssProtocolService.generateSubscribeCommand(faderAddress, faderParamId);
      await _connectionService.sendData(faderSubscribeCmd);
      Logger().log('Subscribed to fader: 0x2D6803000100, 0x0');
      
      await Future.delayed(const Duration(milliseconds: 100));
      
      // 2. Subscribe to button parameter
      final buttonAddress = _bssProtocolService.parseHiQnetAddress("0x2D6803000100");
      final buttonParamId = 1; // 0x1
      final buttonSubscribeCmd = _bssProtocolService.generateSubscribeCommand(buttonAddress, buttonParamId);
      await _connectionService.sendData(buttonSubscribeCmd);
      Logger().log('Subscribed to button: 0x2D6803000100, 0x1');
      
      await Future.delayed(const Duration(milliseconds: 100));
      
      // 3. Subscribe to meter parameter (with refresh rate)
      final meterAddress = _bssProtocolService.parseHiQnetAddress("0x2D6803000200");
      final meterParamId = 0; // 0x0
      final meterSubscribeCmd = _bssProtocolService.generateSubscribeCommand(meterAddress, meterParamId, 100);
      await _connectionService.sendData(meterSubscribeCmd);
      Logger().log('Subscribed to meter: 0x2D6803000200, 0x0, rate=100ms');
      
      await Future.delayed(const Duration(milliseconds: 100));
      
      // 4. Subscribe to source selector parameter
      // Using the UI controller values if available
      String sourceAddressText = "0x2D6803000101"; // Use the address from the UI
      int sourceParamId = 0; // 0x0
      
      if (_sourceHiQnetAddressController != null) {
        sourceAddressText = _sourceHiQnetAddressController!.text;
      }
      
      if (_sourceParamIdController != null) {
        try {
          sourceParamId = int.parse(_sourceParamIdController!.text.replaceAll("0x", ""), radix: 16);
        } catch (e) {
          Logger().log('Error parsing source param ID: $e, using default 0');
        }
      }
      
      final sourceAddress = _bssProtocolService.parseHiQnetAddress(sourceAddressText);
      final sourceSubscribeCmd = _bssProtocolService.generateSubscribeCommand(sourceAddress, sourceParamId);
      await _connectionService.sendData(sourceSubscribeCmd);
      Logger().log('Subscribed to source selector: $sourceAddressText, 0x$sourceParamId');
      
      Logger().log('All parameter subscriptions complete');
      
    } catch (e) {
      Logger().log('Error subscribing to parameters: $e');
    }
  }
  
  // Start meter refresh timer
  void _startMeterRefreshTimer(int meterRate) {
    // Cancel existing timer if any
    _meterRefreshTimer?.cancel();
    
    // Update the refresh rate
    _meterRefreshRate = meterRate;
    
    if (!_connectionService.isConnected) {
      Logger().log('Cannot start meter refresh - not connected');
      return;
    }
    
    try {
      // Get meter address and parameter ID
      final meterAddress = _bssProtocolService.parseHiQnetAddress("0x2D6803000200");
      final meterParamId = 0; // 0x0
      
      // First unsubscribe to ensure clean state
      final unsubCmd = _bssProtocolService.generateUnsubscribeCommand(meterAddress, meterParamId);
      _connectionService.sendData(unsubCmd);
      
      // Small delay before resubscribing
      Future.delayed(const Duration(milliseconds: 100), () async {
        // Subscribe with the new rate
        final meterSubscribeCmd = _bssProtocolService.generateSubscribeCommand(
          meterAddress, meterParamId, meterRate);
        await _connectionService.sendData(meterSubscribeCmd);
        
        Logger().log('Meter refresh rate updated to $meterRate ms');
        
        // Set up a periodic check to ensure meter updates are still coming
        _monitorMeterUpdates();
      });
    } catch (e) {
      Logger().log('Error setting meter refresh rate: $e');
    }
  }
  
  // Monitor meter updates and resubscribe if needed
  void _monitorMeterUpdates() {
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!_connectionService.isConnected) {
        timer.cancel();
        return;
      }
      
      int currentTime = DateTime.now().millisecondsSinceEpoch;
      // If we haven't received a meter update in more than 15 seconds
      if ((currentTime - _lastMeterUpdateTime) > 15000 && _autoRefreshMeter) {
        Logger().log('No meter updates received recently, resubscribing...');
        _startMeterRefreshTimer(_meterRefreshRate);
      }
    });
  }
  
  // Handle processed messages from the message processor
  void _handleProcessedMessage(Map<String, dynamic> message) {
    try {
      if (message['type'] == 'SET' || message['type'] == 'SET_PERCENT') {
        // Extract details
        List<int>? address = message['address'];
        int? paramId = message['paramId'];
        int? value = message['value'];
        
        // Safety check for null values
        if (address == null || paramId == null || value == null) {
          Logger().log('Invalid message format - missing required fields');
          return;
        }
        
        // Convert address to hex string for comparison
        String addressHex = '0x${address.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}';
        String paramIdHex = '0x${paramId.toRadixString(16)}';
        
        Logger().log('Processing message - Address: $addressHex, ParamId: $paramIdHex, Value: $value');
        
        // IMPORTANT FIX: Debug what we're receiving more clearly
        Logger().log('Address bytes: ${address.toString()}, Address hex: $addressHex');
        Logger().log('ParamId decimal: $paramId, ParamId hex: $paramIdHex');
        
        // We need to handle different parameter ID formats
        // Sometimes paramId is received as decimal but stored as hex, or vice versa
        String paramIdHexAlt = '0x${paramId.toRadixString(16).toUpperCase()}';
        String paramIdHexLower = paramIdHex.toLowerCase();
        String addressHexLower = addressHex.toLowerCase();
        
        Logger().log('Looking for control with address: $addressHexLower and paramId options: $paramIdHexLower or $paramIdHexAlt');
        
        // Determine control type based on address and paramId
        // First check if this is a fader message
        bool handledMessage = false;
        
        // Always try to convert fader values to see if it might be a fader message
        try {
          double normalizedValue = _bssProtocolService.faderValueToNormalized(value);
          Logger().log('Calculated normalized value: ${normalizedValue.toStringAsFixed(3)} from raw: $value');
          
          // Send update to fader stream
          _safeAddToStream(_faderUpdateController, {
            'address': addressHex,
            'paramId': paramIdHex,
            'value': normalizedValue,
            'raw': value
          });
          
          Logger().log('Sent fader update for $addressHex, $paramIdHex, value: $normalizedValue');
          handledMessage = true;
        } catch (e) {
          Logger().log('Error processing as fader value: $e');
        }
        
        // Also try as source selector if param ID is 0 or 0x0
        if (paramId == 0 || paramIdHex == '0x0') {
          try {
            // Check if value is within a reasonable range for a selector
            if (value >= 0 && value < 100) {
              _safeAddToStream(_sourceUpdateController, {
                'address': addressHex,
                'paramId': paramIdHex,
                'value': value,
                'raw': value
              });
              Logger().log('Sent source selector update for $addressHex, $paramIdHex, value: $value');
              handledMessage = true;
            }
          } catch (e) {
            Logger().log('Error processing as source selector: $e');
          }
        }
        
        // Try as button (paramId is typically 1)
        if (paramId == 1 || paramIdHex == '0x1') {
          try {
            _safeAddToStream(_buttonUpdateController, {
              'address': addressHex,
              'paramId': paramIdHex,
              'value': value,
              'state': value != 0,
              'raw': value
            });
            Logger().log('Sent button update for $addressHex, $paramIdHex, value: $value, state: ${value != 0}');
            handledMessage = true;
          } catch (e) {
            Logger().log('Error processing as button: $e');
          }
        }
        
        // If we couldn't identify the control type, log it but still try sending as a fader update
        if (!handledMessage) {
          Logger().log('Received message for unknown parameter ID: $paramId, address: $addressHex, value: $value');
          Logger().log('Trying to send as generic fader update in case it matches something');
          
          // Force send to all channels as a backup
          try {
            double normalizedValue = _bssProtocolService.faderValueToNormalized(value);
            
            // Send to fader stream
            _safeAddToStream(_faderUpdateController, {
              'address': addressHex,
              'paramId': paramIdHex,
              'value': normalizedValue,
              'raw': value
            });
            
            // Also try with alternative hex format
            _safeAddToStream(_faderUpdateController, {
              'address': addressHex,
              'paramId': paramIdHexAlt,
              'value': normalizedValue,
              'raw': value
            });
            
            Logger().log('Force-sent fader updates for $addressHex with both paramId formats');
          } catch (e) {
            Logger().log('Error in force-sending to fader: $e');
          }
        }
      } else if (message['type'] == 'ACK') {
        Logger().log('Received ACK');
      } else if (message['type'] == 'NAK') {
        Logger().log('Received NAK - command rejected');
      } else if (message['error'] != null) {
        Logger().log('Error in message processing: ${message['error']}');
      }
    } catch (e) {
      Logger().log('Error handling processed message: $e');
    }
  }
  
  // Helper method to safely add data to a stream without blocking
  void _safeAddToStream<T>(StreamController<T> controller, T data) {
    if (!controller.isClosed) {
      try {
        controller.add(data);
      } catch (e) {
        Logger().log('Error adding to stream: $e');
      }
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