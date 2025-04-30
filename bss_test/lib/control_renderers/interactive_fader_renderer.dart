import 'dart:async';
import 'package:flutter/material.dart';
import '../models/control_model.dart';
import '../fader_communication.dart';

class InteractiveFaderRenderer extends StatefulWidget {
  final ControlModel control;
  
  const InteractiveFaderRenderer({
    super.key,
    required this.control,
  });

  @override
  State<InteractiveFaderRenderer> createState() => _InteractiveFaderRendererState();
}

class _InteractiveFaderRendererState extends State<InteractiveFaderRenderer> {
  double _value = 0.5; // Default to middle position
  bool _isDragging = false;
  final _communication = FaderCommunication();
  StreamSubscription? _updateSubscription;
  StreamSubscription? _connectionSubscription;
  Color _faderColor = Colors.grey;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    
    // Listen for fader updates from the device
    _updateSubscription = _communication.onFaderUpdate.listen((data) {
      // Check if this update is for this fader
      final address = widget.control.getPrimaryAddress();
      final paramId = widget.control.getPrimaryParameterId();
      
      if (address == data['address'] && paramId == data['paramId'] && !_isDragging) {
        setState(() {
          _value = data['value'];
        });
      }
    });
    
    // Listen for connection state changes
    _connectionSubscription = _communication.onConnectionChanged.listen((connected) {
      setState(() {
        _isConnected = connected;
        _faderColor = connected ? Colors.blue : Colors.grey;
      });
    });
    
    // Initialize connection state
    _isConnected = _communication.isConnected;
    _faderColor = _isConnected ? Colors.blue : Colors.grey;
  }

  @override
  void dispose() {
    _updateSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVertical = widget.control.type.toLowerCase().contains("v");
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.grey),
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: isVertical
                  ? SizedBox(
                      width: 60,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Slider(
                          value: _value,
                          activeColor: _faderColor,
                          onChangeStart: (_) {
                            _isDragging = true;
                          },
                          onChanged: (newValue) {
                            setState(() {
                              _value = newValue;
                            });
                          },
                          onChangeEnd: (newValue) {
                            _isDragging = false;
                            _onFaderChanged(newValue);
                          },
                        ),
                      ),
                    )
                  : Slider(
                      value: _value,
                      activeColor: _faderColor,
                      onChangeStart: (_) {
                        _isDragging = true;
                      },
                      onChanged: (newValue) {
                        setState(() {
                          _value = newValue;
                        });
                      },
                      onChangeEnd: (newValue) {
                        _isDragging = false;
                        _onFaderChanged(newValue);
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Text(
              widget.control.name,
              style: TextStyle(
                color: widget.control.foregroundColor,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  void _onFaderChanged(double value) {
    // Get address and parameter ID if available
    final address = widget.control.getPrimaryAddress();
    final paramId = widget.control.getPrimaryParameterId();
    
    if (address != null && paramId != null && _isConnected) {
      // Notify the communication system
      _communication.reportFaderMoved(address, paramId, value);
      
      // For debugging
      debugPrint('Fader ${widget.control.name} moved: $address, $paramId, $value');
    }
  }
}