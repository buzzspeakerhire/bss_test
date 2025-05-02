import 'package:flutter/material.dart';
import '../../models/panel_model.dart';
import '../../models/control_types.dart';
import '../../services/global_state.dart';
import '../../services/fader_communication.dart';
import '../../services/control_communication_service.dart';
import '../../services/connection_service.dart'; // Add this import
import 'dart:async';

class XmlFadersPanel extends StatefulWidget {
  final PanelModel panel;
  
  const XmlFadersPanel({
    super.key,
    required this.panel,
  });

  @override
  State<XmlFadersPanel> createState() => _XmlFadersPanelState();
}

class _XmlFadersPanelState extends State<XmlFadersPanel> {
  // Faders list
  late List<dynamic> _faders;
  final _controlService = ControlCommunicationService();
  final _connectionService = ConnectionService(); // Direct connection service
  final _globalState = GlobalState();
  
  // Connection status
  bool _isConnected = false;
  
  // Screen dimensions
  late double _screenWidth;
  late double _screenHeight;
  
  // Layout properties
  late double _faderWidth;
  late double _faderHeight;
  late double _faderSpacing;
  late int _fadersPerRow;
  
  // Track subscriptions
  StreamSubscription? _connectionSubscription;
  
  @override
  void initState() {
    super.initState();
    // Get current connection state directly from the service
    _isConnected = _connectionService.isConnected;
    debugPrint('XmlFadersPanel: Initial connection state: $_isConnected');
    
    // Subscribe to connection state changes
    _connectionSubscription = _connectionService.onConnectionStatusChanged.listen((connected) {
      setState(() {
        _isConnected = connected;
        debugPrint('XmlFadersPanel: Connection state changed to: $_isConnected');
      });
    });
    
    // Extract only faders from the panel
    _faders = widget.panel.findControlsByType(ControlType.fader);
    
    // Print debug info for each fader
    for (var fader in _faders) {
      final rawAddress = fader.getPrimaryAddress();
      final rawParamId = fader.getPrimaryParameterId();
      
      // Normalize address format: lowercase "0x" prefix, uppercase hex values
      final normalizedAddress = _normalizeAddressCase(rawAddress);
      final normalizedParamId = _normalizeParamIdCase(rawParamId);
      
      debugPrint('Fader: ${fader.name}');
      debugPrint('  Position: ${fader.position.dx}, ${fader.position.dy}');
      debugPrint('  Size: ${fader.size.width} x ${fader.size.height}');
      debugPrint('  Raw Address: $rawAddress -> Normalized: $normalizedAddress');
      debugPrint('  Raw ParamId: $rawParamId -> Normalized: $normalizedParamId');
      
      // Subscribe to the fader to ensure we get updates
      if (normalizedAddress != null && normalizedParamId != null) {
        _controlService.subscribeFaderValue(normalizedAddress, normalizedParamId);
        debugPrint('  Subscribed to fader: $normalizedAddress, $normalizedParamId');
      }
    }
  }
  
  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }
  
  // Helper to normalize address case: lowercase "0x" prefix, uppercase hex values
  String? _normalizeAddressCase(String? address) {
    if (address == null) return null;
    
    if (address.startsWith('0x') || address.startsWith('0X')) {
      // Get the prefix and the hex part
      final hexPart = address.substring(2).toUpperCase();
      return '0x$hexPart'; // Use lowercase "0x" prefix
    }
    return address; // Return unchanged if doesn't match pattern
  }
  
  // Helper to normalize parameter ID case: lowercase "0x" prefix, uppercase hex values
  String? _normalizeParamIdCase(String? paramId) {
    if (paramId == null) return null;
    
    if (paramId.startsWith('0x') || paramId.startsWith('0X')) {
      // Get the prefix and the hex part
      final hexPart = paramId.substring(2).toUpperCase();
      return '0x$hexPart'; // Use lowercase "0x" prefix
    }
    return paramId; // Return unchanged if doesn't match pattern
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions
    _screenWidth = MediaQuery.of(context).size.width;
    _screenHeight = MediaQuery.of(context).size.height - 
                   AppBar().preferredSize.height - 
                   MediaQuery.of(context).padding.top - 
                   MediaQuery.of(context).padding.bottom - 
                   40; // Extra spacing for bottom info
    
    // Calculate layout properties
    _fadersPerRow = 2; // Start with 2 faders per row
    _faderSpacing = 16;
    _faderWidth = (_screenWidth - (_fadersPerRow + 1) * _faderSpacing) / _fadersPerRow;
    _faderHeight = _screenHeight / 3;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('XML Faders: ${widget.panel.name}'),
        actions: [
          // Connection status indicator
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _isConnected ? 'Connected' : 'Disconnected',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          // Add a refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAllFaders,
            tooltip: 'Refresh all faders',
          ),
        ],
      ),
      body: Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        padding: EdgeInsets.all(_faderSpacing),
        child: _faders.isEmpty 
          ? const Center(child: Text('No faders found', style: TextStyle(color: Colors.white)))
          : _buildFadersGrid(),
      ),
      bottomSheet: Container(
        height: 40,
        color: Colors.black,
        child: Center(
          child: Text(
            'Showing ${_faders.length} faders - Connection: ${_isConnected ? "Connected" : "Disconnected"}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ),
    );
  }
  
  // Force refresh all faders
  void _refreshAllFaders() {
    debugPrint('Refreshing all ${_faders.length} faders');
    for (var fader in _faders) {
      final rawAddress = fader.getPrimaryAddress();
      final rawParamId = fader.getPrimaryParameterId();
      
      // Normalize address format
      final normalizedAddress = _normalizeAddressCase(rawAddress);
      final normalizedParamId = _normalizeParamIdCase(rawParamId);
      
      if (normalizedAddress != null && normalizedParamId != null) {
        _controlService.subscribeFaderValue(normalizedAddress, normalizedParamId);
        debugPrint('Refreshed fader: $normalizedAddress, $normalizedParamId');
      }
    }
  }
  
  // Build a simple grid of faders
  Widget _buildFadersGrid() {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _fadersPerRow,
        crossAxisSpacing: _faderSpacing,
        mainAxisSpacing: _faderSpacing,
        childAspectRatio: _faderWidth / _faderHeight,
      ),
      itemCount: _faders.length,
      itemBuilder: (context, index) {
        final fader = _faders[index];
        return XmlFaderControl(
          control: fader,
          normalizeAddressCase: _normalizeAddressCase,
          normalizeParamIdCase: _normalizeParamIdCase,
          isConnected: _isConnected, // Pass the current connection state
        );
      },
    );
  }
}

class XmlFaderControl extends StatefulWidget {
  final dynamic control;
  final String? Function(String?) normalizeAddressCase;
  final String? Function(String?) normalizeParamIdCase;
  final bool isConnected; // Added connection state
  
  const XmlFaderControl({
    super.key,
    required this.control,
    required this.normalizeAddressCase,
    required this.normalizeParamIdCase,
    required this.isConnected,
  });

  @override
  State<XmlFaderControl> createState() => _XmlFaderControlState();
}

class _XmlFaderControlState extends State<XmlFaderControl> {
  final _faderComm = FaderCommunication();
  final _controlService = ControlCommunicationService();
  final _connectionService = ConnectionService(); // Direct connection service
  
  double _faderValue = 0.5;
  bool _isDragging = false;
  String? _address;
  String? _paramId;
  String? _rawAddress;
  String? _rawParamId;
  
  // Track subscriptions
  StreamSubscription? _faderUpdateSubscription;
  
  @override
  void initState() {
    super.initState();
    
    // Get raw addresses from control
    _rawAddress = widget.control.getPrimaryAddress();
    _rawParamId = widget.control.getPrimaryParameterId();
    
    // Normalize address format
    _address = widget.normalizeAddressCase(_rawAddress);
    _paramId = widget.normalizeParamIdCase(_rawParamId);
    
    if (_address == null || _paramId == null) {
      debugPrint('XmlFaderControl: Missing address or paramId for ${widget.control.name}');
      debugPrint('  Raw address: $_rawAddress, Raw paramId: $_rawParamId');
      return;
    }
    
    // Debug logging to show exactly what addresses we're using
    debugPrint('XmlFaderControl: Initializing ${widget.control.name}');
    debugPrint('  Raw address: $_rawAddress => Normalized: $_address');
    debugPrint('  Raw paramId: $_rawParamId => Normalized: $_paramId');
    debugPrint('  Current connection state: ${widget.isConnected}');
    
    // Subscribe to fader updates - making sure to normalize addresses in comparisons
    _faderUpdateSubscription = _faderComm.onFaderUpdate.listen((data) {
      final dataAddress = widget.normalizeAddressCase(data['address'].toString());
      final dataParamId = widget.normalizeParamIdCase(data['paramId'].toString());
      
      if (dataAddress == _address && dataParamId == _paramId && !_isDragging) {
        setState(() {
          _faderValue = data['value'];
          debugPrint('XmlFaderControl ${widget.control.name}: Updated from FaderComm: ${_faderValue.toStringAsFixed(3)}');
        });
      }
    });
    
    // Subscribe to ensure we get initial values
    if (widget.isConnected) {
      _controlService.subscribeFaderValue(_address!, _paramId!);
    }
  }
  
  @override
  void didUpdateWidget(XmlFaderControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Subscribe if we just got connected
    if (!oldWidget.isConnected && widget.isConnected && _address != null && _paramId != null) {
      debugPrint('XmlFaderControl: Connection state changed to connected, subscribing to $_address:$_paramId');
      _controlService.subscribeFaderValue(_address!, _paramId!);
    }
  }
  
  @override
  void dispose() {
    _faderUpdateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_address == null || _paramId == null) {
      return Container(
        color: Colors.red[900],
        child: const Center(
          child: Text('Invalid Fader', style: TextStyle(color: Colors.white)),
        ),
      );
    }
    
    // Calculate dB value for display
    final dbValue = _getDbValue(_faderValue);
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.isConnected ? Colors.blue : Colors.grey,
          width: 2,
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Fader name
          Text(
            widget.control.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          
          // dB value display
          Text(
            '${dbValue.toStringAsFixed(1)} dB',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
          
          // Connection indicator
          Text(
            widget.isConnected ? 'Connected' : 'Disconnected',
            style: TextStyle(
              color: widget.isConnected ? Colors.green : Colors.red,
              fontSize: 10,
            ),
          ),
          
          // Vertical fader
          Expanded(
            child: RotatedBox(
              quarterTurns: 3, // Make vertical
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 20.0,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 15.0),
                  activeTrackColor: widget.isConnected ? Colors.white : Colors.grey,
                  inactiveTrackColor: Colors.grey[800],
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: _faderValue,
                  onChangeStart: (_) {
                    debugPrint('XmlFaderControl: Starting drag on ${widget.control.name}');
                    _isDragging = true;
                  },
                  onChanged: (newValue) {
                    setState(() {
                      _faderValue = newValue;
                    });
                  },
                  onChangeEnd: (newValue) {
                    debugPrint('XmlFaderControl: Ending drag on ${widget.control.name}');
                    _isDragging = false;
                    if (widget.isConnected) {
                      _sendFaderValue(newValue);
                    } else {
                      debugPrint('XmlFaderControl: Not sending value - disconnected');
                      debugPrint('  Connection state: ${widget.isConnected}');
                      debugPrint('  ConnectionService state: ${_connectionService.isConnected}');
                    }
                  },
                ),
              ),
            ),
          ),
          
          // Debug info - address and paramId
          Text(
            '$_address:$_paramId',
            style: TextStyle(color: Colors.grey[600], fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
  
  // Send fader value to the device - using the exact same approach as the working test faders
  void _sendFaderValue(double value) {
    if (widget.isConnected && _address != null && _paramId != null) {
      debugPrint('SENDING FADER VALUE:');
      debugPrint('  Fader: ${widget.control.name}');
      debugPrint('  Address: $_address');
      debugPrint('  ParamId: $_paramId');
      debugPrint('  Value: ${value.toStringAsFixed(6)}');
      debugPrint('  Connection state: ${widget.isConnected}');
      debugPrint('  ConnectionService state: ${_connectionService.isConnected}');
      
      // First, update through the control service
      _controlService.setFaderValue(_address!, _paramId!, value);
      
      // Then, report directly through FaderCommunication
      _faderComm.reportFaderMoved(_address!, _paramId!, value);
      
      debugPrint('XmlFaderControl: Fader ${widget.control.name} moved - value: ${value.toStringAsFixed(3)}');
    } else {
      debugPrint('XmlFaderControl: Cannot send fader value - not connected or missing address/paramId');
      debugPrint('  Connected: ${widget.isConnected}');
      debugPrint('  Address: $_address');
      debugPrint('  ParamId: $_paramId');
    }
  }
  
  // Convert normalized value to dB for display
  double _getDbValue(double normalizedValue) {
    if (normalizedValue <= 0.0) return -80.0;
    if (normalizedValue >= 1.0) return 10.0;
    
    // Unity gain at 0.7373
    if ((normalizedValue - 0.7373).abs() < 0.001) return 0.0;
    
    // For values below 0.7373 (unity gain)
    if (normalizedValue < 0.7373) {
      // Scale from -80dB to 0dB
      return -80.0 + (normalizedValue / 0.7373) * 80.0;
    } else {
      // Scale from 0dB to +10dB
      return ((normalizedValue - 0.7373) / (1.0 - 0.7373)) * 10.0;
    }
  }
}