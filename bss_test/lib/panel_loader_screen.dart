import 'package:flutter/material.dart';
import 'panel_parser.dart';
import 'models/panel_model.dart';
import 'models/control_types.dart';
import 'panel_viewer.dart';

class PanelLoaderScreen extends StatefulWidget {
  const PanelLoaderScreen({super.key});

  @override
  State<PanelLoaderScreen> createState() => _PanelLoaderScreenState();
}

class _PanelLoaderScreenState extends State<PanelLoaderScreen> {
  PanelModel? _loadedPanel;
  String _statusMessage = 'No panel loaded';
  final _panelParser = PanelParser();

  Future<void> _loadPanel() async {
    setState(() {
      _statusMessage = 'Loading panel...';
    });

    final panel = await _panelParser.loadPanelFromStorage();
    
    setState(() {
      if (panel != null) {
        _loadedPanel = panel;
        _statusMessage = 'Panel loaded: ${panel.name} with ${panel.controls.length} controls';
        _panelParser.printPanelInfo(panel);
      } else {
        _statusMessage = 'Failed to load panel';
      }
    });
  }

  void _viewPanel() {
    if (_loadedPanel == null) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PanelViewer(panel: _loadedPanel!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BSS Panel Loader'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _loadPanel,
              child: const Text('Load Panel File'),
            ),
            if (_loadedPanel != null) ...[
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _viewPanel,
                child: const Text('View Panel'),
              ),
            ],
            const SizedBox(height: 20),
            Text(_statusMessage),
            if (_loadedPanel != null) ...[
              const SizedBox(height: 20),
              Text('Panel: ${_loadedPanel!.name}'),
              Text('Size: ${_loadedPanel!.size.width.toInt()} x ${_loadedPanel!.size.height.toInt()}'),
              Text('Controls: ${_loadedPanel!.controls.length}'),
              
              // Add count by control type
              Text('Buttons: ${_loadedPanel!.findControlsByType(ControlType.button).length}'),
              Text('Faders: ${_loadedPanel!.findControlsByType(ControlType.fader).length}'),
              Text('Meters: ${_loadedPanel!.findControlsByType(ControlType.meter).length}'),
              Text('Selectors: ${_loadedPanel!.findControlsByType(ControlType.selector).length}'),
              
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: _loadedPanel!.controls.length,
                  itemBuilder: (context, index) {
                    final control = _loadedPanel!.controls[index];
                    return ListTile(
                      title: Text(control.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${control.type} at ${control.position.dx.toInt()},${control.position.dy.toInt()}'),
                          if (control.stateVariables.isNotEmpty)
                            Text('Address: ${control.getPrimaryAddress() ?? "None"}, Param: ${control.getPrimaryParameterId() ?? "None"}'),
                        ],
                      ),
                      dense: true,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}