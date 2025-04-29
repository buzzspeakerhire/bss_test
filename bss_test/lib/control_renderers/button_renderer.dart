import 'package:flutter/material.dart';
import '../models/control_model.dart';

class ButtonRenderer extends StatelessWidget {
  final ControlModel control;
  
  const ButtonRenderer({
    super.key,
    required this.control,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: control.backgroundColor,
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          control.text,
          style: TextStyle(
            color: control.foregroundColor,
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}