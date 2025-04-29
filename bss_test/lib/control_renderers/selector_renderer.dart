import 'package:flutter/material.dart';
import '../models/control_model.dart';

class SelectorRenderer extends StatelessWidget {
  final ControlModel control;
  
  const SelectorRenderer({
    super.key,
    required this.control,
  });
  
  @override
  Widget build(BuildContext context) {
    // Get options if they exist
    final options = control.properties['options'] as List<Map<String, String>>? ?? [];
    
    return Container(
      decoration: BoxDecoration(
        color: control.backgroundColor,
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              options.isNotEmpty ? options.first['label'] ?? control.name : control.name,
              style: TextStyle(
                color: control.foregroundColor,
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 14),
        ],
      ),
    );
  }
}