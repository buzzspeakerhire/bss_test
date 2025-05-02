import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/control_communication_service.dart';
import '../../services/fader_communication.dart';

class ButtonPanel extends StatefulWidget {
  final bool isConnected;
  
  const ButtonPanel({
    super.key,
    required this.isConnected,
  });

  @override
  State<ButtonPanel> createState() => _ButtonPanelState();
}

class _ButtonPanelState extends State<ButtonPanel> {
  final _controlService = ControlCommunicationService();
  final _faderComm = FaderCommunication();
  
  // Text controllers
  final _buttonHiQnetAddressController = TextEditingController(text: "0x2D6803000100");
  final _buttonParamIdController = TextEditingController(text: "0x1");
  
  // Control values
  bool _buttonState = false;
  
  // Subscriptions
  StreamSubscription? _buttonUpdateSubscription;
  StreamSubscription? _faderCommSubscription;
  
  @override
  void initState() {
    super.initState();
    
    // Register with control service
    _controlService.setButtonAddressControllers(_buttonHiQnetAddressController, _buttonParamIdController);
    
    // Listen for updates from both sources
    _buttonUpdateSubscription = _controlService.onButtonUpdate.listen((data) {
      final address = _buttonHiQnetAddressController.text;
      final paramId = _buttonParamIdController.text;
      
      if (data['address'].toString().toLowerCase() == address.toLowerCase() && 
          data['paramId'].toString().toLowerCase() == paramId.toLowerCase()) {
        setState(() {
          // Make sure to convert to boolean
          _buttonState = data['value'] != 0;
          debugPrint('ButtonPanel: Updated from control service: $_buttonState');
        });
      }
    });
    
    // Also listen for updates from FaderCommunication
    _faderCommSubscription = _faderComm.onButtonUpdate.listen((data) {
      final address = _buttonHiQnetAddressController.text;
      final paramId = _buttonParamIdController.text;
      
      if (data['address'].toString().toLowerCase() == address.toLowerCase() && 
          data['paramId'].toString().toLowerCase() == paramId.toLowerCase()) {
        setState(() {
          _buttonState = data['state'] as bool;
          debugPrint('ButtonPanel: Updated from FaderComm: $_buttonState');
        });
      }
    });
    
    // Add direct listener for further reliability
    _faderComm.addButtonUpdateListener((data) {
      final address = _buttonHiQnetAddressController.text;
      final paramId = _buttonParamIdController.text;
      
      if (data['address'].toString().toLowerCase() == address.toLowerCase() && 
          data['paramId'].toString().toLowerCase() == paramId.toLowerCase()) {
        setState(() {
          _buttonState = data['state'] as bool;
          debugPrint('ButtonPanel: Updated from direct listener: $_buttonState');
        });
      }
    });
    
    // Force UI update when connection status changes
    if (widget.isConnected) {
      // Request current state
      _requestButtonState();
    }
  }
  
  @override
  void didUpdateWidget(ButtonPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // React to connection state changes
    if (widget.isConnected != oldWidget.isConnected && widget.isConnected) {
      // Connection just became active, request current state
      _requestButtonState();
    }
  }
  
  void _requestButtonState() {
    // Send a subscribe message to get current state
    if (widget.isConnected) {
      _controlService.setButtonState(
        _buttonHiQnetAddressController.text,
        _buttonParamIdController.text,
        _buttonState,
      );
    }
  }
  
  @override
  void dispose() {
    _buttonUpdateSubscription?.cancel();
    _faderCommSubscription?.cancel();
    _buttonHiQnetAddressController.dispose();
    _buttonParamIdController.dispose();
    super.dispose();
  }
  
  // Toggle button state
  void _toggleButtonState() {
    setState(() {
      _buttonState = !_buttonState;
    });
    
    if (widget.isConnected) {
      _controlService.setButtonState(
        _buttonHiQnetAddressController.text,
        _buttonParamIdController.text,
        _buttonState,
      );
    }
  }
  
  // Set button to specific state
  void _setButtonState(bool state) {
    setState(() {
      _buttonState = state;
    });
    
    if (widget.isConnected) {
      _controlService.setButtonState(
        _buttonHiQnetAddressController.text,
        _buttonParamIdController.text,
        _buttonState,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
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
                    controller: _buttonHiQnetAddressController,
                    decoration: const InputDecoration(
                      labelText: 'HiQnet Address',
                      border: OutlineInputBorder(),
                      hintText: 'Example: 0x2D6803000100',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _buttonParamIdController,
                    decoration: const InputDecoration(
                      labelText: 'Param ID',
                      border: OutlineInputBorder(),
                      hintText: 'Example: 0x1',
                    ),
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
                  value: _buttonState,
                  onChanged: widget.isConnected ? (value) => _setButtonState(value) : null,
                ),
                const SizedBox(width: 8),
                Text(_buttonState ? 'ON' : 'OFF'),
                // Add a debug button to force UI update
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _requestButtonState,
                  tooltip: 'Force refresh',
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Add button control UI options
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: widget.isConnected ? () => _setButtonState(true) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _buttonState ? Colors.green : null,
                    ),
                    child: const Text('ON'),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: widget.isConnected ? () => _setButtonState(false) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !_buttonState ? Colors.red : null,
                    ),
                    child: const Text('OFF'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}