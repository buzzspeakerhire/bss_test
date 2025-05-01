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
      
      // Create fader communication instance
      final faderComm = FaderCommunication();
      
      // Listen for connection status changes
      _connectionService.onConnectionStatusChanged.listen((isConnected) {
        try {
          // Update the connection state in the FaderCommunication service
          faderComm.setConnectionState(isConnected);
          
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
        _handleProcessedMessage(message);
      });
      
      // Listen for extracted messages from the connection service
      _connectionService.onMessageExtracted.listen((message) {
        // Forward to message processor
        _messageProcessorService.processMessage(message);
      });
      
      // Listen for fader move events from UI components
      faderComm.onFaderMoved.listen((data) {
        try {
          // When a fader is moved in the UI, send the update to the device
          if (isConnected) {
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
      if (faderComm is FaderCommunication) { // Check if it has button support
        try {
          faderComm.onButtonStateChanged.listen((data) {
            // When a button state changes in the UI, send the update to the device
            if (isConnected) {
              setButtonState(
                data['address'] as String,
                data['paramId'] as String,
                data['state'] as bool,
              );
            }
          });
        } catch (e) {
          Logger().log('Error setting up button state changed listener: $e');
        }
      }
      
      // Forward fader updates to the FaderCommunication service
      onFaderUpdate.listen((data) {
        try {
          faderComm.updateFaderFromDevice(
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
          faderComm.updateButtonFromDevice(
            data['address'] as String,
            data['paramId'] as String,
            data['value'] != 0, // Convert int to bool
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
      return await _connectionService.connect(ip: ip, portNum: port);
    } catch (e) {
      Logger().log('Error connecting: $e');
      return false;
    }
  }
  
  // Disconnect from the device
  void disconnect() {
    try {
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
      
      // Use simpler, hardcoded addresses for stability
      // 1. Subscribe to fader parameter
      final faderAddress = _bssProtocolService.parseHiQnetAddress("0x2D6803000100");
      final faderParamId = 0; // 0x0
      final faderSubscribeCmd = _bssProtocolService.generateSubscribeCommand(faderAddress, faderParamId);
      await _connectionService.sendData(faderSubscribeCmd);
      Logger().log('Subscribed to fader: 0x2D6803000100, 0x0');
      
      // 2. Subscribe to button parameter
      final buttonAddress = _bssProtocolService.parseHiQnetAddress("0x2D6803000100");
      final buttonParamId = 1; // 0x1
      final buttonSubscribeCmd = _bssProtocolService.generateSubscribeCommand(buttonAddress, buttonParamId);
      await _connectionService.sendData(buttonSubscribeCmd);
      Logger().log('Subscribed to button: 0x2D6803000100, 0x1');
      
      // 3. Subscribe to meter parameter (with refresh rate)
      final meterAddress = _bssProtocolService.parseHiQnetAddress("0x2D6803000200");
      final meterParamId = 0; // 0x0
      final meterSubscribeCmd = _bssProtocolService.generateSubscribeCommand(meterAddress, meterParamId, 100);
      await _connectionService.sendData(meterSubscribeCmd);
      Logger().log('Subscribed to meter: 0x2D6803000200, 0x0, rate=100ms');
      
      // 4. Subscribe to source selector parameter
      final sourceAddress = _bssProtocolService.parseHiQnetAddress("0x2D6803000300");
      final sourceParamId = 0; // 0x0
      final sourceSubscribeCmd = _bssProtocolService.generateSubscribeCommand(sourceAddress, sourceParamId);
      await _connectionService.sendData(sourceSubscribeCmd);
      Logger().log('Subscribed to source selector: 0x2D6803000300, 0x0');
      
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
        
        // Simplify control type detection to improve stability
        // Use paramId to determine control type
        if (paramId == 0) {
          // This is likely a fader or meter
          // Determine based on address pattern
          if (addressHex.toLowerCase().contains("0200")) {
            // This is likely a meter
            _lastMeterUpdateTime = DateTime.now().millisecondsSinceEpoch;
            
            // Convert value to normalized meter level (0.0-1.0)
            double dbValue = value / 10000.0; // Convert from device value to dB
            double normalizedValue = _bssProtocolService.dbToNormalizedValue(dbValue);
            
            // Clamp to valid range
            normalizedValue = normalizedValue.clamp(0.0, 1.0);
            
            _safeAddToStream(_meterUpdateController, {
              'address': addressHex,
              'paramId': paramIdHex,
              'value': normalizedValue,
              'db': dbValue,
              'raw': value
            });
            
            // Only log occasionally to avoid spam
            if (DateTime.now().second % 5 == 0) {
              Logger().log('Updated meter value: ${normalizedValue.toStringAsFixed(3)}, ${dbValue.toStringAsFixed(1)}dB');
            }
          } else if (addressHex.toLowerCase().contains("0300")) {
            // This is likely a source selector
            _safeAddToStream(_sourceUpdateController, {
              'address': addressHex,
              'paramId': paramIdHex,
              'value': value,
              'raw': value
            });
            Logger().log('Updated source selection: $value');
          } else {
            // This is likely a fader
            final normalizedValue = _bssProtocolService.faderValueToNormalized(value);
            _safeAddToStream(_faderUpdateController, {
              'address': addressHex,
              'paramId': paramIdHex,
              'value': normalizedValue,
              'raw': value
            });
            Logger().log('Updated fader value: ${normalizedValue.toStringAsFixed(3)}');
          }
        } 
        else if (paramId == 1) {
          // This is likely a button
          _safeAddToStream(_buttonUpdateController, {
            'address': addressHex,
            'paramId': paramIdHex,
            'value': value, // Button state (0 or 1)
            'raw': value
          });
          Logger().log('Updated button state: ${value != 0}');
        }
        else {
          // Unknown parameter ID - log it for debugging
          Logger().log('Received message for unknown parameter ID: $paramId, address: $addressHex, value: $value');
        }
      } else if (message['type'] == 'ACK') {
        // Optional: Handle acknowledgement if needed
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