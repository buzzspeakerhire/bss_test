import 'package:flutter/material.dart';
import '../../services/control_communication_service.dart';

class FaderPanel extends StatefulWidget {
  final bool isConnected;
  
  const FaderPanel({
    super.key,
    required this.isConnected,
  });

  @override
  State<FaderPanel> createState() => _FaderPanelState();
}

class _FaderPanelState extends State<FaderPanel> {
  final _controlService = ControlCommunicationService();
  
  // Text controllers
  final _faderHiQnetAddressController = TextEditingController(text: "0x2D6803000100");
  final _faderParamIdController = TextEditingController(text: "0x0");
  
  // Control values
  double _faderValue = 1.0; // 0.0 (min) to 1.0 (max)
  
  @override
  void initState() {
    super.initState();
    
    // Listen for fader updates
    _controlService.onFaderUpdate.listen((data) {
      final address = _faderHiQnetAddressController.text;
      final paramId = _faderParamIdController.text;
      
      if (data['address'] == address && data['paramId'] == paramId) {
        setState(() {
          _faderValue = data['value'];
        });
      }
    });
  }
  
  @override
  void dispose() {
    _faderHiQnetAddressController.dispose();
    _faderParamIdController.dispose();
    super.dispose();
  }
  
  // Update fader value and send to device if connected
  void _updateFaderValue(double value) {
    setState(() {
      _faderValue = value;
    });
  }
  
  // Send updated fader value to device
  void _sendFaderValue() {
    if (widget.isConnected) {
      _controlService.setFaderValue(
        _faderHiQnetAddressController.text,
        _faderParamIdController.text,
        _faderValue,
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
            const Text('Fader Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _faderHiQnetAddressController,
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
                    controller: _faderParamIdController,
                    decoration: const InputDecoration(
                      labelText: 'Param ID',
                      border: OutlineInputBorder(),
                      hintText: 'Example: 0x0',
                    ),
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
                    value: _faderValue,
                    onChanged: (value) => _updateFaderValue(value),
                    onChangeEnd: (_) => _sendFaderValue(),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text('${(_faderValue * 100).toInt()}%'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Display dB value
            Center(
              child: Text(
                'dB: ${_getDbValue(_faderValue).toStringAsFixed(1)} dB',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Convert normalized value to dB for display
  double _getDbValue(double normalizedValue) {
    if (normalizedValue <= 0.0) return -80.0; // Minimum
    
    // Logarithmic scaling
    if (normalizedValue < 0.73) {
      // Below unity gain (0.73 is ~0dB)
      return -80.0 + (normalizedValue / 0.73) * 80.0;
    } else {
      // Above unity gain
      return (normalizedValue - 0.73) / 0.27 * 10.0;
    }
  }
}