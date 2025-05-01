import 'package:flutter/material.dart';
import '../models/control_model.dart';

class RectangleRenderer extends StatelessWidget {
  final ControlModel control;
  
  const RectangleRenderer({
    super.key,
    required this.control,
  });
  
  @override
  Widget build(BuildContext context) {
    // Extract border thickness if available
    final thickness = 
        double.tryParse(control.properties['controlProperties']?['Thickness'] as String? ?? '1') ?? 1.0;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(
          color: control.foregroundColor,
          width: thickness,
        ),
      ),
    );
  }
} 