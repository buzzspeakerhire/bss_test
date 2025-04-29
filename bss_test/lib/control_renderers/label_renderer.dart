import 'package:flutter/material.dart';
import '../models/control_model.dart';

class LabelRenderer extends StatelessWidget {
  final ControlModel control;
  
  const LabelRenderer({
    super.key,
    required this.control,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: control.backgroundColor,
      alignment: Alignment.center,
      child: Text(
        control.text,
        style: TextStyle(
          color: control.foregroundColor,
          fontSize: 12,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}