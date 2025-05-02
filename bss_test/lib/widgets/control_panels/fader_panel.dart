import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/control_communication_service.dart';
import '../../services/fader_communication.dart';
import '../../services/bss_protocol_service.dart';

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
  final _faderComm = FaderCommunication();
  final _bssProtocol = BssProtocolService();
  
  // Text controllers
  final _faderHiQnetAddressController = TextEditingController(text: "0x2D6803000100");
  final _faderParamIdController = TextEditingController(text: "0x0");
  
  // Control values
  double _faderValue = 0.5; // 0.0 (min) to 1.0 (max)
  
  // Track subscriptions
  StreamSubscription? _faderUpdateSubscription;
  StreamSubscription? _faderCommSubscription;
  Timer? _debugTimer;
  
  @override
  void initState() {
    super.initState();
    
    // Register with control service
    _controlService.setFaderAddressControllers(_faderHiQnetAddressController, _faderParamIdController);
    
    // Listen for fader updates from control service
    _faderUpdateSubscription = _controlService.onFaderUpdate.listen((data) {
      final address = _faderHiQnetAddressController.text;
      final paramId = _faderParamIdController.text;
      
      if (data['address'].toString().toLowerCase() == address.toLowerCase() && 
          data['paramId'].toString().toLowerCase() == paramId.toLowerCase()) {
        setState(() {
          _faderValue = data['value'];
          debugPrint('FaderPanel: Updated from control service: ${_faderValue.toStringAsFixed(3)}');
        });
      }
    });
    
    // Also listen for updates from FaderCommunication
    _faderCommSubscription = _faderComm.onFaderUpdate.listen((data) {
      final address = _faderHiQnetAddressController.text;
      final paramId = _faderParamIdController.text;
      
      if (data['address'].toString().toLowerCase() == address.toLowerCase() && 
          data['paramId'].toString().toLowerCase() == paramId.toLowerCase()) {
        setState(() {
          _faderValue = data['value'];
          debugPrint('FaderPanel: Updated from FaderComm: ${_faderValue.toStringAsFixed(3)}');
        });
      }
    });
    
    // Add a direct listener for further reliability
    _faderComm.addFaderUpdateListener((data) {
      final address = _faderHiQnetAddressController.text;
      final paramId = _faderParamIdController.text;
      
      if (data['address'].toString().toLowerCase() == address.toLowerCase() && 
          data['paramId'].toString().toLowerCase() == paramId.toLowerCase()) {
        setState(() {
          _faderValue = data['value'];
          debugPrint('FaderPanel: Updated from direct listener: ${_faderValue.toStringAsFixed(3)}');
        });
      }
    });
    
    // Start debug timer to help diagnose update issues
    _debugTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (widget.isConnected) {
        debugPrint('FaderPanel: Debug timer - current value: ${_faderValue.toStringAsFixed(3)}');
      }
    });
    
    // Request current fader value if connected
    if (widget.isConnected) {
      _requestFaderValue();
    }
  }
  
  @override
  void didUpdateWidget(FaderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // React to connection state changes
    if (widget.isConnected != oldWidget.isConnected && widget.isConnected) {
      // Connection just became active, request current state
      _requestFaderValue();
    }
  }
  
  // Request current fader value from device
  void _requestFaderValue() {
    if (widget.isConnected) {
      // Send a subscribe message to get current value
      debugPrint('FaderPanel: Requesting current fader value');
      
      final address = _faderHiQnetAddressController.text;
      final paramId = _faderParamIdController.text;
      
      _controlService.subscribeFaderValue(address, paramId);
    }
  }
  
  @override
  void dispose() {
    _faderUpdateSubscription?.cancel();
    _faderCommSubscription?.cancel();
    _debugTimer?.cancel();
    _faderHiQnetAddressController.dispose();
    _faderParamIdController.dispose();
    super.dispose();
  }
  
  // Update fader value and send to device if connected
  void _updateFaderValue(double value) {
    setState(() {
      _faderValue = value;
    });
    
    if (widget.isConnected) {
      _sendFaderValue();
    }
  }
  
  // Send updated fader value to device
  void _sendFaderValue() {
    if (widget.isConnected) {
      debugPrint('FaderPanel: Sending fader value: ${_faderValue.toStringAsFixed(3)}');
      
      // Use both communication channels for reliability
      _controlService.setFaderValue(
        _faderHiQnetAddressController.text,
        _faderParamIdController.text,
        _faderValue,
      );
      
      // Also directly report to FaderCommunication
      _faderComm.reportFaderMoved(
        _faderHiQnetAddressController.text,
        _faderParamIdController.text, 
        _faderValue
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
                // Add a refresh button like we did for the button control
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _requestFaderValue,
                  tooltip: 'Force refresh',
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
  
  // Convert normalized value to dB for display - fixed to match BSS scaling
  double _getDbValue(double normalizedValue) {
    if (normalizedValue <= 0.0) return -80.0; // Minimum
    if (normalizedValue >= 1.0) return 10.0;  // Maximum
    
    // Exact unity gain
    if ((normalizedValue - 0.7373).abs() < 0.001) return 0.0;
    
    // For values below 0.7373 (unity gain)
    if (normalizedValue < 0.7373) {
      // Scale from -80dB to 0dB
      return -80.0 + (normalizedValue / 0.7373) * 80.0;
    } else {
      // Scale from 0dB to +10dB
      return ((normalizedValue - 0.7373) / (1.0 - 0.7373)) * 10.0;
    }
  }
}