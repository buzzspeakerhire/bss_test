import 'package:flutter/material.dart';
import '../models/control_model.dart';
import '../services/global_state.dart';
import '../services/control_communication_service.dart';
import 'dart:async';

class SelectorRenderer extends StatefulWidget {
  final ControlModel control;
  
  const SelectorRenderer({
    super.key,
    required this.control,
  });

  @override
  State<SelectorRenderer> createState() => _SelectorRendererState();
}

class _SelectorRendererState extends State<SelectorRenderer> {
  final _globalState = GlobalState();
  final _controlService = ControlCommunicationService();
  int _currentValue = 0;
  
  // Stream subscription
  StreamSubscription? _sourceUpdateSubscription;
  
  @override
  void initState() {
    super.initState();
    
    try {
      final address = widget.control.getPrimaryAddress();
      final paramId = widget.control.getPrimaryParameterId();
      
      if (address == null || paramId == null) {
        debugPrint('SelectorRenderer: Missing address or paramId for ${widget.control.name}');
        return;
      }
      
      debugPrint('SelectorRenderer: Initializing ${widget.control.name} with address=$address, paramId=$paramId');
      
      // Listen for source updates
      _sourceUpdateSubscription = _controlService.onSourceUpdate.listen((data) {
        if (data['address'].toString().toLowerCase() == address.toLowerCase() && 
            data['paramId'].toString().toLowerCase() == paramId.toLowerCase()) {
          setState(() {
            _currentValue = data['value'] as int;
            debugPrint('SelectorRenderer: Updated source value: $_currentValue');
          });
        }
      });
      
      // Request current source value if connected
      if (_globalState.isConnected) {
        _controlService.subscribeSourceValue(address, paramId);
      }
    } catch (e) {
      debugPrint('Error in SelectorRenderer initState: $e');
    }
  }
  
  @override
  void dispose() {
    _sourceUpdateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final address = widget.control.getPrimaryAddress();
      final paramId = widget.control.getPrimaryParameterId();
      
      if (address == null || paramId == null) {
        // Fallback for controls without proper addressing
        return Container(
          decoration: BoxDecoration(
            color: Colors.red[100],
            border: Border.all(color: Colors.red),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Center(
            child: Text('Invalid Selector', style: TextStyle(color: Colors.red, fontSize: 10)),
          ),
        );
      }
      
      // Get options if they exist
      final options = widget.control.properties['options'] as List<dynamic>? ?? [];
      
      // Default label text
      String labelText = widget.control.text;
      
      // Get label based on current value if possible
      if (options.isNotEmpty && _currentValue >= 0 && _currentValue < options.length) {
        labelText = options[_currentValue]['label'] ?? widget.control.text;
      }
      
      return ListenableBuilder(
        listenable: _globalState,
        builder: (context, child) {
          return GestureDetector(
            onTap: _globalState.isConnected ? () => _showSelectionDialog(context, address, paramId, options) : null,
            child: Container(
              decoration: BoxDecoration(
                color: widget.control.backgroundColor,
                border: Border.all(color: _globalState.isConnected ? Colors.blueAccent : Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      labelText,
                      style: TextStyle(
                        color: widget.control.foregroundColor,
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 14),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('Error in SelectorRenderer build: $e');
      return Container(
        color: Colors.red[100],
        child: const Center(
          child: Text('Selector Error', style: TextStyle(color: Colors.red, fontSize: 8)),
        ),
      );
    }
  }
  
  // Show selection dialog
  void _showSelectionDialog(BuildContext context, String address, String paramId, List<dynamic> options) {
    final numOptions = options.isEmpty ? 8 : options.length;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select ${widget.control.name}'),
        content: SizedBox(
          width: double.minPositive,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: numOptions,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(
                  options.isNotEmpty && index < options.length
                      ? options[index]['label'] ?? 'Option ${index + 1}'
                      : 'Option ${index + 1}'
                ),
                onTap: () {
                  setState(() {
                    _currentValue = index;
                  });
                  
                  // Send to device
                  _controlService.setSourceValue(address, paramId, index);
                  
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