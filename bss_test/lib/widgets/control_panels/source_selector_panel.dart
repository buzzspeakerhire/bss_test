import 'package:flutter/material.dart';
import '../../services/control_communication_service.dart';

class SourceSelectorPanel extends StatefulWidget {
  final bool isConnected;
  
  const SourceSelectorPanel({
    super.key,
    required this.isConnected,
  });

  @override
  State<SourceSelectorPanel> createState() => _SourceSelectorPanelState();
}

class _SourceSelectorPanelState extends State<SourceSelectorPanel> {
  final _controlService = ControlCommunicationService();
  
  // Text controllers
  final _sourceHiQnetAddressController = TextEditingController(text: "0x2D6803000300");
  final _sourceParamIdController = TextEditingController(text: "0x0");
  
  // Control values
  int _sourceValue = 0; // Current source selection
  int _numSourceOptions = 8; // Number of source options available
  
  @override
  void initState() {
    super.initState();
    
    // Listen for source updates
    _controlService.onSourceUpdate.listen((data) {
      final address = _sourceHiQnetAddressController.text;
      final paramId = _sourceParamIdController.text;
      
      if (data['address'] == address && data['paramId'] == paramId) {
        setState(() {
          _sourceValue = data['value'];
        });
      }
    });
  }
  
  @override
  void dispose() {
    _sourceHiQnetAddressController.dispose();
    _sourceParamIdController.dispose();
    super.dispose();
  }
  
  // Update source selection
  void _updateSourceSelection(int? value) {
    if (value != null) {
      setState(() {
        _sourceValue = value;
      });
      
      if (widget.isConnected) {
        _controlService.setSourceValue(
          _sourceHiQnetAddressController.text,
          _sourceParamIdController.text,
          _sourceValue,
        );
      }
    }
  }
  
  // Update number of source options
  void _updateNumSourceOptions(String value) {
    int? numOptions = int.tryParse(value);
    if (numOptions != null && numOptions > 0) {
      setState(() {
        _numSourceOptions = numOptions;
        // Make sure current selection is valid
        if (_sourceValue >= _numSourceOptions) {
          _sourceValue = _numSourceOptions - 1;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Source Selector', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sourceHiQnetAddressController,
                    decoration: const InputDecoration(
                      labelText: 'HiQnet Address',
                      border: OutlineInputBorder(),
                      hintText: 'Example: 0x2D6803000300',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _sourceParamIdController,
                    decoration: const InputDecoration(
                      labelText: 'Param ID',
                      border: OutlineInputBorder(),
                      hintText: 'Example: 0x0',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Number of Options:'),
                const SizedBox(width: 16),
                SizedBox(
                  width: 80,
                  child: TextField(
                    // Fixed: Using controller instead of initialValue
                    controller: TextEditingController(text: _numSourceOptions.toString()),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: _updateNumSourceOptions,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Source Input:'),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _sourceValue,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    ),
                    items: List.generate(_numSourceOptions, (index) {
                      return DropdownMenuItem<int>(
                        value: index,
                        child: Text('Input ${index + 1}'),
                      );
                    }),
                    onChanged: widget.isConnected ? _updateSourceSelection : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Quick select buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                _numSourceOptions > 8 ? 8 : _numSourceOptions, 
                (index) => ElevatedButton(
                  onPressed: widget.isConnected ? () => _updateSourceSelection(index) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _sourceValue == index ? Theme.of(context).primaryColor : null,
                    foregroundColor: _sourceValue == index ? Colors.white : null,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: Text('${index + 1}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}