import 'package:flutter/material.dart';
import 'panel_parser.dart';
import 'models/panel_model.dart';
import 'models/control_model.dart';

class PanelLoaderScreen extends StatefulWidget {
  const PanelLoaderScreen({Key? key}) : super(key: key);

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
            const SizedBox(height: 20),
            Text(_statusMessage),
            if (_loadedPanel != null) ...[
              const SizedBox(height: 20),
              Text('Panel: ${_loadedPanel!.name}'),
              Text('Size: ${_loadedPanel!.size.width.toInt()} x ${_loadedPanel!.size.height.toInt()}'),
              Text('Controls: ${_loadedPanel!.controls.length}'),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: _loadedPanel!.controls.length,
                  itemBuilder: (context, index) {
                    final control = _loadedPanel!.controls[index];
                    return ListTile(
                      title: Text(control.name),
                      subtitle: Text('${control.type} at ${control.position.dx.toInt()},${control.position.dy.toInt()}'),
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