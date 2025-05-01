import 'package:flutter/material.dart';
import '../../models/panel_model.dart';
import '../../control_renderers/control_renderer_factory.dart';

class PanelViewer extends StatefulWidget {
  final PanelModel panel;
  
  const PanelViewer({
    super.key,
    required this.panel,
  });

  @override
  State<PanelViewer> createState() => _PanelViewerState();
}

class _PanelViewerState extends State<PanelViewer> {
  // Track the scale of the panel
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  final _transformationController = TransformationController();
  
  void _updateTransformation() {
    final matrix = Matrix4.identity();
    matrix.translate(_offset.dx, _offset.dy);
    matrix.scale(_scale);
    _transformationController.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Panel: ${widget.panel.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_in),
            onPressed: () {
              setState(() {
                _scale = _scale * 1.2;
                _updateTransformation();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            onPressed: () {
              setState(() {
                _scale = _scale / 1.2;
                _updateTransformation();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen),
            onPressed: () {
              setState(() {
                _scale = 1.0;
                _offset = Offset.zero;
                _updateTransformation();
              });
            },
          ),
        ],
      ),
      body: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _offset += details.delta;
            _updateTransformation();
          });
        },
        child: ClipRect(
          child: ColoredBox(
            color: Colors.grey[800]!,
            child: InteractiveViewer(
              boundaryMargin: const EdgeInsets.all(double.infinity),
              minScale: 0.1,
              maxScale: 4.0,
              transformationController: _transformationController,
              child: Stack(
                children: [
                  // Panel background
                  Container(
                    width: widget.panel.size.width,
                    height: widget.panel.size.height,
                    color: widget.panel.backgroundColor,
                  ),
                  
                  // Controls
                  ...widget.panel.controls.map((control) => Positioned(
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
    );
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }
}