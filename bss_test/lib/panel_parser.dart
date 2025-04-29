import 'dart:io';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:file_picker/file_picker.dart';
import 'models/panel_model.dart';
import 'models/control_model.dart';
import 'models/control_types.dart';  // Added this import

class PanelParser {
  /// Loads a panel file from device storage and returns the parsed PanelModel
  Future<PanelModel?> loadPanelFromStorage() async {
    try {
      // Use FileType.any like your working implementation
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false,
        withReadStream: false,
        // Removed allowCompression since it's deprecated
      );

      if (result == null || result.files.isEmpty || result.files.first.path == null) {
        debugPrint('No file selected');
        return null;
      }
      
      // Use simple File access
      final file = File(result.files.first.path!);
      final xmlString = await file.readAsString();
      
      // Parse the XML string
      return parseXmlString(xmlString);
    } catch (e) {
      debugPrint('Error loading panel file: $e');
      return null;
    }
  }
  
  /// Parses a panel XML string into a PanelModel
  PanelModel? parseXmlString(String xmlString) {
    try {
      final document = XmlDocument.parse(xmlString);
      
      // Find the Panel element
      final panelElement = document.findAllElements('Panel').firstOrNull;
      if (panelElement == null) {
        debugPrint('No Panel element found in XML');
        return null;
      }
      
      // Create panel model from XML
      final panel = PanelModel.fromXmlElement(panelElement);
      
      // Extract controls (basic implementation for now)
      final controlElements = panelElement.findElements('Control');
      final controls = controlElements.map((element) => 
        ControlModel.fromXmlElement(element)).toList();
      
      // Return the panel with controls
      return PanelModel(
        name: panel.name,
        text: panel.text,
        version: panel.version,
        size: panel.size,
        backgroundColor: panel.backgroundColor,
        foregroundColor: panel.foregroundColor,
        controls: controls,
        properties: panel.properties,
      );
    } catch (e) {
      debugPrint('Error parsing panel XML: $e');
      return null;
    }
  }
  
  /// Prints panel information for debugging purposes
  void printPanelInfo(PanelModel panel) {
    debugPrint('Panel: ${panel.name} (${panel.text})');
    debugPrint('Size: ${panel.size.width.toInt()} x ${panel.size.height.toInt()}');
    debugPrint('Controls: ${panel.controls.length}');
    
    // Count by control type
    final buttonCount = panel.findControlsByType(ControlType.button).length;
    final faderCount = panel.findControlsByType(ControlType.fader).length;
    final meterCount = panel.findControlsByType(ControlType.meter).length;
    final selectorCount = panel.findControlsByType(ControlType.selector).length;
    
    debugPrint('Control types: Buttons: $buttonCount, Faders: $faderCount, Meters: $meterCount, Selectors: $selectorCount');
    
    // Print the first few controls as examples
    final maxControls = panel.controls.length > 5 ? 5 : panel.controls.length;
    for (var i = 0; i < maxControls; i++) {
      final control = panel.controls[i];
      debugPrint('- ${control.name}: ${control.type} at ${control.position.dx.toInt()},${control.position.dy.toInt()}');
      if (control.stateVariables.isNotEmpty) {
        debugPrint('  Address: ${control.getPrimaryAddress()}, Param: ${control.getPrimaryParameterId()}');
      }
    }
  }
}