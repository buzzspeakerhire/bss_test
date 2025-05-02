import 'package:flutter/material.dart';
import '../models/control_model.dart';
import '../services/global_state.dart';

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
  final _globalState = GlobalState();
  bool _localIsPressed = false;

  @override
  void initState() {
    super.initState();
    
    try {
      final address = widget.control.getPrimaryAddress();
      final paramId = widget.control.getPrimaryParameterId();
      
      if (address == null || paramId == null) {
        debugPrint('ButtonRenderer: Missing address or paramId for ${widget.control.name}');
        return;
      }
      
      debugPrint('ButtonRenderer: Initializing ${widget.control.name} with address=$address, paramId=$paramId');
      
      // Set initial local state
      _localIsPressed = _globalState.getButtonState(address, paramId);
      
      debugPrint('ButtonRenderer: ${widget.control.name} initialized, initial state: $_localIsPressed');
    } catch (e) {
      debugPrint('Error in ButtonRenderer initState: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final address = widget.control.getPrimaryAddress();
      final paramId = widget.control.getPrimaryParameterId();
      
      if (address == null || paramId == null) {
        // Fallback for controls without proper addressing
        return Container(
          decoration: BoxDecoration(
            color: Colors.red[100],
            border: Border.all(color: Colors.red),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Center(
            child: Text('Invalid Button', style: TextStyle(color: Colors.red, fontSize: 10)),
          ),
        );
      }
      
      // Listen to the global state
      return ListenableBuilder(
        listenable: _globalState,
        builder: (context, child) {
          // Get the current state from global state
          final isPressed = _globalState.getButtonState(address, paramId);
          
          // Update local state if it's different
          if (_localIsPressed != isPressed) {
            _localIsPressed = isPressed;
            debugPrint('ButtonRenderer: Updated from global state: $isPressed');
          }
          
          return GestureDetector(
            onTapDown: (_) => _onButtonPressed(address, paramId, true),
            onTapUp: (_) => _onButtonPressed(address, paramId, false),
            onTapCancel: () => _onButtonPressed(address, paramId, false),
            child: Container(
              decoration: BoxDecoration(
                color: isPressed ? Colors.grey[600] : widget.control.backgroundColor,
                border: Border.all(color: _globalState.isConnected ? Colors.blueAccent : Colors.grey),
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
        },
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
  
  void _onButtonPressed(String address, String paramId, bool pressed) {
    try {
      if (_globalState.isConnected) {
        // Send button state to the global state
        _globalState.setButtonState(address, paramId, pressed);
        debugPrint('ButtonRenderer: Button ${widget.control.name} state changed to $pressed');
      }
    } catch (e) {
      debugPrint('Error in button press handling: $e');
    }
  }
}