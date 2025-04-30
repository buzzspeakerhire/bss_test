import 'package:flutter/material.dart';
import 'models/panel_model.dart';
import 'models/control_types.dart';
import 'control_renderers/bare_fader_renderer.dart';
import 'control_renderers/selector_renderer.dart';

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
    // Get faders and source selectors from the panel
    final faders = widget.panel.findControlsByType(ControlType.fader);
    final selectors = widget.panel.findControlsByType(ControlType.selector);
    
    // Debug information about controls found
    debugPrint('Found ${faders.length} faders and ${selectors.length} selectors');
    
    // Calculate available screen dimensions
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height - 
                        kToolbarHeight - 
                        MediaQuery.of(context).padding.top -
                        MediaQuery.of(context).padding.bottom - 
                        50; // Extra padding for the label at bottom
    
    // Find the bounds of all controls
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = 0;
    double maxY = 0;
    
    // Process all controls to find bounds
    final allControls = [...faders, ...selectors];
    for (final control in allControls) {
      minX = control.position.dx < minX ? control.position.dx : minX;
      minY = control.position.dy < minY ? control.position.dy : minY;
      maxX = (control.position.dx + control.size.width) > maxX ? (control.position.dx + control.size.width) : maxX;
      maxY = (control.position.dy + control.size.height) > maxY ? (control.position.dy + control.size.height) : maxY;
    }
    
    // Add a buffer around the region
    minX = minX - 20;
    minY = minY - 20;
    maxX = maxX + 20;
    maxY = maxY + 20;
    
    // Calculate control region dimensions
    final regionWidth = maxX - minX;
    final regionHeight = maxY - minY;
    
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
    _scaleFactor = _scaleFactor * 0.75; // 75% of calculated scale
    
    return Scaffold(
      appBar: AppBar(
        title: Text(_shouldRotate 
            ? 'Rotated Controls: ${widget.panel.name}' 
            : 'Controls: ${widget.panel.name}'),
      ),
      body: Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        child: Column(
          children: [
            // Main view with rotation if needed
            Expanded(
              child: Center(
                // We need to use a GestureDetector that doesn't handle events but passes them through
                child: AbsorbPointer(
                  absorbing: false,
                  child: _shouldRotate
                      ? RotatedBox(
                          quarterTurns: 1, // 90 degrees clockwise
                          child: _buildDirectInteractionLayout(faders, selectors, minX, minY, _scaleFactor),
                        )
                      : _buildDirectInteractionLayout(faders, selectors, minX, minY, _scaleFactor),
                ),
              ),
            ),
            
            // Control count indicator
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                'Faders: ${faders.length}, Selectors: ${selectors.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            
            // Scale indicator
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
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
  
  // New approach using direct controls for better interaction
  Widget _buildDirectInteractionLayout(List<dynamic> faders, List<dynamic> selectors, double minX, double minY, double scaleFactor) {
    return Transform.scale(
      scale: scaleFactor,
      alignment: Alignment.center,
      child: Container(
        color: widget.panel.backgroundColor,
        child: Stack(
          fit: StackFit.loose,
          children: [
            // First render selectors
            ...selectors.map((selector) => Positioned(
              left: selector.position.dx - minX,
              top: selector.position.dy - minY,
              width: selector.size.width,
              height: selector.size.height,
              child: _buildInteractiveSelector(selector),
            )),
            
            // Then render faders on top for better interaction
            ...faders.map((fader) => Positioned(
              left: fader.position.dx - minX,
              top: fader.position.dy - minY,
              width: fader.size.width,
              height: fader.size.height,
              child: BareFaderRenderer(control: fader),
            )),
          ],
        ),
      ),
    );
  }
  
  // Custom interactive selector that ensures proper gesture handling
  Widget _buildInteractiveSelector(dynamic selector) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // When tapped, show a dialog with options
          _showSelectorOptions(selector);
        },
        child: Container(
          decoration: BoxDecoration(
            color: selector.backgroundColor,
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selector.name,
                  style: TextStyle(
                    color: selector.foregroundColor,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 14),
            ],
          ),
        ),
      ),
    );
  }
  
  // Show selector options dialog
  void _showSelectorOptions(dynamic selector) {
    final options = selector.properties['options'] as List<dynamic>? ?? [];
    if (options.isEmpty) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select ${selector.name}'),
        content: SizedBox(
          width: double.minPositive,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(options[index]['label'] ?? 'Option ${index + 1}'),
                onTap: () {
                  // Here you would implement the actual selection
                  // and send it to the device using your communication system
                  debugPrint('Selected ${options[index]['label']} for ${selector.name}');
                  Navigator.of(context).pop();
                },
              );
            },
          ),
        ),
      ),
    );
  }
}