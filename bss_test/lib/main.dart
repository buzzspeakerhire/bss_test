import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool isConnected = false;
  Socket? socket;
  StreamSubscription<Uint8List>? socketSubscription;
  
  // Automatic meter refresh
  Timer? meterRefreshTimer;
  bool autoRefreshMeter = true;
  
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
  
  // Control values
  double faderValue = 1.0; // 100% = max value
  bool buttonState = false;
  double meterValue = 0.0; // -80dB to +40dB, normalized to 0.0-1.0
  
  // Command strings
  String faderMaxString = "02,88,2D,68,1B,83,00,01,00,00,00,01,86,A0,E8,03";
  String faderMinString = "02,88,2D,68,1B,83,00,01,00,00,00,FF,FB,B7,D7,AB,03";
  String buttonOnString = "02,88,2D,68,1B,83,00,01,00,00,01,00,00,00,01,CF,03";
  String buttonOffString = "02,88,2D,68,1B,83,00,01,00,00,01,00,00,00,00,CE,03";
  String meterSubscribeString = "02,89,2D,68,1B,83,00,02,00,00,00,A2,03";
  
  // Buffer for incoming data
  final List<int> _buffer = [];
  
  // Log messages
  final List<String> _logMessages = [];
  final int _maxLogMessages = 10;

  @override
  void initState() {
    super.initState();
    updateCommandStrings();
  }

  @override
  void dispose() {
    disconnectFromDevice();
    socketSubscription?.cancel();
    meterRefreshTimer?.cancel();
    ipAddressController.dispose();
    portController.dispose();
    faderHiQnetAddressController.dispose();
    faderParamIdController.dispose();
    buttonHiQnetAddressController.dispose();
    buttonParamIdController.dispose();
    meterHiQnetAddressController.dispose();
    meterParamIdController.dispose();
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

  // Connect to the BSS device
  Future<void> connectToDevice() async {
    if (isConnected) return;
    
    final ip = ipAddressController.text;
    final port = int.parse(portController.text);
    
    try {
      socket = await Socket.connect(ip, port);
      setState(() {
        isConnected = true;
        _buffer.clear(); // Clear buffer on new connection
      });
      
      addLog('Connected to $ip:$port');
      
      // Listen for responses from the device
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
      );
      
      // Subscribe to parameters (request current values)
      subscribeToParameters();
      
      // Start automatic meter refresh timer
      if (autoRefreshMeter) {
        startMeterRefreshTimer();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected to device')),
        );
      }
    } catch (e) {
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
    if (!isConnected) return;
    
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
    });
    
    addLog('Disconnected from device');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Disconnected from device')),
    );
  }

  // Start timer for automatic meter refresh
  void startMeterRefreshTimer() {
    // Cancel existing timer if any
    meterRefreshTimer?.cancel();
    
    // Create a new timer that fires every 5 seconds
    meterRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (isConnected) {
        try {
          // Re-subscribe to meter parameter to ensure updates continue
          final meterAddress = parseHiQnetAddress(meterHiQnetAddressController.text);
          final meterParamId = int.parse(meterParamIdController.text.replaceAll("0x", ""), radix: 16);
          final command = generateSubscribeCommand(meterAddress, meterParamId);
          sendCommand(command);
          addLog('Auto-refresh: re-subscribed to meter parameter');
        } catch (e) {
          // Silent fail on auto-refresh, don't bother the user unless they requested it
          addLog('Error in auto-refresh meter: $e');
        }
      } else {
        // Stop the timer if disconnected
        timer.cancel();
      }
    });
  }
  
  // Toggle auto refresh of meter
  void toggleAutoRefreshMeter(bool value) {
    setState(() {
      autoRefreshMeter = value;
    });
    
    if (autoRefreshMeter && isConnected) {
      startMeterRefreshTimer();
    } else {
      meterRefreshTimer?.cancel();
      meterRefreshTimer = null;
    }
  }

  // Send a command to the BSS device
  void sendCommand(List<int> command) {
    if (!isConnected || socket == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to device')),
      );
      return;
    }
    
    try {
      socket!.add(Uint8List.fromList(command));
      addLog('Sent command: ${bytesToHexString(command)}');
    } catch (e) {
      addLog('Failed to send command: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send command: $e')),
      );
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
      
      // Generate command strings
      final faderMaxCmd = generateSetCommand(faderAddress, faderParamId, 0x0186A0);
      final faderMinCmd = generateSetCommand(faderAddress, faderParamId, 0xFFFBB7D7);
      final buttonOnCmd = generateSetCommand(buttonAddress, buttonParamId, 0x1);
      final buttonOffCmd = generateSetCommand(buttonAddress, buttonParamId, 0x0);
      final meterSubscribeCmd = generateSubscribeCommand(meterAddress, meterParamId);
      
      setState(() {
        faderMaxString = bytesToHexString(faderMaxCmd);
        faderMinString = bytesToHexString(faderMinCmd);
        buttonOnString = bytesToHexString(buttonOnCmd);
        buttonOffString = bytesToHexString(buttonOffCmd);
        meterSubscribeString = bytesToHexString(meterSubscribeCmd);
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
    final hexString = addressHex.replaceAll("0x", "");
    final bytes = <int>[];
    
    for (int i = 0; i < hexString.length; i += 2) {
      if (i + 2 <= hexString.length) {
        bytes.add(int.parse(hexString.substring(i, i + 2), radix: 16));
      }
    }
    
    return bytes;
  }

  // Generate a command with checksum and byte substitution
  List<int> generateCommand(int commandType, List<int> addressBytes, int paramId, [int value = 0]) {
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
  
  // Generate a SUBSCRIBE command (0x89)
  List<int> generateSubscribeCommand(List<int> addressBytes, int paramId) {
    return generateCommand(0x89, addressBytes, paramId);
  }
  
  // Generate an UNSUBSCRIBE command (0x8A)
  List<int> generateUnsubscribeCommand(List<int> addressBytes, int paramId) {
    return generateCommand(0x8A, addressBytes, paramId);
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

  // Subscribe to parameters
  void subscribeToParameters() {
    try {
      // Subscribe to fader parameter
      final faderAddress = parseHiQnetAddress(faderHiQnetAddressController.text);
      final faderParamId = int.parse(faderParamIdController.text.replaceAll("0x", ""), radix: 16);
      final faderSubscribeCmd = generateSubscribeCommand(faderAddress, faderParamId);
      sendCommand(faderSubscribeCmd);
      
      // Subscribe to button parameter
      final buttonAddress = parseHiQnetAddress(buttonHiQnetAddressController.text);
      final buttonParamId = int.parse(buttonParamIdController.text.replaceAll("0x", ""), radix: 16);
      final buttonSubscribeCmd = generateSubscribeCommand(buttonAddress, buttonParamId);
      sendCommand(buttonSubscribeCmd);
      
      // Subscribe to meter parameter
      final meterAddress = parseHiQnetAddress(meterHiQnetAddressController.text);
      final meterParamId = int.parse(meterParamIdController.text.replaceAll("0x", ""), radix: 16);
      final meterSubscribeCmd = generateSubscribeCommand(meterAddress, meterParamId);
      sendCommand(meterSubscribeCmd);
      
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
  void unsubscribeFromParameters() {
    if (socket == null) return;
    
    try {
      // Unsubscribe from fader parameter
      final faderAddress = parseHiQnetAddress(faderHiQnetAddressController.text);
      final faderParamId = int.parse(faderParamIdController.text.replaceAll("0x", ""), radix: 16);
      final faderUnsubscribeCmd = generateUnsubscribeCommand(faderAddress, faderParamId);
      sendCommand(faderUnsubscribeCmd);
      
      // Unsubscribe from button parameter
      final buttonAddress = parseHiQnetAddress(buttonHiQnetAddressController.text);
      final buttonParamId = int.parse(buttonParamIdController.text.replaceAll("0x", ""), radix: 16);
      final buttonUnsubscribeCmd = generateUnsubscribeCommand(buttonAddress, buttonParamId);
      sendCommand(buttonUnsubscribeCmd);
      
      // Unsubscribe from meter parameter
      final meterAddress = parseHiQnetAddress(meterHiQnetAddressController.text);
      final meterParamId = int.parse(meterParamIdController.text.replaceAll("0x", ""), radix: 16);
      final meterUnsubscribeCmd = generateUnsubscribeCommand(meterAddress, meterParamId);
      sendCommand(meterUnsubscribeCmd);
      
      addLog('Unsubscribed from parameters');
    } catch (e) {
      addLog('Error unsubscribing from parameters: $e');
    }
  }
  
  // Handle incoming data from the device
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
        // Not a complete message yet
        return;
      }
      
      // Extract the message (including start and end bytes)
      List<int> message = _buffer.sublist(0, endIndex + 1);
      _buffer.removeRange(0, endIndex + 1);
      
      // Process the message
      processMessage(message);
    }
  }
  
  // Process a complete message
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
      
      // Verify checksum (last byte)
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
      } else if (msgType == 0x06) { // ACK
        addLog('Received ACK');
      } else if (msgType == 0x15) { // NAK
        addLog('Received NAK');
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
      if (message.length < 10) {
        addLog('SET message too short: ${bytesToHexString(message)}');
        return;
      }
      
      // Extract the address from the message
      List<int> address = message.sublist(1, 7); // 6 bytes address
      
      // Extract parameter ID (2 bytes)
      int paramId = (message[7] << 8) | message[8];
      
      // Extract value (4 bytes)
      int value = 0;
      if (message.length >= 13) {
        value = (message[9] << 24) | (message[10] << 16) | (message[11] << 8) | message[12];
      }
      
      // Convert address to hex string for logging
      String addressHex = address.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
      
      // Only log meter updates if they're not too frequent to avoid flooding the log
      if (!isMeterAddress(address, paramId)) {
        addLog('Received SET: address=0x$addressHex, paramId=0x${paramId.toRadixString(16)}, value=$value');
      }
      
      // Update UI based on the received message
      updateUIFromSetMessage(address, paramId, value);
    } catch (e) {
      addLog('Error processing SET message: $e');
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
  
  // Update UI based on received SET message
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
          signedValue = value - 0x100000000;
        }
        
        double normalizedValue = (signedValue - minValue) / (maxValue - minValue);
        normalizedValue = normalizedValue.clamp(0.0, 1.0);
        
        setState(() {
          faderValue = normalizedValue;
        });
        
        addLog('Updated fader value: $normalizedValue');
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
      
      // Check if it matches meter parameter
      String meterAddressHex = meterHiQnetAddressController.text.replaceAll("0x", "");
      int meterParamId = int.parse(meterParamIdController.text.replaceAll("0x", ""), radix: 16);
      
      if (addressHex.toUpperCase() == meterAddressHex.toUpperCase() && paramId == meterParamId) {
        // Convert value to meter position (0.0 to 1.0)
        // Meter parameters use values -800,000 (0% -80dB) to 400,000 (100% +40dB)
        const double minDb = -80.0; // -80dB
        const double maxDb = 40.0;  // +40dB
        
        // Handle signed values
        double signedValue = value.toDouble();
        if (value > 0x7FFFFFFF) {
          signedValue = value - 0x100000000;
        }
        
        // Convert to dB (value / 10000)
        double dbValue = signedValue / 10000.0;
        dbValue = dbValue.clamp(minDb, maxDb);
        
        // Normalize to 0.0-1.0 range
        double normalizedValue = (dbValue - minDb) / (maxDb - minDb);
        
        setState(() {
          meterValue = normalizedValue;
        });
        
        addLog('Updated meter value: ${dbValue.toStringAsFixed(1)}dB (${(normalizedValue * 100).toStringAsFixed(1)}%)');
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection settings
            const Text('Connection Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ipAddressController,
                    decoration: const InputDecoration(
                      labelText: 'IP Address',
                      border: OutlineInputBorder(),
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
                  onPressed: isConnected ? null : connectToDevice,
                  child: const Text('Connect'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: isConnected ? disconnectFromDevice : null,
                  child: const Text('Disconnect'),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Text(isConnected ? 'Connected' : 'Disconnected'),
              ],
            ),
            
            const Divider(height: 32),
            
            // Fader control
            const Text('Fader Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: faderHiQnetAddressController,
              decoration: const InputDecoration(
                labelText: 'HiQnet Address',
                border: OutlineInputBorder(),
                hintText: 'Example: 0x2D6803000100',
              ),
              onChanged: (_) => updateCommandStrings(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: faderParamIdController,
              decoration: const InputDecoration(
                labelText: 'Param ID',
                border: OutlineInputBorder(),
                hintText: 'Example: 0x0',
              ),
              onChanged: (_) => updateCommandStrings(),
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
                        
                        // Re-subscribe to ensure we get updates
                        try {
                          final faderAddress = parseHiQnetAddress(faderHiQnetAddressController.text);
                          final faderParamId = int.parse(faderParamIdController.text.replaceAll("0x", ""), radix: 16);
                          sendCommand(generateSubscribeCommand(faderAddress, faderParamId));
                        } catch (e) {
                          addLog('Error re-subscribing to fader: $e');
                        }
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
            
            const Divider(height: 32),
            
            // Button control
            const Text('Button Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: buttonHiQnetAddressController,
              decoration: const InputDecoration(
                labelText: 'HiQnet Address',
                border: OutlineInputBorder(),
                hintText: 'Example: 0x2D6803000100',
              ),
              onChanged: (_) => updateCommandStrings(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: buttonParamIdController,
              decoration: const InputDecoration(
                labelText: 'Param ID',
                border: OutlineInputBorder(),
                hintText: 'Example: 0x1',
              ),
              onChanged: (_) => updateCommandStrings(),
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
                        
                        // Re-subscribe to ensure we get updates
                        sendCommand(generateSubscribeCommand(address, paramId));
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
            
            const Divider(height: 32),
            
            // Meter control
            const Text('Signal Meter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: meterHiQnetAddressController,
              decoration: const InputDecoration(
                labelText: 'HiQnet Address',
                border: OutlineInputBorder(),
                hintText: 'Example: 0x2D6803000200',
              ),
              onChanged: (_) => updateCommandStrings(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: meterParamIdController,
              decoration: const InputDecoration(
                labelText: 'Param ID',
                border: OutlineInputBorder(),
                hintText: 'Example: 0x0',
              ),
              onChanged: (_) => updateCommandStrings(),
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 8),
            
            // Meter visualization
            Container(
              height: 80,
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
                          
                          return Stack(
                            children: [
                              // Background
                              Container(
                                width: constraints.maxWidth,
                                decoration: BoxDecoration(
                                  color: Colors.black12,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              // Meter bar
                              Container(
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
                                    '${(-80 + meterValue * 120).toStringAsFixed(1)} dB',
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
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text('Meter Subscribe HEX Command:'),
            SelectableText(meterSubscribeString),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: isConnected ? () {
                    // Subscribe to the meter parameter
                    try {
                      final meterAddress = parseHiQnetAddress(meterHiQnetAddressController.text);
                      final meterParamId = int.parse(meterParamIdController.text.replaceAll("0x", ""), radix: 16);
                      final command = generateSubscribeCommand(meterAddress, meterParamId);
                      sendCommand(command);
                      setState(() {
                        meterSubscribeString = bytesToHexString(command);
                      });
                      addLog('Manually subscribed to meter parameter');
                    } catch (e) {
                      addLog('Error subscribing to meter: $e');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error subscribing to meter: $e')),
                      );
                    }
                  } : null,
                  child: const Text('Refresh Meter Now'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: updateCommandStrings,
                  child: const Text('Update HEX Commands'),
                ),
              ],
            ),
            
            const Divider(height: 32),
            
            // Command strings
            const Text('Command Strings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
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
            
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  onPressed: updateCommandStrings,
                  child: const Text('Update Command Strings'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: isConnected ? subscribeToParameters : null,
                  child: const Text('Refresh All States'),
                ),
              ],
            ),
            
            const Divider(height: 32),
            
            // Log section
            const Text('Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
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
          ],
        ),
      ),
    );
  }
}