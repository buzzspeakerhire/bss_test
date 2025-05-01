import 'dart:async';
import 'package:flutter/material.dart';
import '../models/control_model.dart';
import '../services/fader_communication.dart';

class ButtonRenderer extends StatefulWidget {
  final ControlModel control;
  
  const ButtonRenderer({
    super.key,
    required this.control,
  });

  @override
  State<ButtonRenderer> createState() => _ButtonRendererState();
}

class _ButtonRendererState extends State<ButtonRenderer> {
  bool _isPressed = false;
  bool _isConnected = false;
  final _communication = FaderCommunication();
  StreamSubscription? _buttonUpdateSubscription;
  StreamSubscription? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    
    try {
      // Listen for button updates from the device
      _buttonUpdateSubscription = _communication.onButtonUpdate.listen((data) {
        try {
          final address = widget.control.getPrimaryAddress();
          final paramId = widget.control.getPrimaryParameterId();
          
          if (address == data['address'] && paramId == data['paramId']) {
            setState(() {
              _isPressed = data['state'] as bool;
            });
            debugPrint('ButtonRenderer: State updated from device - ${widget.control.name}: $_isPressed');
          }
        } catch (e) {
          debugPrint('Error handling button update: $e');
        }
      });
      
      // Listen for connection state changes
      _connectionSubscription = _communication.onConnectionChanged.listen((connected) {
        try {
          setState(() {
            _isConnected = connected;
          });
          debugPrint('ButtonRenderer: Connection state changed to $_isConnected');
        } catch (e) {
          debugPrint('Error handling connection state change: $e');
        }
      });
      
      // Initialize connection state
      _isConnected = _communication.isConnected;
    } catch (e) {
      debugPrint('Error in ButtonRenderer initState: $e');
    }
  }

  @override
  void dispose() {
    try {
      _buttonUpdateSubscription?.cancel();
      _connectionSubscription?.cancel();
    } catch (e) {
      debugPrint('Error in ButtonRenderer dispose: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      return GestureDetector(
        onTapDown: (_) => _onButtonPressed(true),
        onTapUp: (_) => _onButtonPressed(false),
        onTapCancel: () => _onButtonPressed(false),
        child: Container(
          decoration: BoxDecoration(
            color: _isPressed ? Colors.grey[600] : widget.control.backgroundColor,
            border: Border.all(color: _isConnected ? Colors.blueAccent : Colors.grey),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              widget.control.text,
              style: TextStyle(
                color: widget.control.foregroundColor,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error in ButtonRenderer build: $e');
      return Container(
        color: Colors.red[100],
        child: const Center(
          child: Text('Button Error', style: TextStyle(color: Colors.red, fontSize: 8)),
        ),
      );
    }
  }
  
  void _onButtonPressed(bool pressed) {
    try {
      if (_isConnected) {
        setState(() {
          _isPressed = pressed;
        });
        
        // Get address and parameter ID
        final address = widget.control.getPrimaryAddress();
        final paramId = widget.control.getPrimaryParameterId();
        
        if (address != null && paramId != null) {
          // Report the button state change
          _reportButtonState(address, paramId, pressed);
        }
      }
    } catch (e) {
      debugPrint('Error in button press handling: $e');
    }
  }
  
  void _reportButtonState(String address, String paramId, bool state) {
    try {
      // Send button state to the fader communication service
      _communication.reportButtonStateChanged(address, paramId, state);
      debugPrint('ButtonRenderer: Button ${widget.control.name} state changed to $state');
    } catch (e) {
      debugPrint('Error reporting button state: $e');
    }
  }
}