import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'panel_loader_screen.dart';
import 'fader_communication.dart';  // Added import for fader communication

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BSS Controller',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const BSSControllerScreen(),
    );
  }
}

class BSSControllerScreen extends StatefulWidget {
  const BSSControllerScreen({super.key});

  @override
  State<BSSControllerScreen> createState() => _BSSControllerScreenState();
}

class _BSSControllerScreenState extends State<BSSControllerScreen> {
  // Connection state
  bool isConnecting = false;
  bool isConnected = false;
  Socket? socket;
  StreamSubscription<Uint8List>? socketSubscription;
  
  // Meter update control
  Timer? meterRefreshTimer;
  bool autoRefreshMeter = true;
  int meterRefreshRateValue = 100; // Default 100ms (10 updates per second)
  
  // Text controllers
  final ipAddressController = TextEditingController(text: "192.168.0.20");
  final portController = TextEditingController(text: "1023");
  
  // Control parameters
  final faderHiQnetAddressController = TextEditingController(text: "0x2D6803000100");
  final faderParamIdController = TextEditingController(text: "0x0");
  final buttonHiQnetAddressController = TextEditingController(text: "0x2D6803000100");
  final buttonParamIdController = TextEditingController(text: "0x1");
  final meterHiQnetAddressController = TextEditingController(text: "0x2D6803000200");
  final meterParamIdController = TextEditingController(text: "0x0");
  final sourceHiQnetAddressController = TextEditingController(text: "0x2D6803000300");
  final sourceParamIdController = TextEditingController(text: "0x0");
  
  // Control values
  double faderValue = 1.0; // 100% = max value
  bool buttonState = false;
  double meterValue = 0.0; // -80dB to +40dB, normalized to a 0.0-1.0 range
  int sourceValue = 0; // Multi-state parameter (0, 1, 2, etc.)
  int numSourceOptions = 8; // Number of source options available
  
  // Command strings (for display purposes)
  String faderMaxString = "02,88,2D,68,1B,83,00,01,00,00,00,01,86,A0,E8,03";
  String faderMinString = "02,88,2D,68,1B,83,00,01,00,00,00,FF,FB,B7,D7,AB,03";
  String buttonOnString = "02,88,2D,68,1B,83,00,01,00,00,01,00,00,00,01,CF,03";
  String buttonOffString = "02,88,2D,68,1B,83,00,01,00,00,01,00,00,00,00,CE,03";
  String meterSubscribeString = "02,89,2D,68,1B,83,00,02,00,00,00,A2,03";
  String sourceSelectString = "02,88,2D,68,1B,83,00,03,00,00,00,00,00,00,00,A5,03";
  
  // Buffer for incoming data - increased size for better throughput
  final List<int> _buffer = [];
  
  // Isolate for message processing
  Isolate? _messageProcessorIsolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  
  // Meter UI update optimization
  int _lastUIUpdateTime = 0;
  double _lastMeterValue = 0.0;
  final int _minUpdateInterval = 16; // ~60fps in milliseconds
  
  // Meter subscription tracking
  int _lastMeterSubscribeTime = 0;
  int _meterSubscribeCount = 0;
  
  // Log messages
  final List<String> _logMessages = [];
  final int _maxLogMessages = 20;

  // Added for fader communication
  final _faderCommunication = FaderCommunication();

  @override
  void initState() {
    super.initState();
    updateCommandStrings();
    _setupMessageProcessor();
    
    // Listen for fader events from panel viewer
    _faderCommunication.onFaderMoved.listen((data) {
      if (!isConnected || socket == null) return;
      
      try {
        final addressHex = data['address'] as String;
        final paramIdHex = data['paramId'] as String;
        final value = data['value'] as double;
        
        // Parse the address and parameter ID
        final address = parseHiQnetAddress(addressHex);
        final paramId = int.parse(paramIdHex.replaceAll("0x", ""), radix: 16);
        
        // Convert normalized value (0.0-1.0) to device value range
        final double maxValue = 0x0186A0.toDouble(); // 100000
        final double minValue = -280617.0; // 0xFFFBB7D7 as signed integer
        final int deviceValue = (minValue + value * (maxValue - minValue)).toInt();
        
        // Generate and send the command
        final command = generateSetCommand(address, paramId, deviceValue & 0xFFFFFFFF);
        sendCommand(command);
        
        addLog('Sent fader command from panel: $addressHex, $paramIdHex, $value');
      } catch (e) {
        addLog('Error sending fader command from panel: $e');
      }
    });
  }

  Future<void> _setupMessageProcessor() async {
    _receivePort = ReceivePort();
    _messageProcessorIsolate = await Isolate.spawn(
      _messageProcessorEntryPoint, 
      _receivePort!.sendPort
    );
    
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
      } else if (message is Map) {
        // Handle processed messages from isolate
        if (message['type'] == 'processedMessage') {
          handleProcessedMessage(message['data']);
        } else if (message['type'] == 'log') {
          addLog(message['message']);
        }
      }
    });
  }
  
  // Isolate entry point for message processing
  static void _messageProcessorEntryPoint(SendPort sendPort) {
    final ReceivePort receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    
    receivePort.listen((message) {
      if (message is List<int>) {
        // Process the message
        try {
          final processedMessage = _processMessageInIsolate(message);
          if (processedMessage != null) {
            sendPort.send({
              'type': 'processedMessage',
              'data': processedMessage
            });
          }
        } catch (e) {
          sendPort.send({
            'type': 'log',
            'message': 'Error processing message in isolate: $e'
          });
        }
      }
    });
  }
  
  static Map<String, dynamic>? _processMessageInIsolate(List<int> message) {
    // Remove start and end bytes
    if (message.length < 3) return null;
    
    List<int> body = message.sublist(1, message.length - 1);
    
    // Perform byte substitution reversal
    List<int> unsubstitutedBody = [];
    for (int i = 0; i < body.length; i++) {
      if (body[i] == 0x1B && i + 1 < body.length) {
        if (body[i + 1] == 0x82) {
          unsubstitutedBody.add(0x02);
          i++;
        } else if (body[i + 1] == 0x83) {
          unsubstitutedBody.add(0x03);
          i++;
        } else if (body[i + 1] == 0x86) {
          unsubstitutedBody.add(0x06);
          i++;
        } else if (body[i + 1] == 0x95) {
          unsubstitutedBody.add(0x15);
          i++;
        } else if (body[i + 1] == 0x9B) {
          unsubstitutedBody.add(0x1B);
          i++;
        } else {
          unsubstitutedBody.add(body[i]);
        }
      } else {
        unsubstitutedBody.add(body[i]);
      }
    }
    
    // Verify checksum
    if (unsubstitutedBody.length < 2) return null;
    
    int receivedChecksum = unsubstitutedBody.last;
    unsubstitutedBody.removeLast();
    
    int calculatedChecksum = 0;
    for (int b in unsubstitutedBody) {
      calculatedChecksum ^= b;
    }
    
    if (receivedChecksum != calculatedChecksum) {
      return {'error': 'Checksum mismatch'};
    }
    
    // Parse message
    if (unsubstitutedBody.isEmpty) return null;
    
    int msgType = unsubstitutedBody[0];
    if (msgType == 0x88) { // SET message
      // Extract address, paramId, and value
      if (unsubstitutedBody.length < 13) return null;
      
      List<int> address = unsubstitutedBody.sublist(1, 7); // 6 bytes address
      int paramId = (unsubstitutedBody[7] << 8) | unsubstitutedBody[8];
      int value = (unsubstitutedBody[9] << 24) | 
                 (unsubstitutedBody[10] << 16) | 
                 (unsubstitutedBody[11] << 8) | 
                  unsubstitutedBody[12];
      
      return {
        'type': 'SET',
        'address': address,
        'paramId': paramId,
        'value': value
      };
    } else if (msgType == 0x8D) { // SET_PERCENT message
      // Similar to SET but with percent value
      if (unsubstitutedBody.length < 13) return null;
      
      List<int> address = unsubstitutedBody.sublist(1, 7);
      int paramId = (unsubstitutedBody[7] << 8) | unsubstitutedBody[8];
      int value = (unsubstitutedBody[9] << 24) | 
                 (unsubstitutedBody[10] << 16) | 
                 (unsubstitutedBody[11] << 8) | 
                  unsubstitutedBody[12];
      
      return {
        'type': 'SET_PERCENT',
        'address': address,
        'paramId': paramId,
        'value': value
      };
    } else if (msgType == 0x06) { // ACK
      return {'type': 'ACK'};
    } else if (msgType == 0x15) { // NAK
      return {'type': 'NAK'};
    }
    
    return null;
  }

  @override
  void dispose() {
    disconnectFromDevice();
    socketSubscription?.cancel();
    meterRefreshTimer?.cancel();
    
    // Clean up text controllers
    ipAddressController.dispose();
    portController.dispose();
    faderHiQnetAddressController.dispose();
    faderParamIdController.dispose();
    buttonHiQnetAddressController.dispose();
    buttonParamIdController.dispose();
    meterHiQnetAddressController.dispose();
    meterParamIdController.dispose();
    sourceHiQnetAddressController.dispose();
    sourceParamIdController.dispose();
    
    // Clean up isolate
    _messageProcessorIsolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    
    super.dispose();
  }
  
  // Add a log message
  void addLog(String message) {
    setState(() {
      _logMessages.add("${DateTime.now().toString().split('.')[0]}: $message");
      if (_logMessages.length > _maxLogMessages) {
        _logMessages.removeAt(0);
      }
    });
    debugPrint(message);
  }

  // Connect to the BSS device with improved error handling
  Future<void> connectToDevice() async {
    if (isConnected || isConnecting) return;
    
    setState(() {
      isConnecting = true;
    });
    
    final ip = ipAddressController.text;
    final port = int.parse(portController.text);
    
    try {
      // Set a connection timeout
      socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      
      setState(() {
        isConnected = true;
        isConnecting = false;
        _buffer.clear(); // Clear buffer on new connection
        _lastUIUpdateTime = DateTime.now().millisecondsSinceEpoch; // Reset timer
        
        // Update fader communication state
        _faderCommunication.setConnectionState(true);
      });
      
      addLog('Connected to $ip:$port');
      
      // Configure socket for better throughput
      socket!.setOption(SocketOption.tcpNoDelay, true);
      
      // Listen for responses from the device with error handling
      socketSubscription = socket!.listen(
        (Uint8List data) {
          // Process incoming data
          handleIncomingData(data);
        },
        onError: (error) {
          addLog('Socket error: $error');
          disconnectFromDevice();
        },
        onDone: () {
          addLog('Socket closed');
          disconnectFromDevice();
        },
        cancelOnError: false,
      );
      
      // Subscribe to parameters after connection
      await subscribeToParameters();
      
      // Start automatic meter refresh timer if enabled
      if (autoRefreshMeter) {
        startMeterRefreshTimer(meterRate: meterRefreshRateValue);
      }
      
      // Start meter monitoring to auto-resubscribe if needed
      startMeterMonitoring();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected to device')),
        );
      }
    } catch (e) {
      setState(() {
        isConnecting = false;
      });
      
      addLog('Failed to connect: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect: $e')),
        );
      }
    }
  }

  // Disconnect from the BSS device
  void disconnectFromDevice() {
    if (!isConnected && !isConnecting) return;
    
    // Stop the meter refresh timer
    meterRefreshTimer?.cancel();
    meterRefreshTimer = null;
    
    // Unsubscribe from parameters before disconnecting
    try {
      unsubscribeFromParameters();
    } catch (e) {
      addLog('Error unsubscribing: $e');
    }
    
    socketSubscription?.cancel();
    socketSubscription = null;
    socket?.close();
    socket = null;
    
    setState(() {
      isConnected = false;
      isConnecting = false;
      
      // Update fader communication state
      _faderCommunication.setConnectionState(false);
    });
    
    addLog('Disconnected from device');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Disconnected from device')),
    );
  }

  // Start meter refresh with proper rate parameter - improved with protections
  void startMeterRefreshTimer({int meterRate = 100}) {
    // Cancel existing timer if any
    meterRefreshTimer?.cancel();
    
    int currentTime = DateTime.now().millisecondsSinceEpoch;
    
    // Prevent excessive resubscribing (no more than once per second)
    if (currentTime - _lastMeterSubscribeTime < 1000) {
      _meterSubscribeCount++;
      if (_meterSubscribeCount > 5) {
        addLog('Warning: Too many meter subscription attempts - throttling');
        Future.delayed(const Duration(seconds: 2), () {
          _meterSubscribeCount = 0;
          startMeterRefreshTimer(meterRate: meterRate);
        });
        return;
      }
    } else {
      _meterSubscribeCount = 0;
    }
    
    _lastMeterSubscribeTime = currentTime;
    
    // Subscribe to meter parameter with specified rate
    try {
      final meterAddress = parseHiQnetAddress(meterHiQnetAddressController.text);
      final meterParamId = int.parse(meterParamIdController.text.replaceAll("0x", ""), radix: 16);
      
      // First, unsubscribe from both formats to ensure clean state
      final unsubPercentCmd = generateUnsubscribePercentCommand(meterAddress, meterParamId);
      sendCommand(unsubPercentCmd);
      
      final unsubCmd = generateUnsubscribeCommand(meterAddress, meterParamId);
      sendCommand(unsubCmd);
      
      // Short delay before resubscribing
      Future.delayed(const Duration(milliseconds: 100), () {
        // Generate command with meter rate - use regular subscribe (0x89), not percent
        final command = generateSubscribeCommand(meterAddress, meterParamId, meterRate);
        sendCommand(command);
        
        // Update the displayed command string
        setState(() {
          meterSubscribeString = bytesToHexString(command);
          meterRefreshRateValue = meterRate;
        });
        
        addLog('Subscribed to meter parameter with rate: $meterRate ms');
      });
    } catch (e) {
      addLog('Error subscribing to meter: $e');
    }
  }
  
  // Add meter monitoring to detect if meter updates stop
  void startMeterMonitoring() {
    // Create a timer that periodically checks if meter values are being received
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!isConnected) {
        timer.cancel();
        return;
      }
      
      int currentTime = DateTime.now().millisecondsSinceEpoch;
      // If we haven't received a meter update in more than 5 seconds
      if ((currentTime - _lastUIUpdateTime) > 5000 && autoRefreshMeter) {
        addLog('No meter updates received recently, resubscribing...');
        
        // Resubscribe to meter
        startMeterRefreshTimer(meterRate: meterRefreshRateValue);
      }
    });
  }
  
  // Toggle auto refresh of meter
  void toggleAutoRefreshMeter(bool value) {
    setState(() {
      autoRefreshMeter = value;
    });
    
    if (autoRefreshMeter && isConnected) {
      // If turning on, ensure we're properly subscribed
      startMeterRefreshTimer(meterRate: meterRefreshRateValue);
    } else {
      // If turning off auto-refresh, unsubscribe from meter updates
      try {
        final meterAddress = parseHiQnetAddress(meterHiQnetAddressController.text);
        final meterParamId = int.parse(meterParamIdController.text.replaceAll("0x", ""), radix: 16);
        
        // First unsubscribe from percent format (in case it was subscribed that way)
        final unsubPercentCmd = generateUnsubscribePercentCommand(meterAddress, meterParamId);
        sendCommand(unsubPercentCmd);
        
        // Then unsubscribe from regular format
        final unsubCmd = generateUnsubscribeCommand(meterAddress, meterParamId);
        sendCommand(unsubCmd);
        
        addLog('Unsubscribed from meter parameter (both formats)');
      } catch (e) {
        addLog('Error unsubscribing from meter: $e');
      }
      
      meterRefreshTimer?.cancel();
      meterRefreshTimer = null;
    }
  }

  // Send a command to the BSS device with retry capability
  Future<bool> sendCommand(List<int> command, {int retries = 2}) async {
    if (!isConnected || socket == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to device')),
      );
      return false;
    }
    
    try {
      socket!.add(Uint8List.fromList(command));
      addLog('Sent command: ${bytesToHexString(command)}');
      return true;
    } catch (e) {
      addLog('Failed to send command: $e');
      
      if (retries > 0) {
        // Wait a moment and retry
        await Future.delayed(const Duration(milliseconds: 100));
        return sendCommand(command, retries: retries - 1);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send command: $e')),
        );
        return false;
      }
    }
  }

  // Update all command strings based on current parameters
  void updateCommandStrings() {
    try {
      // Parse fader HiQnet address and parameter ID
      final faderAddress = parseHiQnetAddress(faderHiQnetAddressController.text);
      final faderParamId = int.parse(faderParamIdController.text.replaceAll("0x", ""), radix: 16);
      
      // Parse button HiQnet address and parameter ID
      final buttonAddress = parseHiQnetAddress(buttonHiQnetAddressController.text);
      final buttonParamId = int.parse(buttonParamIdController.text.replaceAll("0x", ""), radix: 16);
      
      // Parse meter HiQnet address and parameter ID
      final meterAddress = parseHiQnetAddress(meterHiQnetAddressController.text);
      final meterParamId = int.parse(meterParamIdController.text.replaceAll("0x", ""), radix: 16);
      
      // Parse source HiQnet address and parameter ID
      final sourceAddress = parseHiQnetAddress(sourceHiQnetAddressController.text);
      final sourceParamId = int.parse(sourceParamIdController.text.replaceAll("0x", ""), radix: 16);
      
      // Generate command strings
      final faderMaxCmd = generateSetCommand(faderAddress, faderParamId, 0x0186A0);
      final faderMinCmd = generateSetCommand(faderAddress, faderParamId, 0xFFFBB7D7);
      final buttonOnCmd = generateSetCommand(buttonAddress, buttonParamId, 0x1);
      final buttonOffCmd = generateSetCommand(buttonAddress, buttonParamId, 0x0);
      final meterSubscribeCmd = generateSubscribeCommand(meterAddress, meterParamId, meterRefreshRateValue);
      final sourceSelectCmd = generateSetCommand(sourceAddress, sourceParamId, sourceValue);
      
      setState(() {
        faderMaxString = bytesToHexString(faderMaxCmd);
        faderMinString = bytesToHexString(faderMinCmd);
        buttonOnString = bytesToHexString(buttonOnCmd);
        buttonOffString = bytesToHexString(buttonOffCmd);
        meterSubscribeString = bytesToHexString(meterSubscribeCmd);
        sourceSelectString = bytesToHexString(sourceSelectCmd);
      });
      
      addLog('Command strings updated');
    } catch (e) {
      addLog('Error updating command strings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating command strings: $e')),
        );
      }
    }
  }

  // Parse HiQnet address string to list of bytes
  List<int> parseHiQnetAddress(String addressHex) {
    final hexString = addressHex.replaceAll("0x", "").replaceAll(" ", "");
    final bytes = <int>[];
    
    for (int i = 0; i < hexString.length; i += 2) {
      if (i + 2 <= hexString.length) {
        bytes.add(int.parse(hexString.substring(i, i + 2), radix: 16));
      }
    }
    
    return bytes;
  }

  // Generate a command with checksum and byte substitution - core messaging function
  List<int> generateCommand(int commandType, List<int> addressBytes, int paramId, [int value = 0, int meterRate = 0]) {
    // Command structure:
    // 0x02 (start) + commandType + Address + ParamID + Value (optional) + Checksum + 0x03 (end)
    
    final command = <int>[commandType]; // Command type (SET, SUBSCRIBE, etc.)
    
    // Add address bytes
    command.addAll(addressBytes);
    
    // Add parameter ID (2 bytes)
    command.add((paramId >> 8) & 0xFF); // High byte
    command.add(paramId & 0xFF);        // Low byte
    
    // Add value (4 bytes) - only for SET commands
    if (commandType == 0x88 || commandType == 0x8D || commandType == 0x90) {
      command.add((value >> 24) & 0xFF); // Byte 1 (MSB)
      command.add((value >> 16) & 0xFF); // Byte 2
      command.add((value >> 8) & 0xFF);  // Byte 3
      command.add(value & 0xFF);         // Byte 4 (LSB)
    } 
    // For meter parameter subscription, add meter rate
    else if ((commandType == 0x89 || commandType == 0x8E) && paramId == 0x0) {
      command.add(0x00);                    // Byte 1 (MSB)
      command.add(0x00);                    // Byte 2
      command.add((meterRate >> 8) & 0xFF); // Byte 3
      command.add(meterRate & 0xFF);        // Byte 4 (LSB)
    }
    // For other commands that need data payload
    else if (commandType == 0x89 || commandType == 0x8A || commandType == 0x8E || commandType == 0x8F) {
      command.add(0x00); // Byte 1 (MSB)
      command.add(0x00); // Byte 2
      command.add(0x00); // Byte 3
      command.add(0x00); // Byte 4 (LSB)
    }
    
    // Calculate checksum (XOR of all bytes in the command)
    int checksum = 0;
    for (int byte in command) {
      checksum ^= byte;
    }
    command.add(checksum);
    
    // Perform byte substitution
    final substitutedCommand = <int>[];
    for (int byte in command) {
      if (byte == 0x02) {
        substitutedCommand.addAll([0x1B, 0x82]);
      } else if (byte == 0x03) {
        substitutedCommand.addAll([0x1B, 0x83]);
      } else if (byte == 0x06) {
        substitutedCommand.addAll([0x1B, 0x86]);
      } else if (byte == 0x15) {
        substitutedCommand.addAll([0x1B, 0x95]);
      } else if (byte == 0x1B) {
        substitutedCommand.addAll([0x1B, 0x9B]);
      } else {
        substitutedCommand.add(byte);
      }
    }
    
    // Add start and end bytes
    return [0x02, ...substitutedCommand, 0x03];
  }
  
  // Generate a SET command (0x88)
  List<int> generateSetCommand(List<int> addressBytes, int paramId, int value) {
    return generateCommand(0x88, addressBytes, paramId, value);
  }
  
  // Generate a SET_PERCENT command (0x8D)
  List<int> generateSetPercentCommand(List<int> addressBytes, int paramId, int percentValue) {
    return generateCommand(0x8D, addressBytes, paramId, percentValue);
  }
  
  // Generate a SUBSCRIBE command (0x89) with meter rate option
  List<int> generateSubscribeCommand(List<int> addressBytes, int paramId, [int meterRate = 100]) {
    return generateCommand(0x89, addressBytes, paramId, 0, meterRate);
  }
  
  // Generate a SUBSCRIBE_PERCENT command (0x8E) with meter rate option
  List<int> generateSubscribePercentCommand(List<int> addressBytes, int paramId, [int meterRate = 100]) {
    return generateCommand(0x8E, addressBytes, paramId, 0, meterRate);
  }
  
  // Generate an UNSUBSCRIBE command (0x8A)
  List<int> generateUnsubscribeCommand(List<int> addressBytes, int paramId) {
    return generateCommand(0x8A, addressBytes, paramId);
  }
  
  // Generate an UNSUBSCRIBE_PERCENT command (0x8F)
  List<int> generateUnsubscribePercentCommand(List<int> addressBytes, int paramId) {
    return generateCommand(0x8F, addressBytes, paramId);
  }
  
  // Generate fader command based on current value
  List<int> generateFaderCommand() {
    try {
      final address = parseHiQnetAddress(faderHiQnetAddressController.text);
      final paramId = int.parse(faderParamIdController.text.replaceAll("0x", ""), radix: 16);
      
      // Calculate value based on fader position (0.0 to 1.0)
      // Max value = 0x0186A0 (100000), Min value = 0xFFFBB7D7 (-280617)
      final double maxValue = 0x0186A0.toDouble();
      final double minValue = -280617.0; // 0xFFFBB7D7 as signed integer
      final int value = (minValue + faderValue * (maxValue - minValue)).toInt();
      
      return generateSetCommand(address, paramId, value & 0xFFFFFFFF);
    } catch (e) {
      addLog('Error generating fader command: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating fader command: $e')),
        );
      }
      return [];
    }
  }

  // Subscribe to parameters with optimized approach
  Future<void> subscribeToParameters() async {
    try {
      // Subscribe to fader parameter
      final faderAddress = parseHiQnetAddress(faderHiQnetAddressController.text);
      final faderParamId = int.parse(faderParamIdController.text.replaceAll("0x", ""), radix: 16);
      final faderSubscribeCmd = generateSubscribeCommand(faderAddress, faderParamId);
      await sendCommand(faderSubscribeCmd);
      
      // Subscribe to button parameter
      final buttonAddress = parseHiQnetAddress(buttonHiQnetAddressController.text);
      final buttonParamId = int.parse(buttonParamIdController.text.replaceAll("0x", ""), radix: 16);
      final buttonSubscribeCmd = generateSubscribeCommand(buttonAddress, buttonParamId);
      await sendCommand(buttonSubscribeCmd);
      
      // Subscribe to meter parameter with specific refresh rate
      final meterAddress = parseHiQnetAddress(meterHiQnetAddressController.text);
      final meterParamId = int.parse(meterParamIdController.text.replaceAll("0x", ""), radix: 16);
      final meterSubscribeCmd = generateSubscribeCommand(meterAddress, meterParamId, meterRefreshRateValue);
      await sendCommand(meterSubscribeCmd);
      
      // Subscribe to source selector parameter
      final sourceAddress = parseHiQnetAddress(sourceHiQnetAddressController.text);
      final sourceParamId = int.parse(sourceParamIdController.text.replaceAll("0x", ""), radix: 16);
      final sourceSubscribeCmd = generateSubscribeCommand(sourceAddress, sourceParamId);
      await sendCommand(sourceSubscribeCmd);
      
      addLog('Subscribed to parameters');
    } catch (e) {
      addLog('Error subscribing to parameters: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error subscribing to parameters: $e')),
        );
      }
    }
  }
  
  // Unsubscribe from parameters
  Future<void> unsubscribeFromParameters() async {
    if (socket == null) return;
    
    try {
      // Unsubscribe from fader parameter
      final faderAddress = parseHiQnetAddress(faderHiQnetAddressController.text);
      final faderParamId = int.parse(faderParamIdController.text.replaceAll("0x", ""), radix: 16);
      final faderUnsubscribeCmd = generateUnsubscribeCommand(faderAddress, faderParamId);
      await sendCommand(faderUnsubscribeCmd);
      
      // Unsubscribe from button parameter
      final buttonAddress = parseHiQnetAddress(buttonHiQnetAddressController.text);
      final buttonParamId = int.parse(buttonParamIdController.text.replaceAll("0x", ""), radix: 16);
      final buttonUnsubscribeCmd = generateUnsubscribeCommand(buttonAddress, buttonParamId);
      await sendCommand(buttonUnsubscribeCmd);
      
      // Unsubscribe from meter parameter
      final meterAddress = parseHiQnetAddress(meterHiQnetAddressController.text);
      final meterParamId = int.parse(meterParamIdController.text.replaceAll("0x", ""), radix: 16);
      final meterUnsubscribeCmd = generateUnsubscribeCommand(meterAddress, meterParamId);
      await sendCommand(meterUnsubscribeCmd);
      
      // Unsubscribe from source selector parameter
      final sourceAddress = parseHiQnetAddress(sourceHiQnetAddressController.text);
      final sourceParamId = int.parse(sourceParamIdController.text.replaceAll("0x", ""), radix: 16);
      final sourceUnsubscribeCmd = generateUnsubscribeCommand(sourceAddress, sourceParamId);
      await sendCommand(sourceUnsubscribeCmd);
      
      addLog('Unsubscribed from parameters');
    } catch (e) {
      addLog('Error unsubscribing from parameters: $e');
    }
  }
  
  // Handle incoming data from the device - improved version
  void handleIncomingData(Uint8List newData) {
    // Add new data to buffer
    _buffer.addAll(newData);
    
    // Process complete messages
    while (_buffer.isNotEmpty) {
      // Look for start byte
      int startIndex = _buffer.indexOf(0x02);
      if (startIndex == -1) {
        _buffer.clear();
        return;
      }
      
      // Remove data before start byte
      if (startIndex > 0) {
        _buffer.removeRange(0, startIndex);
      }
      
      // Look for end byte
      int endIndex = _buffer.indexOf(0x03);
      if (endIndex == -1 || _buffer.length < endIndex + 1) {
        // Not a complete message yet, but keep buffer
        // Set a reasonable buffer size limit to prevent memory issues
        if (_buffer.length > 4096) {
          _buffer.removeRange(0, _buffer.length - 2048);
          addLog('Buffer size limited to prevent overflow');
        }
        return;
      }
      
      // Extract the message (including start and end bytes)
      List<int> message = _buffer.sublist(0, endIndex + 1);
      _buffer.removeRange(0, endIndex + 1);
      
      // Process the message using isolate if available, otherwise process directly
      if (_sendPort != null) {
        _sendPort!.send(message);
      } else {
        processMessage(message);
      }
    }
  }
  
  // Handle processed messages from isolate
  void handleProcessedMessage(Map<String, dynamic> processedMessage) {
    if (processedMessage['type'] == 'SET' || processedMessage['type'] == 'SET_PERCENT') {
      // Extract details
      List<int> address = processedMessage['address'];
      int paramId = processedMessage['paramId'];
      int value = processedMessage['value'];
      
      // Update UI based on message
      updateUIFromSetMessage(address, paramId, value);
    } else if (processedMessage['type'] == 'ACK') {
      // Handle acknowledgement
      // addLog('Received ACK');
    } else if (processedMessage['type'] == 'NAK') {
      addLog('Received NAK - command rejected');
    } else if (processedMessage['error'] != null) {
      addLog('Message processing error: ${processedMessage['error']}');
    }
  }
  
  // Process a complete message directly (used as fallback)
  void processMessage(List<int> message) {
    try {
      // Remove start and end bytes
      List<int> body = message.sublist(1, message.length - 1);
      
      // Perform byte substitution reversal
      List<int> unsubstitutedBody = [];
      for (int i = 0; i < body.length; i++) {
        if (body[i] == 0x1B && i + 1 < body.length) {
          if (body[i + 1] == 0x82) {
            unsubstitutedBody.add(0x02);
            i++;
          } else if (body[i + 1] == 0x83) {
            unsubstitutedBody.add(0x03);
            i++;
          } else if (body[i + 1] == 0x86) {
            unsubstitutedBody.add(0x06);
            i++;
          } else if (body[i + 1] == 0x95) {
            unsubstitutedBody.add(0x15);
            i++;
          } else if (body[i + 1] == 0x9B) {
            unsubstitutedBody.add(0x1B);
            i++;
          } else {
            unsubstitutedBody.add(body[i]);
          }
        } else {
          unsubstitutedBody.add(body[i]);
        }
      }
      
      // Verify checksum
      if (unsubstitutedBody.length < 2) return;
      
      int receivedChecksum = unsubstitutedBody.last;
      unsubstitutedBody.removeLast();
      
      int calculatedChecksum = 0;
      for (int b in unsubstitutedBody) {
        calculatedChecksum ^= b;
      }
      
      if (receivedChecksum != calculatedChecksum) {
        addLog('Checksum mismatch: $receivedChecksum != $calculatedChecksum');
        return;
      }
      
      // Parse message
      if (unsubstitutedBody.isEmpty) return;
      
      int msgType = unsubstitutedBody[0];
      if (msgType == 0x88) { // SET message
        processSetMessage(unsubstitutedBody);
      } else if (msgType == 0x8D) { // SET_PERCENT message
        processSetPercentMessage(unsubstitutedBody);
      } else if (msgType == 0x06) { // ACK
        // Received acknowledgement
        // addLog('Received ACK');
      } else if (msgType == 0x15) { // NAK
        addLog('Received NAK - command rejected');
      }
    } catch (e) {
      addLog('Error processing message: $e');
    }
  }
  
  // Process a SET message
  void processSetMessage(List<int> message) {
    try {
      // Verify message length
      // SET message structure: 0x88 + Address + ParamID + Value + Checksum
      if (message.length < 13) {
        addLog('SET message too short: ${bytesToHexString(message)}');
        return;
      }
      
      // Extract the address from the message
      List<int> address = message.sublist(1, 7); // 6 bytes address
      
      // Extract parameter ID (2 bytes)
      int paramId = (message[7] << 8) | message[8];
      
      // Extract value (4 bytes)
      int value = 0;
      value = (message[9] << 24) | (message[10] << 16) | (message[11] << 8) | message[12];
      
      // Log raw meter values for debugging purposes
      if (isMeterAddress(address, paramId)) {
        // Use a separate debug flag if needed to reduce log volume
        if (_logMessages.length < 5) { // Only log when buffer isn't too full
          final rawHex = '0x${value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
          addLog('Raw meter value: $rawHex (${bytesToHexString(message.sublist(9, 13))})');
        }
      }
      
      // Update UI based on the received message
      updateUIFromSetMessage(address, paramId, value);
    } catch (e) {
      addLog('Error processing SET message: $e');
    }
  }
  
  // Process a SET_PERCENT message
  void processSetPercentMessage(List<int> message) {
    try {
      // Verify message length
      // SET_PERCENT message structure: 0x8D + Address + ParamID + Value + Checksum
      if (message.length < 13) {
        addLog('SET_PERCENT message too short: ${bytesToHexString(message)}');
        return;
      }
      
      // Extract the address from the message
      List<int> address = message.sublist(1, 7); // 6 bytes address
      
      // Extract parameter ID (2 bytes)
      int paramId = (message[7] << 8) | message[8];
      
      // Extract value (4 bytes)
      int value = 0;
      value = (message[9] << 24) | (message[10] << 16) | (message[11] << 8) | message[12];
      
      // Convert to percentage (0-100) if needed before updating UI
      updateUIFromSetMessage(address, paramId, value);
    } catch (e) {
      addLog('Error processing SET_PERCENT message: $e');
    }
  }
  
  // Check if the address and param ID match the meter
  bool isMeterAddress(List<int> address, int paramId) {
    try {
      String addressHex = address.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
      String meterAddressHex = meterHiQnetAddressController.text.replaceAll("0x", "");
      int meterParamId = int.parse(meterParamIdController.text.replaceAll("0x", ""), radix: 16);
      
      return addressHex.toUpperCase() == meterAddressHex.toUpperCase() && paramId == meterParamId;
    } catch (e) {
      return false;
    }
  }
  
  // Update UI based on received SET message with throttling for meters
  void updateUIFromSetMessage(List<int> address, int paramId, int value) {
    try {
      // Convert address and parameters to hex strings for comparison
      String addressHex = address.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
      
      // Check if it matches fader parameter
      String faderAddressHex = faderHiQnetAddressController.text.replaceAll("0x", "");
      int faderParamId = int.parse(faderParamIdController.text.replaceAll("0x", ""), radix: 16);
      
      if (addressHex.toUpperCase() == faderAddressHex.toUpperCase() && paramId == faderParamId) {
        // Convert value to fader position (0.0 to 1.0)
        double maxValue = 0x0186A0.toDouble(); // 100000
        double minValue = -280617.0; // 0xFFFBB7D7 as signed integer
        
        // Handle signed values
        double signedValue = value.toDouble();
        if (value > 0x7FFFFFFF) {
          signedValue = -(0x100000000 - value).toDouble();
        }
        
        double normalizedValue = (signedValue - minValue) / (maxValue - minValue);
        normalizedValue = normalizedValue.clamp(0.0, 1.0);
        
        setState(() {
          faderValue = normalizedValue;
        });
        
        // Update panel faders with this address/paramId
        _faderCommunication.updateFaderFromDevice('0x$addressHex', '0x${paramId.toRadixString(16)}', normalizedValue);
        
        addLog('Updated fader value: ${normalizedValue.toStringAsFixed(3)}');
      }
      
      // Check if it matches button parameter
      String buttonAddressHex = buttonHiQnetAddressController.text.replaceAll("0x", "");
      int buttonParamId = int.parse(buttonParamIdController.text.replaceAll("0x", ""), radix: 16);
      
      if (addressHex.toUpperCase() == buttonAddressHex.toUpperCase() && paramId == buttonParamId) {
        setState(() {
          buttonState = value != 0;
        });
        
        addLog('Updated button state: ${value != 0}');
      }
      
      // Check if it matches meter parameter - with throttling
      String meterAddressHex = meterHiQnetAddressController.text.replaceAll("0x", "");
      int meterParamId = int.parse(meterParamIdController.text.replaceAll("0x", ""), radix: 16);
      
      if (addressHex.toUpperCase() == meterAddressHex.toUpperCase() && paramId == meterParamId) {
        // Convert value to meter position (0.0 to 1.0)
        // Meter parameters use values -800,000 (0% -80dB) to 400,000 (100% +40dB)
        const double minDb = -80.0; // -80dB
        const double maxDb = 40.0;  // +40dB
        
        // FIXED: Proper handling of signed values for meters
        double signedValue = value.toDouble();
        final rawHex = '0x${value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
        
        // Process correctly - even with SET_PERCENT messages
        if (value > 0x7FFFFFFF) {
          // Proper conversion from two's complement
          signedValue = -(0x100000000 - value).toDouble();
          
          // Log raw negative values - these should be common for low meter readings
          addLog('Raw negative meter value: $rawHex = $signedValue (converted from two\'s complement)');
        } else if (value > 0x400000) {
          // Any value over 40dB is suspicious - log it
          addLog('Suspicious meter value (>+40dB): $rawHex');
          
          // Filter out extreme values that cause the jumping behavior
          if (value >= 0x10000000) {
            addLog('Filtering extreme meter value: $rawHex');
            return; // Skip this update entirely
          }
        }
        
        // Different scale factor depending on if it's a SET or SET_PERCENT message
        double dbValue;
        if (value >= -800000 && value <= 400000) {
          // Normal SET message - scale factor is 10000
          dbValue = signedValue / 10000.0;
        } else if (value >= 0 && value <= 65535) {
          // Likely a SET_PERCENT message - scale to dB range
          dbValue = minDb + (signedValue / 65535.0) * (maxDb - minDb);
        } else {
          // Unknown format - log and use default scaling
          addLog('Unusual meter value format: $rawHex');
          dbValue = signedValue / 10000.0;
        }
        
        // Ensure we don't go outside our expected range
        dbValue = dbValue.clamp(minDb, maxDb);
        
        // Normalize to 0.0-1.0 range
        double normalizedValue = (dbValue - minDb) / (maxDb - minDb);
        
        // Throttle UI updates based on time and value change
        int currentTime = DateTime.now().millisecondsSinceEpoch;
        bool significantChange = (normalizedValue - _lastMeterValue).abs() > 0.01;
        
        if (significantChange || (currentTime - _lastUIUpdateTime) >= _minUpdateInterval) {
          setState(() {
            meterValue = normalizedValue;
          });
          
          _lastMeterValue = normalizedValue;
          _lastUIUpdateTime = currentTime;
          
          // Log meter values for troubleshooting with frequency control
          if (significantChange || (currentTime % 5000 < 50)) { // Log occasionally even without changes
            addLog('Meter: raw=$value, dB=${dbValue.toStringAsFixed(1)}, normalized=${normalizedValue.toStringAsFixed(3)}');
          }
        }
      }
      
      // Check if it matches source selector parameter
      String sourceAddressHex = sourceHiQnetAddressController.text.replaceAll("0x", "");
      int sourceParamId = int.parse(sourceParamIdController.text.replaceAll("0x", ""), radix: 16);
      
      if (addressHex.toUpperCase() == sourceAddressHex.toUpperCase() && paramId == sourceParamId) {
        // Source selector is a multi-state parameter (0, 1, 2, etc.)
        if (value >= 0 && value < numSourceOptions) {
          setState(() {
            sourceValue = value;
          });
          
          addLog('Updated source selection: $sourceValue');
        }
      }
    } catch (e) {
      addLog('Error updating UI from SET message: $e');
    }
  }
  
  // Convert dB value to a color
  Color getDbColor(double normalizedValue) {
    if (normalizedValue < 0.7) {
      return Colors.green;
    } else if (normalizedValue < 0.9) {
      return Colors.amber;
    } else {
      return Colors.red;
    }
  }
  
  // Convert bytes to hex string for display
  String bytesToHexString(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(',');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BSS Controller'),
        actions: [
          // Add a connection status indicator
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected ? Colors.green : 
                           isConnecting ? Colors.orange : Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isConnected ? 'Connected' : 
                  isConnecting ? 'Connecting...' : 'Disconnected'
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection settings
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Connection Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ipAddressController,
                            decoration: const InputDecoration(
                              labelText: 'IP Address',
                              border: OutlineInputBorder(),
                              hintText: '192.168.0.20',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: portController,
                            decoration: const InputDecoration(
                              labelText: 'Port',
                              border: OutlineInputBorder(),
                              hintText: '1023',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: isConnected || isConnecting ? null : connectToDevice,
                          child: const Text('Connect'),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: isConnected ? disconnectFromDevice : null,
                          child: const Text('Disconnect'),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const PanelLoaderScreen()),
                            );
                          },
                          child: const Text('Open Panel Loader'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Meter visualization
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Signal Meter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: meterHiQnetAddressController,
                            decoration: const InputDecoration(
                              labelText: 'HiQnet Address',
                              border: OutlineInputBorder(),
                              hintText: 'Example: 0x2D6803000200',
                            ),
                            onChanged: (_) => updateCommandStrings(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: meterParamIdController,
                            decoration: const InputDecoration(
                              labelText: 'Param ID',
                              border: OutlineInputBorder(),
                              hintText: 'Example: 0x0',
                            ),
                            onChanged: (_) => updateCommandStrings(),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Meter Refresh Rate slider
                    Row(
                      children: [
                        const Text('Meter Refresh Rate:'),
                        Expanded(
                          child: Slider(
                            value: meterRefreshRateValue.toDouble(),
                            min: 10,    // 10ms (very fast)
                            max: 1000,  // 1000ms (1 second)
                            divisions: 99,
                            label: '${meterRefreshRateValue}ms',
                            onChanged: (value) {
                              setState(() {
                                meterRefreshRateValue = value.round();
                              });
                            },
                            onChangeEnd: (value) {
                              // Resubscribe with new rate when slider is released
                              if (isConnected && autoRefreshMeter) {
                                startMeterRefreshTimer(meterRate: value.round());
                              }
                            },
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: Text('${meterRefreshRateValue}ms'),
                        ),
                      ],
                    ),
                    
                    Row(
                      children: [
                        const Text('Auto-refresh:'),
                        const SizedBox(width: 8),
                        Switch(
                          value: autoRefreshMeter,
                          onChanged: isConnected ? toggleAutoRefreshMeter : null,
                        ),
                        const SizedBox(width: 8),
                        Text(autoRefreshMeter ? 'ON' : 'OFF'),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Meter visualization - improved with smoother animation and peak hold
                    Container(
                      height: 90,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('-80dB', style: TextStyle(fontSize: 12)),
                                const Text('-40dB', style: TextStyle(fontSize: 12)),
                                const Text('0dB', style: TextStyle(fontSize: 12)),
                                const Text('+20dB', style: TextStyle(fontSize: 12)),
                                const Text('+40dB', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  // Calculate the width of the meter bar
                                  final meterWidth = constraints.maxWidth * meterValue;
                                  final dbValue = -80 + meterValue * 120;
                                  
                                  return Stack(
                                    children: [
                                      // Background with level markings
                                      Container(
                                        width: constraints.maxWidth,
                                        decoration: BoxDecoration(
                                          color: Colors.black12,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(width: constraints.maxWidth * (20/120), color: Colors.black.withAlpha(8)),
                                            Container(width: constraints.maxWidth * (20/120), color: Colors.black.withAlpha(15)),
                                            Container(width: constraints.maxWidth * (20/120), color: Colors.black.withAlpha(23)),
                                            Container(width: constraints.maxWidth * (20/120), color: Colors.black.withAlpha(31)),
                                            Container(width: constraints.maxWidth * (20/120), color: Colors.black.withAlpha(38)),
                                            Container(width: constraints.maxWidth * (20/120), color: Colors.black.withAlpha(46)),
                                          ],
                                        ),
                                      ),
                                      // Meter bar with animated transition
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 100),
                                        width: meterWidth,
                                        decoration: BoxDecoration(
                                          color: getDbColor(meterValue),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      // Current value text
                                      Positioned.fill(
                                        child: Center(
                                          child: Text(
                                            '${dbValue.toStringAsFixed(1)} dB',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: meterValue > 0.4 ? Colors.white : Colors.black,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                          // Numeric readout for additional verification
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                            child: Text(
                              'Rate: ${meterRefreshRateValue}ms   Value: ${(-80 + meterValue * 120).toStringAsFixed(1)}dB',
                              style: const TextStyle(fontSize: 10),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: isConnected ? () {
                            // Subscribe to the meter parameter
                            startMeterRefreshTimer(meterRate: meterRefreshRateValue);
                          } : null,
                          child: const Text('Refresh Meter Now'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Fader control
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Fader Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: faderHiQnetAddressController,
                            decoration: const InputDecoration(
                              labelText: 'HiQnet Address',
                              border: OutlineInputBorder(),
                              hintText: 'Example: 0x2D6803000100',
                            ),
                            onChanged: (_) => updateCommandStrings(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: faderParamIdController,
                            decoration: const InputDecoration(
                              labelText: 'Param ID',
                              border: OutlineInputBorder(),
                              hintText: 'Example: 0x0',
                            ),
                            onChanged: (_) => updateCommandStrings(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Fader Value:'),
                        Expanded(
                          child: Slider(
                            value: faderValue,
                            onChanged: (value) {
                              setState(() {
                                faderValue = value;
                              });
                            },
                            onChangeEnd: (value) {
                              if (isConnected) {
                                // Send new fader value to the device
                                sendCommand(generateFaderCommand());
                              }
                            },
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text('${(faderValue * 100).toInt()}%'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Button control
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Button Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: buttonHiQnetAddressController,
                            decoration: const InputDecoration(
                              labelText: 'HiQnet Address',
                              border: OutlineInputBorder(),
                              hintText: 'Example: 0x2D6803000100',
                            ),
                            onChanged: (_) => updateCommandStrings(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: buttonParamIdController,
                            decoration: const InputDecoration(
                              labelText: 'Param ID',
                              border: OutlineInputBorder(),
                              hintText: 'Example: 0x1',
                            ),
                            onChanged: (_) => updateCommandStrings(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Button State:'),
                        const SizedBox(width: 16),
                        Switch(
                          value: buttonState,
                          onChanged: (value) {
                            setState(() {
                              buttonState = value;
                            });
                            
                            if (isConnected) {
                              try {
                                final address = parseHiQnetAddress(buttonHiQnetAddressController.text);
                                final paramId = int.parse(buttonParamIdController.text.replaceAll("0x", ""), radix: 16);
                                
                                // Send button state command
                                final command = generateSetCommand(address, paramId, buttonState ? 1 : 0);
                                sendCommand(command);
                              } catch (e) {
                                addLog('Error sending button command: $e');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error sending button command: $e')),
                                );
                              }
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        Text(buttonState ? 'ON' : 'OFF'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Source Selector control
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Source Selector', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: sourceHiQnetAddressController,
                            decoration: const InputDecoration(
                              labelText: 'HiQnet Address',
                              border: OutlineInputBorder(),
                              hintText: 'Example: 0x2D6803000300',
                            ),
                            onChanged: (_) => updateCommandStrings(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: sourceParamIdController,
                            decoration: const InputDecoration(
                              labelText: 'Param ID',
                              border: OutlineInputBorder(),
                              hintText: 'Example: 0x0',
                            ),
                            onChanged: (_) => updateCommandStrings(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Source Input:'),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: sourceValue,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            ),
                            items: List.generate(numSourceOptions, (index) {
                              return DropdownMenuItem<int>(
                                value: index,
                                child: Text('Input ${index + 1}'),
                              );
                            }),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  sourceValue = value;
                                });
                                
                                if (isConnected) {
                                  try {
                                    final address = parseHiQnetAddress(sourceHiQnetAddressController.text);
                                    final paramId = int.parse(sourceParamIdController.text.replaceAll("0x", ""), radix: 16);
                                    
                                    // Send source selection command
                                    final command = generateSetCommand(address, paramId, sourceValue);
                                    sendCommand(command);
                                    
                                    // Update the command string display
                                    setState(() {
                                      sourceSelectString = bytesToHexString(command);
                                    });
                                  } catch (e) {
                                    addLog('Error sending source command: $e');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error sending source command: $e')),
                                    );
                                  }
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Command strings
            ExpansionTile(
              title: const Text('Command Strings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              initiallyExpanded: false,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Fader Max String:'),
                      SelectableText(faderMaxString),
                      const SizedBox(height: 8),
                      const Text('Fader Min String:'),
                      SelectableText(faderMinString),
                      const SizedBox(height: 8),
                      const Text('Button On:'),
                      SelectableText(buttonOnString),
                      const SizedBox(height: 8),
                      const Text('Button Off:'),
                      SelectableText(buttonOffString),
                      const SizedBox(height: 8),
                      const Text('Meter Subscribe:'),
                      SelectableText(meterSubscribeString),
                      const SizedBox(height: 8),
                      const Text('Source Select:'),
                      SelectableText(sourceSelectString),
                      
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: updateCommandStrings,
                        child: const Text('Update Command Strings'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Log section
            ExpansionTile(
              title: const Text('Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              initiallyExpanded: true,
              children: [
                Container(
                  height: 200,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _logMessages.isEmpty 
                    ? const Text(
                        'No logs yet. Connect to a device to see communications.',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      )
                    : ListView.builder(
                        itemCount: _logMessages.length,
                        itemBuilder: (context, index) {
                          return Text(
                            _logMessages[index],
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          );
                        },
                      ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _logMessages.clear();
                    });
                  },
                  child: const Text('Clear Log'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}