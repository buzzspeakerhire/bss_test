import 'dart:async';
import 'package:flutter/material.dart';
import '../models/control_model.dart';
import '../fader_communication.dart';

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

  @override
  void initState() {
    super.initState();
    
    // Listen for fader updates from the device
    _updateSubscription = _communication.onFaderUpdate.listen((data) {
      final address = widget.control.getPrimaryAddress();
      final paramId = widget.control.getPrimaryParameterId();
      
      if (address == data['address'] && paramId == data['paramId'] && !_isDragging) {
        setState(() {
          _value = data['value'];
        });
      }
    });
  }

  @override
  void dispose() {
    _updateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always render as vertical sliders
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 25.0, // Make the track taller for easier interaction
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 15.0), // Bigger thumb
        overlayShape: RoundSliderOverlayShape(overlayRadius: 20.0), // Bigger tap area
        trackShape: const RectangularSliderTrackShape(),
        thumbColor: Colors.white,
        activeTrackColor: Colors.deepPurple,
        inactiveTrackColor: Colors.white,
      ),
      child: RotatedBox(
        quarterTurns: 3, // Keep slider vertical
        child: Slider(
          value: _value,
          onChangeStart: (_) => _isDragging = true,
          onChanged: (value) => setState(() => _value = value),
          onChangeEnd: (value) {
            _isDragging = false;
            _reportFaderValue(value);
          },
        ),
      ),
    );
  }

  void _reportFaderValue(double value) {
    final address = widget.control.getPrimaryAddress();
    final paramId = widget.control.getPrimaryParameterId();
    
    if (address != null && paramId != null) {
      _communication.reportFaderMoved(address, paramId, value);
      debugPrint('Fader ${widget.control.name} value: $value');
    }
  }
}