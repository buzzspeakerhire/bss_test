import 'package:flutter/material.dart';
import '../../models/panel_model.dart';
import '../../models/control_types.dart';
import '../../control_renderers/bare_fader_renderer.dart';

class FadersOnlyPanelViewer extends StatelessWidget {
  final PanelModel panel;
  
  const FadersOnlyPanelViewer({
    super.key,
    required this.panel,
  });

  @override
  Widget build(BuildContext context) {
    // Get only the faders from the panel
    final faders = panel.findControlsByType(ControlType.fader);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Faders: ${panel.name}'),
      ),
      body: Stack(
        children: [
          // Plain background - no decorations
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
          ),
          
          // Only render the faders
          ...faders.map((fader) => Positioned(
            left: fader.position.dx,
            top: fader.position.dy,
            width: fader.size.width,
            height: fader.size.height,
            child: BareFaderRenderer(control: fader),
          )),
        ],
      ),
    );
  }
}