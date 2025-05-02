import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'control_types.dart';
import 'state_variable_item.dart';

class ControlModel {
  final String name;
  final String type;
  final ControlType controlType;
  final String text;
  final Offset position;
  final Size size;
  final Color backgroundColor;
  final Color foregroundColor;
  
  // Complex properties
  final Map<String, dynamic> properties;
  final List<StateVariableItem> stateVariables;

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
    this.stateVariables = const [],
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
    
    // Parse complex properties
    Map<String, dynamic> properties = {};
    List<StateVariableItem> stateVariables = [];
    
    // Find ComplexProperties elements
    final complexPropertiesList = element.findElements('ComplexProperties');
    for (var complexProps in complexPropertiesList) {
      final tag = complexProps.getAttribute('Tag') ?? '';
      
      // Handle state variables
      if (tag == 'HProSVControl') {
        final stateVarItems = complexProps.findElements('StateVariableItems').firstOrNull;
        if (stateVarItems != null) {
          final items = stateVarItems.findElements('StateVariableItem');
          for (var item in items) {
            stateVariables.add(StateVariableItem.fromXmlElement(item));
          }
        }
      } 
      // Handle DiscreteControl (for ComboBox)
      else if (tag == 'HProDiscreteControl') {
        final userList = complexProps.findElements('UserList').firstOrNull;
        if (userList != null) {
          final items = userList.findElements('StringList');
          List<Map<String, String>> options = [];
          
          for (var item in items) {
            options.add({
              'value': item.getAttribute('Value') ?? '',
              'label': item.getAttribute('Label') ?? ''
            });
          }
          
          properties['options'] = options;
        }
      }
      // Handle other complex properties by tag
      else {
        // Store the XML string for advanced processing later
        properties[tag] = complexProps.toXmlString();
      }
    }
    
    // Parse ControlProperties for additional settings
    final controlPropsElement = element.findElements('ControlProperties').firstOrNull;
    if (controlPropsElement != null) {
      Map<String, String> controlProps = {};
      for (var prop in controlPropsElement.childElements) {
        final propName = prop.name.local;
        final propValue = prop.innerText;
        controlProps[propName] = propValue;
      }
      properties['controlProperties'] = controlProps;
    }
    
    return ControlModel(
      name: name,
      type: type,
      controlType: controlType,
      text: text,
      position: position,
      size: size,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      properties: properties,
      stateVariables: stateVariables,
    );
  }
  
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
  
  static ControlType _determineControlType(String typeString) {
    if (typeString.contains('Button')) return ControlType.button;
    if (typeString.contains('Slider')) return ControlType.fader;
    if (typeString.contains('Meter')) return ControlType.meter;
    if (typeString.contains('ComboBox')) return ControlType.selector;
    if (typeString.contains('Annotation')) return ControlType.label;
    if (typeString.contains('Rectangle')) return ControlType.rectangle;
    return ControlType.unknown;
  }
  
  // Helper method to get protocol address for this control
  String? getPrimaryAddress() {
    if (stateVariables.isEmpty) return null;
    String address = stateVariables.first.hiQnetAddress;
    // Ensure address is properly formatted and lowercase for consistent comparisons
    return address.toLowerCase();
  }
  
  // Helper method to get parameter ID for this control
  String? getPrimaryParameterId() {
    if (stateVariables.isEmpty) return null;
    String paramId = stateVariables.first.parameterID;
    // Ensure parameter ID is properly formatted and lowercase for consistent comparisons
    return paramId.toLowerCase();
  }
  
  // Get all state variables for this control
  List<StateVariableItem> getStateVariables() {
    return stateVariables;
  }
  
  // Check if control has a state variable
  bool hasStateVariable() {
    return stateVariables.isNotEmpty;
  }
  
  // Get control properties
  Map<String, dynamic> getProperties() {
    return properties;
  }
  
  // Check if control has specific property
  bool hasProperty(String key) {
    return properties.containsKey(key);
  }
  
  // Get a specific property value
  dynamic getProperty(String key, [dynamic defaultValue]) {
    return properties[key] ?? defaultValue;
  }
}