import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'control_model.dart';
import 'control_types.dart';

class PanelModel {
  final String name;
  final String text;
  final String version;
  final Size size;
  final Color backgroundColor;
  final Color foregroundColor;
  final List<ControlModel> controls;
  final Map<String, dynamic> properties;

  PanelModel({
    required this.name,
    required this.text,
    required this.version,
    required this.size,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.controls,
    this.properties = const {},
  });

  factory PanelModel.fromXmlElement(XmlElement element) {
    // Basic parsing of panel attributes
    final name = element.getAttribute('Name') ?? '';
    final text = element.getAttribute('Text') ?? '';
    final version = element.getAttribute('Version') ?? '';
    
    // Parse size
    final sizeStr = element.getAttribute('Size') ?? '0, 0';
    final sizeParts = sizeStr.split(',').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final size = Size(sizeParts[0].toDouble(), sizeParts[1].toDouble());
    
    // Parse colors
    final bgColorStr = element.getAttribute('BackColor') ?? '40, 40, 40';
    final fgColorStr = element.getAttribute('ForeColor') ?? 'WhiteSmoke';
    
    final backgroundColor = _parseColor(bgColorStr);
    final foregroundColor = _parseColor(fgColorStr);
    
    // Extract panel properties
    Map<String, dynamic> properties = {};
    
    // Parse ExtraFormProperties if present
    final extraPropsElement = element.findElements('ExtraFormProperties').firstOrNull;
    if (extraPropsElement != null) {
      for (var prop in extraPropsElement.childElements) {
        final propName = prop.name.local;
        final propValue = prop.innerText;
        properties[propName] = propValue;
      }
    }
    
    return PanelModel(
      name: name,
      text: text,
      version: version,
      size: size,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      controls: [], // Will be populated separately
      properties: properties,
    );
  }
  
  // Color parsing helper
  static Color _parseColor(String colorStr) {
    // Handle named colors
    if (!colorStr.contains(',')) {
      // This is a named color
      switch (colorStr.toLowerCase()) {
        case 'transparent': return Colors.transparent;
        case 'black': return Colors.black;
        case 'white': return Colors.white;
        case 'red': return Colors.red;
        case 'green': return Colors.green;
        case 'blue': return Colors.blue;
        case 'yellow': return Colors.yellow;
        case 'whitesmoke': return const Color(0xFFF5F5F5);
        case 'darkgray': return Colors.grey.shade700;
        default: return Colors.grey; // Default for unknown named colors
      }
    }
    
    // Parse RGB or RGBA colors
    final parts = colorStr.split(',').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    if (parts.length == 3) {
      return Color.fromRGBO(parts[0], parts[1], parts[2], 1.0);
    } else if (parts.length == 4) {
      return Color.fromRGBO(parts[0], parts[1], parts[2], parts[3] / 255.0);
    }
    return Colors.grey;
  }
  
  // Helper methods to find controls by different criteria
  ControlModel? findControlByName(String name) {
    try {
      return controls.firstWhere((control) => control.name == name);
    } catch (_) {
      return null;
    }
  }
  
  List<ControlModel> findControlsByType(ControlType type) {
    return controls.where((control) => control.controlType == type).toList();
  }
  
  List<ControlModel> findControlsByAddress(String address) {
    return controls.where((control) {
      final controlAddress = control.getPrimaryAddress();
      return controlAddress != null && controlAddress == address;
    }).toList();
  }
}