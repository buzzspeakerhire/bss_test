import 'package:flutter/material.dart';
import '../models/control_model.dart';
import '../services/global_state.dart';
import '../services/fader_communication.dart';
import 'dart:async'; // Added this import for StreamSubscription

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
  final _globalState = GlobalState();
  final _faderComm = FaderCommunication();
  bool _isDragging = false;
  double _localValue = 0.5;
  
  // Track subscriptions
  StreamSubscription? _faderUpdateSubscription;

  @override
  void initState() {
    super.initState();
    
    try {
      final address = widget.control.getPrimaryAddress();
      final paramId = widget.control.getPrimaryParameterId();
      
      if (address == null || paramId == null) {
        debugPrint('BareFaderRenderer: Missing address or paramId for ${widget.control.name}');
        return;
      }
      
      debugPrint('BareFaderRenderer: Initializing ${widget.control.name} with address=$address, paramId=$paramId');
      
      // Set initial local value
      _localValue = _globalState.getFaderValue(address, paramId);
      
      // Subscribe to updates from FaderCommunication
      _faderUpdateSubscription = _faderComm.onFaderUpdate.listen((data) {
        if (data['address'].toString().toLowerCase() == address.toLowerCase() && 
            data['paramId'].toString().toLowerCase() == paramId.toLowerCase()) {
          setState(() {
            if (!_isDragging) {
              _localValue = data['value'];
              debugPrint('BareFaderRenderer: Updated from FaderComm: ${_localValue.toStringAsFixed(3)}');
            }
          });
        }
      });
      
      // Also directly register a listener
      _faderComm.addFaderUpdateListener((data) {
        if (data['address'].toString().toLowerCase() == address.toLowerCase() && 
            data['paramId'].toString().toLowerCase() == paramId.toLowerCase()) {
          setState(() {
            if (!_isDragging) {
              _localValue = data['value'];
              debugPrint('BareFaderRenderer: Updated from direct listener: ${_localValue.toStringAsFixed(3)}');
            }
          });
        }
      });
      
      debugPrint('BareFaderRenderer: ${widget.control.name} initialized, initial value: ${_localValue.toStringAsFixed(3)}');
    } catch (e) {
      debugPrint('Error in BareFaderRenderer initState: $e');
    }
  }
  
  @override
  void dispose() {
    _faderUpdateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final address = widget.control.getPrimaryAddress();
      final paramId = widget.control.getPrimaryParameterId();
      
      if (address == null || paramId == null) {
        // Fallback for controls without proper addressing
        return Container(
          width: 50,
          height: 100,
          color: Colors.red[100],
          child: const Center(
            child: Text('Invalid Fader', style: TextStyle(color: Colors.red, fontSize: 10)),
          ),
        );
      }
      
      // Listen to the global state
      return ListenableBuilder(
        listenable: _globalState,
        builder: (context, child) {
          // Get the current value from global state
          final value = _globalState.getFaderValue(address, paramId);
          
          // Update local value if it's different and not dragging
          if (!_isDragging && (_localValue - value).abs() > 0.001) {
            _localValue = value;
            debugPrint('BareFaderRenderer: Updated from global state: ${value.toStringAsFixed(3)}');
          }
          
          return SliderTheme(
            data: SliderThemeData(
              trackHeight: 25.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 15.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20.0),
              trackShape: const RectangularSliderTrackShape(),
              thumbColor: Colors.white,
              activeTrackColor: _globalState.isConnected ? Colors.blue : Colors.grey,
              inactiveTrackColor: Colors.grey[300],
            ),
            child: RotatedBox(
              quarterTurns: 3, // Keep slider vertical
              child: Slider(
                value: _localValue,
                onChangeStart: (_) {
                  debugPrint('BareFaderRenderer: Starting drag on ${widget.control.name}');
                  _isDragging = true;
                },
                onChanged: (newValue) {
                  setState(() {
                    _localValue = newValue;
                  });
                },
                onChangeEnd: (newValue) {
                  debugPrint('BareFaderRenderer: Ending drag on ${widget.control.name}');
                  _isDragging = false;
                  _reportFaderValue(address, paramId, newValue);
                },
              ),
            ),
          );
        },
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

  void _reportFaderValue(String address, String paramId, double value) {
    try {
      if (_globalState.isConnected) {
        _globalState.setFaderValue(address, paramId, value);
        
        // Also directly report through FaderCommunication
        _faderComm.reportFaderMoved(address, paramId, value);
        
        debugPrint('BareFaderRenderer: Fader ${widget.control.name} moved - value: ${value.toStringAsFixed(3)}');
      }
    } catch (e) {
      debugPrint('Error reporting fader value: $e');
    }
  }
}