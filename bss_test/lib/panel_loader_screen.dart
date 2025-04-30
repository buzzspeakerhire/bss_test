import 'package:flutter/material.dart';
import 'panel_parser.dart';
import 'models/panel_model.dart';
import 'models/control_types.dart';
import 'panel_viewer.dart';
import 'faders_only_panel_viewer.dart';
import 'scalable_panel_viewer.dart';
import 'fixed_faders_viewer.dart';

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
  
  void _viewFadersOnly() {
    if (_loadedPanel == null) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FadersOnlyPanelViewer(panel: _loadedPanel!),
      ),
    );
  }
  
  void _viewScalablePanel() {
    if (_loadedPanel == null) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ScalablePanelViewer(panel: _loadedPanel!),
      ),
    );
  }
  
  void _viewScalableFadersOnly() {
    if (_loadedPanel == null) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ScalablePanelViewer(panel: _loadedPanel!, fadersOnly: true),
      ),
    );
  }
  
  void _viewFixedFaders() {
    if (_loadedPanel == null) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FixedFadersViewer(panel: _loadedPanel!),
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
              const SizedBox(height: 16),
              // Highlight the recommended option
              ElevatedButton(
                onPressed: _viewFixedFaders,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('View Optimized Faders'),
              ),
              
              const SizedBox(height: 16),
              const Text('Other View Options:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _viewPanel,
                    child: const Text('Original Panel'),
                  ),
                  ElevatedButton(
                    onPressed: _viewFadersOnly,
                    child: const Text('Original Faders'),
                  ),
                  ElevatedButton(
                    onPressed: _viewScalablePanel,
                    child: const Text('Scalable Panel'),
                  ),
                  ElevatedButton(
                    onPressed: _viewScalableFadersOnly,
                    child: const Text('Scalable Faders'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Text(_statusMessage),
            if (_loadedPanel != null) ...[
              const SizedBox(height: 20),
              Text('Panel: ${_loadedPanel!.name}'),
              Text('Size: ${_loadedPanel!.size.width.toInt()} x ${_loadedPanel!.size.height.toInt()}'),
              Text('Controls: ${_loadedPanel!.controls.length}'),
              
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _controlInfoBox('Buttons', _loadedPanel!.findControlsByType(ControlType.button).length),
                  _controlInfoBox('Faders', _loadedPanel!.findControlsByType(ControlType.fader).length),
                  _controlInfoBox('Meters', _loadedPanel!.findControlsByType(ControlType.meter).length),
                  _controlInfoBox('Selectors', _loadedPanel!.findControlsByType(ControlType.selector).length),
                ],
              ),
              
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
  
  // Helper widget to display control counts in a nicer format
  Widget _controlInfoBox(String label, int count) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(count.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}