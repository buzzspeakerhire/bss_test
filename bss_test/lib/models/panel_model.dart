import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'control_model.dart';

class PanelModel {
  final String name;
  final String text;
  final String version;
  final Size size;
  final Color backgroundColor;
  final Color foregroundColor;
  final List<ControlModel> controls;

  PanelModel({
    required this.name,
    required this.text,
    required this.version,
    required this.size,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.controls,
  });

  factory PanelModel.fromXmlElement(XmlElement element) {
    // Basic parsing of panel attributes - will be expanded later
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
    
    // For now, return an empty list of controls
    return PanelModel(
      name: name,
      text: text,
      version: version,
      size: size,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      controls: [], // Will be populated in a later phase
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
}