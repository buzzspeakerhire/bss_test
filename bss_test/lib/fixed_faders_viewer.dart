import 'package:flutter/material.dart';
import 'models/panel_model.dart';
import 'models/control_types.dart';
import 'control_renderers/bare_fader_renderer.dart';

class FixedFadersViewer extends StatefulWidget {
  final PanelModel panel;
  
  const FixedFadersViewer({
    super.key,
    required this.panel,
  });

  @override
  State<FixedFadersViewer> createState() => _FixedFadersViewerState();
}

class _FixedFadersViewerState extends State<FixedFadersViewer> {
  // Fixed scaling factor - will be calculated once
  double _scaleFactor = 1.0;
  
  // Whether the panel should be rotated
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
    // Get only the faders from the panel
    final faders = widget.panel.findControlsByType(ControlType.fader);
    
    // Calculate available screen dimensions
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height - 
                        kToolbarHeight - 
                        MediaQuery.of(context).padding.top -
                        MediaQuery.of(context).padding.bottom - 
                        50; // Extra padding for the label at bottom
    
    // Find the bounds of the fader area
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = 0;
    double maxY = 0;
    
    for (final fader in faders) {
      minX = fader.position.dx < minX ? fader.position.dx : minX;
      minY = fader.position.dy < minY ? fader.position.dy : minY;
      maxX = (fader.position.dx + fader.size.width) > maxX ? (fader.position.dx + fader.size.width) : maxX;
      maxY = (fader.position.dy + fader.size.height) > maxY ? (fader.position.dy + fader.size.height) : maxY;
    }
    
    // Calculate fader region dimensions
    final regionWidth = maxX - minX;
    final regionHeight = maxY - minY;
    
    debugPrint('Fader region: $minX,$minY to $maxX,$maxY ($regionWidth x $regionHeight)');
    
    // Calculate scale factor based on whether we're rotating or not
    if (_shouldRotate) {
      // When rotating, swap width and height for calculation
      final scaleFactor1 = screenWidth / regionHeight;
      final scaleFactor2 = screenHeight / regionWidth;
      _scaleFactor = scaleFactor1 < scaleFactor2 ? scaleFactor1 : scaleFactor2;
    } else {
      // Normal orientation
      final scaleFactor1 = screenWidth / regionWidth;
      final scaleFactor2 = screenHeight / regionHeight;
      _scaleFactor = scaleFactor1 < scaleFactor2 ? scaleFactor1 : scaleFactor2;
    }
    
    // Apply a safety margin to ensure everything is visible
    _scaleFactor = _scaleFactor * 0.90; // 90% of calculated scale
    
    return Scaffold(
      appBar: AppBar(
        title: Text(_shouldRotate 
            ? 'Rotated Faders: ${widget.panel.name}' 
            : 'Faders: ${widget.panel.name}'),
      ),
      body: Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        child: Column(
          children: [
            // Main fader view with rotation if needed
            Expanded(
              child: Center(
                child: _shouldRotate
                    ? RotatedBox(
                        quarterTurns: 1, // 90 degrees clockwise
                        child: _buildFaderRegion(faders, minX, minY, maxX, maxY),
                      )
                    : _buildFaderRegion(faders, minX, minY, maxX, maxY),
              ),
            ),
            
            // Scale indicator
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
              child: Text(
                'Optimized view: ${(_scaleFactor * 100).toStringAsFixed(0)}% scale',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFaderRegion(List<dynamic> faders, double minX, double minY, double maxX, double maxY) {
    // Calculate region dimensions
    final regionWidth = maxX - minX;
    final regionHeight = maxY - minY;
    
    return Transform.scale(
      scale: _scaleFactor,
      alignment: Alignment.center,
      child: SizedBox(
        width: regionWidth,
        height: regionHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Background
            Positioned.fill(
              child: Container(
                color: widget.panel.backgroundColor,
              ),
            ),
            
            // Position faders relative to the region's top-left corner
            ...faders.map((fader) => Positioned(
              left: fader.position.dx - minX, // Offset by minX to align with region
              top: fader.position.dy - minY,  // Offset by minY to align with region
              width: fader.size.width,
              height: fader.size.height,
              child: BareFaderRenderer(control: fader),
            )),
          ],
        ),
      ),
    );
  }
}