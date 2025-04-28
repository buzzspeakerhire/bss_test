import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

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
  const BSSControllerScreen({Key? key}) : super(key: key);

  @override
  _BSSControllerScreenState createState() => _BSSControllerScreenState();
}

class _BSSControllerScreenState extends State<BSSControllerScreen> {
  // Connection state
  bool isConnected = false;
  Socket? socket;
  
  // Text controllers
  final ipAddressController = TextEditingController(text: "192.168.0.20");
  final portController = TextEditingController(text: "1023");
  
  // Control parameters
  final faderHiQnetAddressController = TextEditingController(text: "0x2D6803000100");
  final faderParamIdController = TextEditingController(text: "0x0");
  final buttonHiQnetAddressController = TextEditingController(text: "0x2D6803000100");
  final buttonParamIdController = TextEditingController(text: "0x1");
  
  // Control values
  double faderValue = 1.0; // 100% = max value
  bool buttonState = false;
  
  // Command strings
  String faderMaxString = "02,88,2D,68,1B,83,00,01,00,00,00,01,86,A0,E8,03";
  String faderMinString = "02,88,2D,68,1B,83,00,01,00,00,00,FF,FB,B7,D7,AB,03";
  String buttonOnString = "02,88,2D,68,1B,83,00,01,00,00,01,00,00,00,01,CF,03";
  String buttonOffString = "02,88,2D,68,1B,83,00,01,00,00,01,00,00,00,00,CE,03";

  @override
  void initState() {
    super.initState();
    updateCommandStrings();
  }

  @override
  void dispose() {
    disconnectFromDevice();
    ipAddressController.dispose();
    portController.dispose();
    faderHiQnetAddressController.dispose();
    faderParamIdController.dispose();
    buttonHiQnetAddressController.dispose();
    buttonParamIdController.dispose();
    super.dispose();
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
      });
      
      // Listen for responses from the device
      socket!.listen(
        (Uint8List data) {
          // Handle device response if needed
        },
        onError: (error) {
          disconnectFromDevice();
        },
        onDone: () {
          disconnectFromDevice();
        },
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connected to device')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e')),
      );
    }
  }

  // Disconnect from the BSS device
  void disconnectFromDevice() {
    if (!isConnected) return;
    
    socket?.close();
    socket = null;
    setState(() {
      isConnected = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Disconnected from device')),
    );
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
    } catch (e) {
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
      
      // Generate command strings
      final faderMaxCmd = generateSetCommand(faderAddress, faderParamId, 0x0186A0);
      final faderMinCmd = generateSetCommand(faderAddress, faderParamId, 0xFFFBB7D7);
      final buttonOnCmd = generateSetCommand(buttonAddress, buttonParamId, 0x1);
      final buttonOffCmd = generateSetCommand(buttonAddress, buttonParamId, 0x0);
      
      setState(() {
        faderMaxString = bytesToHexString(faderMaxCmd);
        faderMinString = bytesToHexString(faderMinCmd);
        buttonOnString = bytesToHexString(buttonOnCmd);
        buttonOffString = bytesToHexString(buttonOffCmd);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating command strings: $e')),
      );
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

  // Generate a SET command (0x88) with checksum and byte substitution
  List<int> generateSetCommand(List<int> addressBytes, int paramId, int value) {
    // Command structure:
    // 0x02 (start) + 0x88 (SET) + Address + ParamID + Value + Checksum + 0x03 (end)
    
    final command = <int>[0x88]; // SET command
    
    // Add address bytes
    command.addAll(addressBytes);
    
    // Add parameter ID (2 bytes)
    command.add((paramId >> 8) & 0xFF); // High byte
    command.add(paramId & 0xFF);        // Low byte
    
    // Add value (4 bytes)
    command.add((value >> 24) & 0xFF); // Byte 1 (MSB)
    command.add((value >> 16) & 0xFF); // Byte 2
    command.add((value >> 8) & 0xFF);  // Byte 3
    command.add(value & 0xFF);         // Byte 4 (LSB)
    
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

  // Generate fader command based on current value
  List<int> generateFaderCommand() {
    try {
      final address = parseHiQnetAddress(faderHiQnetAddressController.text);
      final paramId = int.parse(faderParamIdController.text.replaceAll("0x", ""), radix: 16);
      
      // Calculate value based on fader position (0.0 to 1.0)
      // Max value = 0x0186A0 (100000), Min value = 0xFFFBB7D7 (-280617)
      final double maxValue = 0x0186A0;
      final double minValue = -280617; // 0xFFFBB7D7 as signed integer
      final int value = (minValue + faderValue * (maxValue - minValue)).toInt();
      
      return generateSetCommand(address, paramId, value & 0xFFFFFFFF);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating fader command: $e')),
      );
      return [];
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
                        final command = generateSetCommand(address, paramId, buttonState ? 1 : 0);
                        sendCommand(command);
                      } catch (e) {
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
            
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: updateCommandStrings,
              child: const Text('Update Command Strings'),
            ),
          ],
        ),
      ),
    );
  }
}