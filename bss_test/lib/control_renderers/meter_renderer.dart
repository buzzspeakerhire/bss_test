import 'package:flutter/material.dart';
import '../models/control_model.dart';

class MeterRenderer extends StatelessWidget {
  final ControlModel control;
  
  const MeterRenderer({
    super.key,
    required this.control,
  });
  
  @override
  Widget build(BuildContext context) {
    final isVertical = control.size.height > control.size.width;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.grey),
      ),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Container(
                  width: isVertical ? 8 : double.infinity,
                  height: isVertical ? double.infinity : 8,
                  color: Colors.black,
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: isVertical ? 8 : (constraints.maxWidth * 0.3),
                    height: isVertical ? (constraints.maxHeight * 0.3) : 8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: isVertical ? Alignment.bottomCenter : Alignment.centerLeft,
                        end: isVertical ? Alignment.topCenter : Alignment.centerRight,
                        colors: [
                          Colors.green,
                          Colors.yellow,
                          Colors.red,
                        ],
                      ),
                    ),
                  ),
                );
              }
            ),
          ),
        ],
      ),
    );
  }
} 