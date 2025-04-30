import 'package:flutter/material.dart';
import 'models/panel_model.dart';
import 'models/control_types.dart';
import 'control_renderers/bare_fader_renderer.dart';
import 'control_renderers/control_renderer_factory.dart';
import 'helpers/orientation_helper.dart';

class ScalablePanelViewer extends StatefulWidget {
  final PanelModel panel;
  final bool fadersOnly;
  
  const ScalablePanelViewer({
    super.key,
    required this.panel,
    this.fadersOnly = false,
  });

  @override
  State<ScalablePanelViewer> createState() => _ScalablePanelViewerState();
}

class _ScalablePanelViewerState extends State<ScalablePanelViewer> {
  // Transformation controller for zoom and pan
  final _transformationController = TransformationController();
  
  // Min/max scaling limits
  final double _minScale = 0.1;
  final double _maxScale = 5.0;
  
  // Padding around the panel (in screen pixels)
  final double _panelPadding = 8.0;
  
  // Whether to auto-fit on first build
  bool _needsInitialFit = true;
  
  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }
  
  // Reset transformation to fit the screen
  void _resetTransformation(BoxConstraints constraints) {
    final matrix = OrientationHelper.getOptimalTransformationMatrix(
      widget.panel.size,
      Size(constraints.maxWidth, constraints.maxHeight),
      padding: _panelPadding,
    );
    
    setState(() {
      _transformationController.value = matrix;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    // Get current screen orientation and size
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fadersOnly 
            ? 'Scalable Faders: ${widget.panel.name}' 
            : 'Scalable Panel: ${widget.panel.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.fit_screen),
            onPressed: () {
              // Use post-frame callback to ensure constraints are available
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  _resetTransformation(
                    BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width,
                      maxHeight: MediaQuery.of(context).size.height -
                          (kToolbarHeight + MediaQuery.of(context).padding.top),
                    ),
                  );
                }
              });
            },
            tooltip: 'Fit to screen',
          ),
          IconButton(
            icon: isLandscape 
                ? const Icon(Icons.stay_current_portrait)
                : const Icon(Icons.stay_current_landscape),
            onPressed: () {
              // This is just an indicator - can't force orientation
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(isLandscape 
                      ? 'Rotate device to portrait mode'
                      : 'Rotate device to landscape mode'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            tooltip: isLandscape ? 'Portrait recommended' : 'Landscape recommended',
          ),
        ],
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return LayoutBuilder(
            builder: (context, constraints) {
              // Apply initial fit if needed
              if (_needsInitialFit) {
                _needsInitialFit = false;
                // Use post-frame callback to avoid calling setState during build
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    _resetTransformation(constraints);
                  }
                });
              }
              
              // Calculate scale factor for info display
              final scalePercent = OrientationHelper.calculateScaleFactor(
                widget.panel.size, 
                Size(constraints.maxWidth, constraints.maxHeight),
                padding: _panelPadding,
              ) * 100;
              
              return Stack(
                children: [
                  // Panel InteractiveViewer
                  Container(
                    color: Colors.black,
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: _minScale,
                      maxScale: _maxScale,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      clipBehavior: Clip.none,
                      child: SizedBox(
                        width: widget.panel.size.width,
                        height: widget.panel.size.height,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Background
                            Container(
                              width: widget.panel.size.width,
                              height: widget.panel.size.height,
                              color: widget.panel.backgroundColor,
                            ),
                            
                            // Controls - conditionally render based on fadersOnly flag
                            ...widget.panel.controls
                                .where((control) => !widget.fadersOnly || control.controlType == ControlType.fader)
                                .map((control) => Positioned(
                                  left: control.position.dx,
                                  top: control.position.dy,
                                  width: control.size.width,
                                  height: control.size.height,
                                  child: control.controlType == ControlType.fader
                                      ? BareFaderRenderer(control: control)
                                      : widget.fadersOnly 
                                          ? Container() // Empty if faders only and not a fader
                                          : ControlRendererFactory.createRenderer(control),
                                )),
                                
                            // Panel border for visibility
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white.withAlpha(51), // 0.2 opacity (51/255)
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Info overlay (scale percentage, etc.)
                  Positioned(
                    right: 8,
                    bottom: 8 + (MediaQuery.of(context).padding.bottom),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(153), // 0.6 opacity (153/255)
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Scale: ${scalePercent.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      // Add floating action buttons for quick zooming
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'zoomIn',
            mini: true,
            child: const Icon(Icons.zoom_in),
            onPressed: () {
              final matrix = _transformationController.value.clone();
              matrix.scale(1.2, 1.2);
              setState(() {
                _transformationController.value = matrix;
              });
            },
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'zoomOut',
            mini: true,
            child: const Icon(Icons.zoom_out),
            onPressed: () {
              final matrix = _transformationController.value.clone();
              matrix.scale(0.8, 0.8);
              setState(() {
                _transformationController.value = matrix;
              });
            },
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'fitScreen',
            child: const Icon(Icons.fit_screen),
            onPressed: () {
              // Use the current layout constraints
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  _resetTransformation(
                    BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width,
                      maxHeight: MediaQuery.of(context).size.height -
                          (kToolbarHeight + MediaQuery.of(context).padding.top),
                    ),
                  );
                }
              });
            },
          ),
        ],
      ),
    );
  }
}