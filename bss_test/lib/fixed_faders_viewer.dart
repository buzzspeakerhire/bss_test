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
  
  @override
  Widget build(BuildContext context) {
    // Get only the faders from the panel
    final faders = widget.panel.findControlsByType(ControlType.fader);
    
    // Sort faders by their x position from left to right
    faders.sort((a, b) => a.position.dx.compareTo(b.position.dx));
    
    // Calculate available screen width accounting for padding
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height - 
                         AppBar().preferredSize.height - 
                         MediaQuery.of(context).padding.top -
                         MediaQuery.of(context).padding.bottom;
    
    // Determine the needed width for all faders with spacing
    final totalOriginalWidth = faders.isNotEmpty 
        ? faders.last.position.dx + faders.last.size.width - faders.first.position.dx
        : 0.0;
    
    // Calculate scale factor based on screen width
    _scaleFactor = (screenWidth * 0.9) / totalOriginalWidth;
    
    // Limit scale factor to ensure faders aren't too small or large
    _scaleFactor = _scaleFactor.clamp(0.1, 2.0);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Faders: ${widget.panel.name}'),
      ),
      body: Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Horizontal row of faders - rotated 90 degrees from original
              SizedBox(
                height: 300, // Fixed height for the faders row
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: faders.map((fader) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: SizedBox(
                          width: 80, // Fixed width for each fader
                          height: 280, // Fixed height for each fader
                          child: Column(
                            children: [
                              // Add labels at the top
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Text(
                                  fader.name,
                                  style: TextStyle(
                                    color: fader.foregroundColor,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // The fader itself - direct renderer, not scaled or transformable
                              Expanded(
                                child: BareFaderRenderer(control: fader),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              // Add visual and text feedback that scaling was applied
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Text(
                  'Optimized view: ${(_scaleFactor * 100).toStringAsFixed(0)}% scale',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}