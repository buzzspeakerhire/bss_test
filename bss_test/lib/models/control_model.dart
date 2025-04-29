import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'control_types.dart';

class ControlModel {
  final String name;
  final String type;
  final ControlType controlType;
  final String text;
  final Offset position;
  final Size size;
  final Color backgroundColor;
  final Color foregroundColor;
  
  // Properties for state variables and other control-specific attributes
  final Map<String, dynamic> properties;
  final Map<String, dynamic> stateVariables;

  ControlModel({
    required this.name,
    required this.type,
    required this.controlType,
    required this.text,
    required this.position,
    required this.size,
    required this.backgroundColor,
    required this.foregroundColor,
    this.properties = const {},
    this.stateVariables = const {},
  });

  factory ControlModel.fromXmlElement(XmlElement element) {
    final name = element.getAttribute('Name') ?? '';
    final type = element.getAttribute('Type') ?? '';
    final text = element.getAttribute('Text') ?? '';
    
    // Parse position
    final locationStr = element.getAttribute('Location') ?? '0, 0';
    final locationParts = locationStr.split(',').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final position = Offset(locationParts[0].toDouble(), locationParts[1].toDouble());
    
    // Parse size
    final sizeStr = element.getAttribute('Size') ?? '0, 0';
    final sizeParts = sizeStr.split(',').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final size = Size(sizeParts[0].toDouble(), sizeParts[1].toDouble());
    
    // Parse background and foreground colors
    final bgColorStr = element.getAttribute('BackColor') ?? '';
    final fgColorStr = element.getAttribute('ForeColor') ?? '';
    
    Color backgroundColor = Colors.transparent;
    if (bgColorStr.isNotEmpty) {
      backgroundColor = _parseColor(bgColorStr);
    }
    
    Color foregroundColor = Colors.black;
    if (fgColorStr.isNotEmpty) {
      foregroundColor = _parseColor(fgColorStr);
    }
    
    // Determine control type
    ControlType controlType = _determineControlType(type);
    
    // For now, return basic properties - we'll expand this later
    return ControlModel(
      name: name,
      type: type,
      controlType: controlType,
      text: text,
      position: position,
      size: size,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
    );
  }
  
  static Color _parseColor(String colorStr) {
    // Handle named colors
    if (!colorStr.contains(',')) {
      // This is a named color, we'll return a default for now
      return Colors.grey;
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
  
  static ControlType _determineControlType(String typeString) {
    if (typeString.contains('Button')) return ControlType.button;
    if (typeString.contains('Slider')) return ControlType.fader;
    if (typeString.contains('Meter')) return ControlType.meter;
    if (typeString.contains('ComboBox')) return ControlType.selector;
    if (typeString.contains('Annotation')) return ControlType.label;
    if (typeString.contains('Rectangle')) return ControlType.rectangle;
    return ControlType.unknown;
  }
}