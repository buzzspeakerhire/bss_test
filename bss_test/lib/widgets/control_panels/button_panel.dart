import 'package:flutter/material.dart';
import '../../services/control_communication_service.dart';

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
  
  // Text controllers
  final _buttonHiQnetAddressController = TextEditingController(text: "0x2D6803000100");
  final _buttonParamIdController = TextEditingController(text: "0x1");
  
  // Control values
  bool _buttonState = false;
  
  @override
  void initState() {
    super.initState();
    
    // Listen for button updates
    _controlService.onButtonUpdate.listen((data) {
      final address = _buttonHiQnetAddressController.text;
      final paramId = _buttonParamIdController.text;
      
      if (data['address'] == address && data['paramId'] == paramId) {
        setState(() {
          _buttonState = data['value'] != 0;
        });
      }
    });
  }
  
  @override
  void dispose() {
    _buttonHiQnetAddressController.dispose();
    _buttonParamIdController.dispose();
    super.dispose();
  }
  
  // Toggle button state
  void _toggleButtonState(bool value) {
    setState(() {
      _buttonState = value;
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
                  onChanged: widget.isConnected ? _toggleButtonState : null,
                ),
                const SizedBox(width: 8),
                Text(_buttonState ? 'ON' : 'OFF'),
              ],
            ),
            const SizedBox(height: 16),
            // Add button control UI options
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: widget.isConnected ? () => _toggleButtonState(true) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _buttonState ? Colors.green : null,
                    ),
                    child: const Text('ON'),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: widget.isConnected ? () => _toggleButtonState(false) : null,
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