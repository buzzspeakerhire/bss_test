import 'package:flutter/material.dart';
import '../models/control_model.dart';

class FaderRenderer extends StatelessWidget {
  final ControlModel control;
  
  const FaderRenderer({
    super.key,
    required this.control,
  });
  
  @override
  Widget build(BuildContext context) {
    final isVertical = control.type.toLowerCase().contains("v");
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.grey),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: Container(
                width: isVertical ? 8 : double.infinity,
                height: isVertical ? double.infinity : 8,
                color: control.backgroundColor,
                alignment: Alignment.center,
                child: Container(
                  width: isVertical ? 16 : 30,
                  height: isVertical ? 30 : 16,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    border: Border.all(color: Colors.black),
                  ),
                ),
              ),
            ),
          ),
          Text(
            control.name,
            style: TextStyle(
              color: control.foregroundColor,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}