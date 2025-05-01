import 'package:flutter/material.dart';
import '../models/panel_model.dart';
import '../models/control_model.dart';
import '../models/control_types.dart';
import '../control_renderers/bare_fader_renderer.dart';
import '../control_renderers/selector_renderer.dart';
import '../helpers/orientation_helper.dart';

class FadersAndSourcePanelViewer extends StatefulWidget {
  final PanelModel panel;
  
  const FadersAndSourcePanelViewer({
    super.key,
    required this.panel,
  });

  @override
  State<FadersAndSourcePanelViewer> createState() => _FadersAndSourcePanelViewerState();
}

class _FadersAndSourcePanelViewerState extends State<FadersAndSourcePanelViewer> {
  // Scale factor for the panel
  double _scaleFactor = 1.0;
  
  // Controls list
  late List<ControlModel> _faders;
  late List<ControlModel> _sourceSelectors;
  
  // Controller for transformations
  final _transformationController = TransformationController();
  
  @override
  void initState() {
    super.initState();
    
    // Extract only faders and source selectors
    _faders = widget.panel.findControlsByType(ControlType.fader);
    _sourceSelectors = widget.panel.findControlsByType(ControlType.selector);
    
    // Log found controls
    debugPrint('Found ${_faders.length} faders and ${_sourceSelectors.length} source selectors');
  }
  
  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Faders & Sources: ${widget.panel.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_in),
            onPressed: () {
              setState(() {
                _scaleFactor *= 1.2;
                _updateTransformation();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            onPressed: () {
              setState(() {
                _scaleFactor /= 1.2;
                _updateTransformation();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen),
            onPressed: _resetScaleToFit,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate optimal scale when layout is built
          if (_scaleFactor == 1.0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _calculateOptimalScale(constraints);
            });
          }
          
          return Container(
            color: Colors.black,
            child: InteractiveViewer(
              transformationController: _transformationController,
              boundaryMargin: const EdgeInsets.all(20.0),
              minScale: 0.1,
              maxScale: 5.0,
              child: SizedBox(
                width: widget.panel.size.width,
                height: widget.panel.size.height,
                child: _buildPanelContent(),
              ),
            ),
          );
        },
      ),
      bottomSheet: Container(
        color: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Faders: ${_faders.length}, Sources: ${_sourceSelectors.length} | ',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              'Scale: ${(_scaleFactor * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
  
  // Build the panel content with faders and source selectors
  Widget _buildPanelContent() {
    return Stack(
      children: [
        // Panel background
        Container(
          width: widget.panel.size.width,
          height: widget.panel.size.height,
          color: widget.panel.backgroundColor,
        ),
        
        // Panel border for visibility
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
          ),
        ),
        
        // Source selectors first (so they appear below faders)
        ..._sourceSelectors.map((control) => Positioned(
          left: control.position.dx,
          top: control.position.dy,
          width: control.size.width,
          height: control.size.height,
          child: SelectorRenderer(control: control),
        )),
        
        // Then faders on top
        ..._faders.map((control) => Positioned(
          left: control.position.dx,
          top: control.position.dy,
          width: control.size.width,
          height: control.size.height,
          child: BareFaderRenderer(control: control),
        )),
        
        // Optional: Add control labels for better visibility
        ..._faders.map((control) => Positioned(
          left: control.position.dx,
          top: control.position.dy + control.size.height,
          width: control.size.width,
          height: 15, // Small height for label
          child: Text(
            control.name,
            style: const TextStyle(color: Colors.white70, fontSize: 9),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        )),
      ],
    );
  }
  
  // Calculate the optimal scale factor
  void _calculateOptimalScale(BoxConstraints constraints) {
    // Get screen dimensions
    final screenWidth = constraints.maxWidth;
    final screenHeight = constraints.maxHeight;
    
    // Calculate the scale factor
    final scaleX = screenWidth / widget.panel.size.width;
    final scaleY = screenHeight / widget.panel.size.height;
    
    // Use the smaller scale factor to ensure content fits
    final newScale = scaleX < scaleY ? scaleX : scaleY;
    
    // Apply a margin factor
    final scaleFactor = newScale * 0.9; // 90% of available space
    
    setState(() {
      _scaleFactor = scaleFactor;
      _updateTransformation();
    });
  }
  
  // Reset scale to fit the screen
  void _resetScaleToFit() {
    // Get screen dimensions
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height - 
                         kToolbarHeight - 
                         MediaQuery.of(context).padding.top -
                         MediaQuery.of(context).padding.bottom - 
                         30; // Extra space for bottom sheet
    
    // Calculate the scale factor
    final scaleX = screenWidth / widget.panel.size.width;
    final scaleY = screenHeight / widget.panel.size.height;
    
    // Use the smaller scale factor to ensure content fits
    final newScale = scaleX < scaleY ? scaleX : scaleY;
    
    // Apply a margin factor
    final scaleFactor = newScale * 0.9; // 90% of available space
    
    setState(() {
      _scaleFactor = scaleFactor;
      _updateTransformation();
    });
  }
  
  // Update the transformation controller
  void _updateTransformation() {
    final matrix = Matrix4.identity();
    
    // Apply scaling
    matrix.scale(_scaleFactor, _scaleFactor);
    
    // Center content
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height - 
                       kToolbarHeight - 
                       MediaQuery.of(context).padding.top -
                       MediaQuery.of(context).padding.bottom - 
                       30; // Extra space for bottom sheet
    
    final scaledWidth = widget.panel.size.width * _scaleFactor;
    final scaledHeight = widget.panel.size.height * _scaleFactor;
    
    final dx = (screenWidth - scaledWidth) / 2 / _scaleFactor;
    final dy = (screenHeight - scaledHeight) / 2 / _scaleFactor;
    
    matrix.translate(dx, dy);
    
    _transformationController.value = matrix;
  }
}