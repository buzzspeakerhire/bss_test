import 'package:flutter/material.dart';
import 'models/panel_model.dart';
import 'models/control_types.dart'; // Added this import for ControlType
import 'control_renderers/control_renderer_factory.dart';

class RotatedPanelViewer extends StatefulWidget {
  final PanelModel panel;
  final bool fadersOnly;
  
  const RotatedPanelViewer({
    super.key,
    required this.panel,
    this.fadersOnly = false,
  });

  @override
  State<RotatedPanelViewer> createState() => _RotatedPanelViewerState();
}

class _RotatedPanelViewerState extends State<RotatedPanelViewer> {
  // Fixed scaling factor - will be calculated based on screen size
  double _scaleFactor = 1.0;
  
  // Whether the panel should be rotated (determined by panel dimensions)
  bool _shouldRotate = false;
  
  @override
  void initState() {
    super.initState();
    
    // Determine if rotation is needed based on panel dimensions
    _shouldRotate = widget.panel.size.width > widget.panel.size.height;
    debugPrint('Panel dimensions: ${widget.panel.size.width} x ${widget.panel.size.height}');
    debugPrint('Should rotate: $_shouldRotate');
  }
  
  @override
  Widget build(BuildContext context) {
    // Get available screen dimensions
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height - 
                        kToolbarHeight - 
                        MediaQuery.of(context).padding.top -
                        MediaQuery.of(context).padding.bottom;
    
    // Calculate panel dimensions after potential rotation
    final panelWidth = _shouldRotate ? widget.panel.size.height : widget.panel.size.width;
    final panelHeight = _shouldRotate ? widget.panel.size.width : widget.panel.size.height;
    
    // Calculate scaling factors
    final scaleX = screenWidth / panelWidth;
    final scaleY = screenHeight / panelHeight;
    
    // Use the smaller scale factor to ensure the entire panel fits
    _scaleFactor = scaleX < scaleY ? scaleX : scaleY;
    
    // Apply a maximum scale limit to prevent controls from becoming too large
    _scaleFactor = _scaleFactor.clamp(0.1, 2.0);
    
    // Create a scaled and potentially rotated panel
    return Scaffold(
      appBar: AppBar(
        title: Text('${_shouldRotate ? "Rotated" : "Scaled"} ${widget.fadersOnly ? "Faders" : "Panel"}: ${widget.panel.name}'),
      ),
      body: Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: panelWidth * _scaleFactor,
              height: panelHeight * _scaleFactor,
              child: RotatedBox(
                quarterTurns: _shouldRotate ? 1 : 0, // Rotate if panel is wider than tall
                child: SizedBox(
                  width: widget.panel.size.width,
                  height: widget.panel.size.height,
                  child: Stack(
                    children: [
                      // Background
                      Container(
                        width: widget.panel.size.width,
                        height: widget.panel.size.height,
                        color: widget.panel.backgroundColor,
                      ),
                      
                      // Controls - render all or just faders based on fadersOnly flag
                      ...widget.panel.controls
                          .where((control) => !widget.fadersOnly || control.controlType == ControlType.fader)
                          .map((control) => Positioned(
                            left: control.position.dx,
                            top: control.position.dy,
                            width: control.size.width,
                            height: control.size.height,
                            child: ControlRendererFactory.createRenderer(control),
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      // Scale indicator
      bottomSheet: Container(
        color: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Text(
            'Optimized view: ${(_scaleFactor * 100).toStringAsFixed(0)}% scale',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ),
    );
  }
}