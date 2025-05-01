import 'dart:async';
import 'package:flutter/material.dart';
import '../models/control_model.dart';
import '../services/fader_communication.dart';

class BareFaderRenderer extends StatefulWidget {
  final ControlModel control;
  
  const BareFaderRenderer({
    super.key,
    required this.control,
  });

  @override
  State<BareFaderRenderer> createState() => _BareFaderRendererState();
}

class _BareFaderRendererState extends State<BareFaderRenderer> {
  double _value = 0.5;
  bool _isDragging = false;
  final _communication = FaderCommunication();
  StreamSubscription? _updateSubscription;
  StreamSubscription? _connectionSubscription;
  bool _isConnected = false;
  Color _faderColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    
    try {
      // Listen for fader updates from the device
      _updateSubscription = _communication.onFaderUpdate.listen((data) {
        try {
          final address = widget.control.getPrimaryAddress();
          final paramId = widget.control.getPrimaryParameterId();
          
          // Check if this update is for this fader
          if (address == data['address'] && paramId == data['paramId'] && !_isDragging) {
            setState(() {
              _value = data['value'];
            });
            debugPrint('BareFaderRenderer: Received fader update from device - ${widget.control.name}: ${_value.toStringAsFixed(3)}');
          }
        } catch (e) {
          debugPrint('Error handling fader update: $e');
        }
      });
      
      // Listen for connection state changes
      _connectionSubscription = _communication.onConnectionChanged.listen((connected) {
        try {
          setState(() {
            _isConnected = connected;
            _faderColor = connected ? Colors.blue : Colors.grey;
          });
          debugPrint('BareFaderRenderer: Connection state changed to $_isConnected');
        } catch (e) {
          debugPrint('Error handling connection state change: $e');
        }
      });
      
      // Initialize connection state
      _isConnected = _communication.isConnected;
      _faderColor = _isConnected ? Colors.blue : Colors.grey;
    } catch (e) {
      debugPrint('Error in BareFaderRenderer initState: $e');
    }
  }

  @override
  void dispose() {
    try {
      _updateSubscription?.cancel();
      _connectionSubscription?.cancel();
    } catch (e) {
      debugPrint('Error in BareFaderRenderer dispose: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      return SliderTheme(
        data: SliderThemeData(
          trackHeight: 25.0, // Make the track taller for easier interaction
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 15.0), // Bigger thumb
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 20.0), // Bigger tap area
          trackShape: const RectangularSliderTrackShape(),
          thumbColor: Colors.white,
          activeTrackColor: _faderColor,
          inactiveTrackColor: Colors.grey[300],
        ),
        child: RotatedBox(
          quarterTurns: 3, // Keep slider vertical
          child: Slider(
            value: _value,
            onChangeStart: (_) => _isDragging = true,
            onChanged: (value) {
              setState(() => _value = value);
            },
            onChangeEnd: (value) {
              _isDragging = false;
              _reportFaderValue(value);
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error in BareFaderRenderer build: $e');
      return Container(
        width: 50,
        height: 100,
        color: Colors.grey[300],
        child: const Center(
          child: Text('Fader Error', style: TextStyle(color: Colors.red, fontSize: 8)),
        ),
      );
    }
  }

  void _reportFaderValue(double value) {
    try {
      final address = widget.control.getPrimaryAddress();
      final paramId = widget.control.getPrimaryParameterId();
      
      if (address != null && paramId != null && _isConnected) {
        _communication.reportFaderMoved(address, paramId, value);
        debugPrint('BareFaderRenderer: Fader ${widget.control.name} moved - value: ${value.toStringAsFixed(3)}');
      }
    } catch (e) {
      debugPrint('Error reporting fader value: $e');
    }
  }
}