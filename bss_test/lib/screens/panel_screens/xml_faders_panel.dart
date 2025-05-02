import 'package:flutter/material.dart';
import '../../models/panel_model.dart';
import '../../models/control_types.dart';
import '../../services/global_state.dart';
import '../../services/fader_communication.dart';
import '../../services/control_communication_service.dart';
import '../../services/connection_service.dart';
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

class _XmlFadersPanelState extends State<XmlFadersPanel> with SingleTickerProviderStateMixin {
  // Controls lists
  late List<dynamic> _faders;
  late List<dynamic> _sourceSelectors;
  final _controlService = ControlCommunicationService();
  final _connectionService = ConnectionService();
  final _globalState = GlobalState();
  
  // Connection status
  bool _isConnected = false;
  
  // Screen dimensions
  late double _screenWidth;
  late double _screenHeight;
  
  // Layout properties
  late double _controlWidth;
  late double _controlHeight;
  late double _controlSpacing;
  late int _controlsPerRow;
  
  // Tab controller for switching between faders and selectors
  late TabController _tabController;
  
  // Track subscriptions
  StreamSubscription? _connectionSubscription;
  
  @override
  void initState() {
    super.initState();
    // Initialize tab controller
    _tabController = TabController(length: 2, vsync: this);
    
    // Get current connection state
    _isConnected = _connectionService.isConnected;
    debugPrint('XmlFadersPanel: Initial connection state: $_isConnected');
    
    // Subscribe to connection state changes
    _connectionSubscription = _connectionService.onConnectionStatusChanged.listen((connected) {
      setState(() {
        _isConnected = connected;
        debugPrint('XmlFadersPanel: Connection state changed to: $_isConnected');
      });
    });
    
    // Extract controls from the panel
    _faders = widget.panel.findControlsByType(ControlType.fader);
    _sourceSelectors = widget.panel.findControlsByType(ControlType.selector);
    
    // Print debug info for controls
    debugPrint('Found ${_faders.length} faders and ${_sourceSelectors.length} source selectors');
    
    // Print out details for controls with multiple addresses
    for (var fader in _faders) {
      final addressPairs = fader.getAddressParameterPairs();
      if (addressPairs.length > 1) {
        debugPrint('Multi-address Fader: ${fader.name} has ${addressPairs.length} address/parameter pairs:');
        for (var pair in addressPairs) {
          debugPrint('  • ${pair['address']}:${pair['paramId']}');
        }
      }
    }
    
    for (var selector in _sourceSelectors) {
      final addressPairs = selector.getAddressParameterPairs();
      if (addressPairs.length > 1) {
        debugPrint('Multi-address Selector: ${selector.name} has ${addressPairs.length} address/parameter pairs:');
        for (var pair in addressPairs) {
          debugPrint('  • ${pair['address']}:${pair['paramId']}');
        }
      }
    }
  }
  
  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }
  
  // Helper to normalize address case
  String? _normalizeAddressCase(String? address) {
    if (address == null) return null;
    
    if (address.startsWith('0x') || address.startsWith('0X')) {
      final hexPart = address.substring(2).toUpperCase();
      return '0x$hexPart';
    }
    return address;
  }
  
  // Helper to normalize parameter ID case
  String? _normalizeParamIdCase(String? paramId) {
    if (paramId == null) return null;
    
    if (paramId.startsWith('0x') || paramId.startsWith('0X')) {
      final hexPart = paramId.substring(2).toUpperCase();
      return '0x$hexPart';
    }
    return paramId;
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
    _controlsPerRow = 2;
    _controlSpacing = 16;
    _controlWidth = (_screenWidth - (_controlsPerRow + 1) * _controlSpacing) / _controlsPerRow;
    _controlHeight = _screenHeight / 3;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('XML Panel: ${widget.panel.name}'),
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
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAllControls,
            tooltip: 'Refresh all controls',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Faders'),
            Tab(text: 'Source Selectors'),
          ],
        ),
      ),
      body: Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        child: TabBarView(
          controller: _tabController,
          children: [
            // Faders Tab
            _faders.isEmpty 
              ? const Center(child: Text('No faders found', style: TextStyle(color: Colors.white)))
              : Padding(
                  padding: EdgeInsets.all(_controlSpacing),
                  child: _buildFadersGrid(),
                ),
            
            // Source Selectors Tab
            _sourceSelectors.isEmpty 
              ? const Center(child: Text('No source selectors found', style: TextStyle(color: Colors.white)))
              : Padding(
                  padding: EdgeInsets.all(_controlSpacing),
                  child: _buildSourceSelectorsGrid(),
                ),
          ],
        ),
      ),
      bottomSheet: Container(
        height: 40,
        color: Colors.black,
        child: Center(
          child: Text(
            'Faders: ${_faders.length}, Sources: ${_sourceSelectors.length} - Connection: ${_isConnected ? "Connected" : "Disconnected"}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ),
    );
  }
  
  // Force refresh all controls
  void _refreshAllControls() {
    debugPrint('Refreshing all controls');
    
    // We need to re-subscribe to all control addresses
    for (var fader in _faders) {
      final addressPairs = fader.getAddressParameterPairs();
      for (var pair in addressPairs) {
        final address = pair['address'];
        final paramId = pair['paramId'];
        if (address != null && paramId != null) {
          _controlService.subscribeFaderValue(address, paramId);
          debugPrint('Re-subscribed to fader: $address:$paramId');
        }
      }
    }
    
    for (var selector in _sourceSelectors) {
      final addressPairs = selector.getAddressParameterPairs();
      for (var pair in addressPairs) {
        final address = pair['address'];
        final paramId = pair['paramId'];
        if (address != null && paramId != null) {
          _controlService.subscribeSourceValue(address, paramId);
          debugPrint('Re-subscribed to selector: $address:$paramId');
        }
      }
    }
    
    // Trigger a rebuild
    setState(() {});
  }
  
  // Build faders grid
  Widget _buildFadersGrid() {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _controlsPerRow,
        crossAxisSpacing: _controlSpacing,
        mainAxisSpacing: _controlSpacing,
        childAspectRatio: _controlWidth / _controlHeight,
      ),
      itemCount: _faders.length,
      itemBuilder: (context, index) {
        final fader = _faders[index];
        return XmlFaderControl(
          control: fader,
          normalizeAddressCase: _normalizeAddressCase,
          normalizeParamIdCase: _normalizeParamIdCase,
          isConnected: _isConnected,
        );
      },
    );
  }
  
  // Build source selectors grid
  Widget _buildSourceSelectorsGrid() {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _controlsPerRow,
        crossAxisSpacing: _controlSpacing,
        mainAxisSpacing: _controlSpacing,
        childAspectRatio: _controlWidth / (_controlHeight * 0.7), // Make selectors less tall
      ),
      itemCount: _sourceSelectors.length,
      itemBuilder: (context, index) {
        final selector = _sourceSelectors[index];
        return XmlSourceControl(
          control: selector,
          normalizeAddressCase: _normalizeAddressCase,
          normalizeParamIdCase: _normalizeParamIdCase,
          isConnected: _isConnected,
        );
      },
    );
  }
}

class XmlFaderControl extends StatefulWidget {
  final dynamic control;
  final String? Function(String?) normalizeAddressCase;
  final String? Function(String?) normalizeParamIdCase;
  final bool isConnected;
  
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
  DateTime _lastUpdateTime = DateTime.now();
  
  // Lists for multiple addresses
  List<Map<String, String>> _addressParamPairs = [];
  
  // Track subscriptions
  List<StreamSubscription> _subscriptions = [];
  
  // UI update info
  bool _isUpdatingFromDevice = false;
  String _lastUpdateSource = "";
  
  @override
  void initState() {
    super.initState();
    
    // Get all addresses and parameter IDs
    _initializeAddresses();
    
    // Debug logging
    debugPrint('XmlFaderControl: Initializing ${widget.control.name}');
    debugPrint('  Found ${_addressParamPairs.length} address/parameter pairs');
    
    for (var pair in _addressParamPairs) {
      debugPrint('  Address: ${pair['address']}, ParamId: ${pair['paramId']}');
    }
    
    // Subscribe to fader updates for all addresses
    _subscribeToUpdates();
  }
  
  void _initializeAddresses() {
    try {
      // Get state variables from the control
      final stateVars = widget.control.stateVariables;
      
      if (stateVars.isEmpty) {
        debugPrint('XmlFaderControl: No state variables for ${widget.control.name}');
        return;
      }
      
      // Process each state variable
      _addressParamPairs = [];
      
      for (var sv in stateVars) {
        final rawAddress = sv.hiQnetAddress;
        final rawParamId = sv.parameterID;
        
        // Normalize address format
        final normalizedAddress = widget.normalizeAddressCase(rawAddress);
        final normalizedParamId = widget.normalizeParamIdCase(rawParamId);
        
        if (normalizedAddress != null && normalizedParamId != null) {
          _addressParamPairs.add({
            'address': normalizedAddress,
            'paramId': normalizedParamId,
          });
        }
      }
    } catch (e) {
      debugPrint('Error initializing addresses: $e');
    }
  }
  
  void _subscribeToUpdates() {
    // Clear previous subscriptions
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    
    // Listen for fader updates from FaderComm
    var faderSub = _faderComm.onFaderUpdate.listen((data) {
      final dataAddress = widget.normalizeAddressCase(data['address'].toString());
      final dataParamId = widget.normalizeParamIdCase(data['paramId'].toString());
      
      // Log what we received for debugging
      debugPrint('XmlFaderControl ${widget.control.name}: Received update, checking if matches:');
      debugPrint('  Received: $dataAddress:$dataParamId, value: ${data['value']}');
      
      // Check if this update is for any of our address/paramId pairs with more flexible matching
      bool matched = false;
      for (var pair in _addressParamPairs) {
        final pairAddress = pair['address']?.toLowerCase();
        final pairParamId = pair['paramId']?.toLowerCase();
        final dataAddressLower = dataAddress?.toLowerCase();
        final dataParamIdLower = dataParamId?.toLowerCase();
        
        // Try various matching strategies
        bool addressMatches = pairAddress == dataAddressLower;
        
        // For paramId, try both hex and decimal representations
        bool paramIdMatches = pairParamId == dataParamIdLower;
        
        // Try to convert between formats (decimal/hex) if direct match fails
        if (!paramIdMatches && pairParamId != null && dataParamId != null) {
          try {
            // Try parsing as hex and comparing decimal values
            final pairDecimal = int.parse(pairParamId.replaceAll('0x', ''), radix: 16);
            final dataDecimal = int.parse(dataParamId.replaceAll('0x', ''), radix: 16);
            paramIdMatches = pairDecimal == dataDecimal;
            
            if (!paramIdMatches) {
              // Another format: compare the last two characters of hex representation
              final pairShort = pairParamId.replaceAll('0x', '').padLeft(2, '0').substring(0, 2).toLowerCase();
              final dataShort = dataParamId.replaceAll('0x', '').padLeft(2, '0').substring(0, 2).toLowerCase();
              paramIdMatches = pairShort == dataShort;
            }
          } catch (e) {
            debugPrint('Error comparing paramIds: $e');
          }
        }
        
        if (addressMatches && paramIdMatches && !_isDragging) {
          debugPrint('  ✓ MATCHED with ${pair['address']}:${pair['paramId']}');
          matched = true;
          
          final now = DateTime.now();
          
          // Update UI with visual feedback
          setState(() {
            _faderValue = data['value'];
            _isUpdatingFromDevice = true;
            _lastUpdateSource = "FaderComm";
            _lastUpdateTime = now;
          });
          
          // Clear update indicator after a short delay
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _isUpdatingFromDevice = false;
              });
            }
          });
          
          break;
        } else {
          debugPrint('  ✗ NO MATCH with ${pair['address']}:${pair['paramId']}');
          debugPrint('    Address match: $addressMatches, ParamId match: $paramIdMatches');
        }
      }
      
      if (!matched) {
        debugPrint('  ✗ NO MATCH FOUND for any address/paramId pair');
      }
    });
    _subscriptions.add(faderSub);
    
    // Also listen directly to the control service updates with similar flexible matching
    var controlSub = _controlService.onFaderUpdate.listen((data) {
      final dataAddress = widget.normalizeAddressCase(data['address'].toString());
      final dataParamId = widget.normalizeParamIdCase(data['paramId'].toString());
      
      // Log what we received for debugging
      debugPrint('XmlFaderControl ${widget.control.name}: Received ControlService update:');
      debugPrint('  Received: $dataAddress:$dataParamId, value: ${data['value']}');
      
      // Check with flexible matching
      bool matched = false;
      for (var pair in _addressParamPairs) {
        final pairAddress = pair['address']?.toLowerCase();
        final pairParamId = pair['paramId']?.toLowerCase();
        final dataAddressLower = dataAddress?.toLowerCase();
        final dataParamIdLower = dataParamId?.toLowerCase();
        
        // Try various matching strategies
        bool addressMatches = pairAddress == dataAddressLower;
        
        // For paramId, try both hex and decimal representations
        bool paramIdMatches = pairParamId == dataParamIdLower;
        
        // Try to convert between formats (decimal/hex) if direct match fails
        if (!paramIdMatches && pairParamId != null && dataParamId != null) {
          try {
            // Try parsing as hex and comparing decimal values
            final pairDecimal = int.parse(pairParamId.replaceAll('0x', ''), radix: 16);
            final dataDecimal = int.parse(dataParamId.replaceAll('0x', ''), radix: 16);
            paramIdMatches = pairDecimal == dataDecimal;
            
            if (!paramIdMatches) {
              // Another format: compare the last two characters of hex representation
              final pairShort = pairParamId.replaceAll('0x', '').padLeft(2, '0').substring(0, 2).toLowerCase();
              final dataShort = dataParamId.replaceAll('0x', '').padLeft(2, '0').substring(0, 2).toLowerCase();
              paramIdMatches = pairShort == dataShort;
            }
          } catch (e) {
            debugPrint('Error comparing paramIds: $e');
          }
        }
        
        if (addressMatches && paramIdMatches && !_isDragging) {
          debugPrint('  ✓ MATCHED with ${pair['address']}:${pair['paramId']}');
          matched = true;
          
          final now = DateTime.now();
          
          // Update UI with visual feedback
          setState(() {
            _faderValue = data['value'];
            _isUpdatingFromDevice = true;
            _lastUpdateSource = "ControlService";
            _lastUpdateTime = now;
          });
          
          // Clear update indicator after a short delay
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _isUpdatingFromDevice = false;
              });
            }
          });
          
          break;
        }
      }
      
      if (!matched) {
        debugPrint('  ✗ NO MATCH FOUND for any address/paramId pair');
      }
    });
    _subscriptions.add(controlSub);
    
    // Subscribe to ensure we get initial values for all addresses
    if (widget.isConnected) {
      for (var pair in _addressParamPairs) {
        _controlService.subscribeFaderValue(pair['address']!, pair['paramId']!);
        debugPrint('XmlFaderControl: Subscribed to ${pair['address']}:${pair['paramId']}');
      }
    }
  }
  
  @override
  void didUpdateWidget(XmlFaderControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Reinitialize if control changed
    if (widget.control != oldWidget.control) {
      _initializeAddresses();
      _subscribeToUpdates();
    }
    
    // Subscribe if we just got connected
    if (!oldWidget.isConnected && widget.isConnected) {
      for (var pair in _addressParamPairs) {
        _controlService.subscribeFaderValue(pair['address']!, pair['paramId']!);
        debugPrint('XmlFaderControl: Subscribed to ${pair['address']}:${pair['paramId']}');
      }
    }
  }
  
  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_addressParamPairs.isEmpty) {
      return Container(
        color: Colors.red[900],
        child: const Center(
          child: Text('Invalid Fader - No Addresses', style: TextStyle(color: Colors.white)),
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
          color: _isUpdatingFromDevice 
              ? Colors.orange
              : (widget.isConnected ? Colors.blue : Colors.grey),
          width: _isUpdatingFromDevice ? 3 : 2,
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
            style: TextStyle(
              color: _isUpdatingFromDevice ? Colors.orange : Colors.white,
              fontSize: 12,
              fontWeight: _isUpdatingFromDevice ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          
          // Connection and address count
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isConnected ? Icons.check_circle : Icons.error_outline,
                color: widget.isConnected ? Colors.green : Colors.red,
                size: 10,
              ),
              const SizedBox(width: 4),
              Text(
                widget.isConnected ? 'Connected' : 'Disconnected',
                style: TextStyle(
                  color: widget.isConnected ? Colors.green : Colors.red,
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.link,
                color: Colors.blue,
                size: 10,
              ),
              const SizedBox(width: 2),
              Text(
                '${_addressParamPairs.length}',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          
          // Vertical fader
          Expanded(
            child: RotatedBox(
              quarterTurns: 3, // Make vertical
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 20.0,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 15.0),
                  activeTrackColor: _isUpdatingFromDevice 
                      ? Colors.orange 
                      : (widget.isConnected ? Colors.white : Colors.grey),
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
                      _sendFaderValueToAllAddresses(newValue);
                    } else {
                      debugPrint('XmlFaderControl: Not sending value - disconnected');
                    }
                  },
                ),
              ),
            ),
          ),
          
          // Show a chip or indicator for number of addresses
          _addressParamPairs.length > 1 
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_addressParamPairs.length} destinations',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              )
            : Text(
                '${_addressParamPairs[0]['address']}:${_addressParamPairs[0]['paramId']}',
                style: TextStyle(color: Colors.grey[600], fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
        ],
      ),
    );
  }
  
  // Send fader value to all linked addresses
  void _sendFaderValueToAllAddresses(double value) {
    try {
      if (!widget.isConnected || _addressParamPairs.isEmpty) return;
      
      debugPrint('XmlFaderControl: Sending fader value ${value.toStringAsFixed(3)} to ${_addressParamPairs.length} destinations');
      
      // Send to each address/paramId pair
      for (var pair in _addressParamPairs) {
        debugPrint('  Sending to ${pair['address']}:${pair['paramId']}');
        
        // Use control service
        _controlService.setFaderValue(pair['address']!, pair['paramId']!, value);
        
        // Also report via FaderComm
        _faderComm.reportFaderMoved(pair['address']!, pair['paramId']!, value);
      }
    } catch (e) {
      debugPrint('Error sending fader value: $e');
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

class XmlSourceControl extends StatefulWidget {
  final dynamic control;
  final String? Function(String?) normalizeAddressCase;
  final String? Function(String?) normalizeParamIdCase;
  final bool isConnected;
  
  const XmlSourceControl({
    super.key,
    required this.control,
    required this.normalizeAddressCase,
    required this.normalizeParamIdCase,
    required this.isConnected,
  });

  @override
  State<XmlSourceControl> createState() => _XmlSourceControlState();
}

class _XmlSourceControlState extends State<XmlSourceControl> {
  final _controlService = ControlCommunicationService();
  
  // Control values
  int _sourceValue = 0;
  List<Map<String, String>> _addressParamPairs = [];
  List<Map<String, String>> _sourceOptions = [];
  DateTime _lastUpdateTime = DateTime.now();
  
  // Track subscriptions
  List<StreamSubscription> _subscriptions = [];
  
  // UI update info
  bool _isUpdatingFromDevice = false;
  String _lastUpdateSource = "";
  
  @override
  void initState() {
    super.initState();
    
    // Get all addresses and parameter IDs
    _initializeAddresses();
    
    // Get source options from control properties
    _sourceOptions = _getSourceOptions();
    
    // Debug logging
    debugPrint('XmlSourceControl: Initializing ${widget.control.name}');
    debugPrint('  Found ${_addressParamPairs.length} address/parameter pairs');
    debugPrint('  Source Options: ${_sourceOptions.length}');
    
    // Subscribe to source updates for all addresses
    _subscribeToUpdates();
  }
  
  void _initializeAddresses() {
    try {
      // Get state variables from the control
      final stateVars = widget.control.stateVariables;
      
      if (stateVars.isEmpty) {
        debugPrint('XmlSourceControl: No state variables for ${widget.control.name}');
        return;
      }
      
      // Process each state variable
      _addressParamPairs = [];
      
      for (var sv in stateVars) {
        final rawAddress = sv.hiQnetAddress;
        final rawParamId = sv.parameterID;
        
        // Normalize address format
        final normalizedAddress = widget.normalizeAddressCase(rawAddress);
        final normalizedParamId = widget.normalizeParamIdCase(rawParamId);
        
        if (normalizedAddress != null && normalizedParamId != null) {
          _addressParamPairs.add({
            'address': normalizedAddress,
            'paramId': normalizedParamId,
          });
        }
      }
    } catch (e) {
      debugPrint('Error initializing addresses: $e');
    }
  }
  
  void _subscribeToUpdates() {
    // Clear previous subscriptions
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    
    // Subscribe to source updates directly
    var sourceSub = _controlService.onSourceUpdate.listen((data) {
      final dataAddress = widget.normalizeAddressCase(data['address'].toString());
      final dataParamId = widget.normalizeParamIdCase(data['paramId'].toString());
      
      // Log what we received for debugging
      debugPrint('XmlSourceControl ${widget.control.name}: Received update, checking if matches:');
      debugPrint('  Received: $dataAddress:$dataParamId, value: ${data['value']}');
      
      // Check if this update is for any of our address/paramId pairs with more flexible matching
      bool matched = false;
      for (var pair in _addressParamPairs) {
        final pairAddress = pair['address']?.toLowerCase();
        final pairParamId = pair['paramId']?.toLowerCase();
        final dataAddressLower = dataAddress?.toLowerCase();
        final dataParamIdLower = dataParamId?.toLowerCase();
        
        // Try various matching strategies
        bool addressMatches = pairAddress == dataAddressLower;
        
        // For paramId, try both hex and decimal representations
        bool paramIdMatches = pairParamId == dataParamIdLower;
        
        // Try to convert between formats (decimal/hex) if direct match fails
        if (!paramIdMatches && pairParamId != null && dataParamId != null) {
          try {
            // Try parsing as hex and comparing decimal values
            final pairDecimal = int.parse(pairParamId.replaceAll('0x', ''), radix: 16);
            final dataDecimal = int.parse(dataParamId.replaceAll('0x', ''), radix: 16);
            paramIdMatches = pairDecimal == dataDecimal;
            
            if (!paramIdMatches) {
              // Another format: compare the last two characters of hex representation
              final pairShort = pairParamId.replaceAll('0x', '').padLeft(2, '0').substring(0, 2).toLowerCase();
              final dataShort = dataParamId.replaceAll('0x', '').padLeft(2, '0').substring(0, 2).toLowerCase();
              paramIdMatches = pairShort == dataShort;
            }
          } catch (e) {
            debugPrint('Error comparing paramIds: $e');
          }
        }
        
        if (addressMatches && paramIdMatches) {
          debugPrint('  ✓ MATCHED with ${pair['address']}:${pair['paramId']}');
          matched = true;
          
          final now = DateTime.now();
          
          // Update UI with visual feedback
          setState(() {
            _sourceValue = data['value'] as int;
            _isUpdatingFromDevice = true;
            _lastUpdateSource = "ControlService";
            _lastUpdateTime = now;
            debugPrint('XmlSourceControl ${widget.control.name}: Updated source value: $_sourceValue from ${pair['address']}:${pair['paramId']}');
          });
          
          // Clear update indicator after a short delay
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _isUpdatingFromDevice = false;
              });
            }
          });
          
          break;
        } else {
          debugPrint('  ✗ NO MATCH with ${pair['address']}:${pair['paramId']}');
          debugPrint('    Address match: $addressMatches, ParamId match: $paramIdMatches');
        }
      }
      
      if (!matched) {
        debugPrint('  ✗ NO MATCH FOUND for any address/paramId pair');
      }
    });
    _subscriptions.add(sourceSub);
    
    // Subscribe to ensure we get initial values for all addresses
    if (widget.isConnected) {
      for (var pair in _addressParamPairs) {
        _controlService.subscribeSourceValue(pair['address']!, pair['paramId']!);
        debugPrint('XmlSourceControl: Subscribed to ${pair['address']}:${pair['paramId']}');
      }
    }
  }
  
  @override
  void didUpdateWidget(XmlSourceControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Reinitialize if control changed
    if (widget.control != oldWidget.control) {
      _initializeAddresses();
      _sourceOptions = _getSourceOptions();
      _subscribeToUpdates();
    }
    
    // Subscribe if we just got connected
    if (!oldWidget.isConnected && widget.isConnected) {
      for (var pair in _addressParamPairs) {
        _controlService.subscribeSourceValue(pair['address']!, pair['paramId']!);
        debugPrint('XmlSourceControl: Subscribed to ${pair['address']}:${pair['paramId']}');
      }
    }
  }
  
  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }
  
  // Extract source options from control properties
  List<Map<String, String>> _getSourceOptions() {
    try {
      // Try to get options from control properties
      final options = widget.control.properties['options'] as List<dynamic>? ?? [];
      
      // Convert to a more usable format
      return options.map<Map<String, String>>((option) {
        return {
          'value': option['value'] as String? ?? '',
          'label': option['label'] as String? ?? 'Option ${options.indexOf(option) + 1}',
        };
      }).toList();
    } catch (e) {
      debugPrint('Error getting source options: $e');
      return [];
    }
  }
  
  // Get current option label
  String _getCurrentOptionLabel() {
    // Safety check on index
    if (_sourceOptions.isEmpty) {
      return 'Input ${_sourceValue + 1}';
    }
    
    if (_sourceValue >= 0 && _sourceValue < _sourceOptions.length) {
      return _sourceOptions[_sourceValue]['label'] ?? 'Input ${_sourceValue + 1}';
    }
    
    return 'Input ${_sourceValue + 1}';
  }

  @override
  Widget build(BuildContext context) {
    if (_addressParamPairs.isEmpty) {
      return Container(
        color: Colors.red[900],
        child: const Center(
          child: Text('Invalid Source Selector - No Addresses', style: TextStyle(color: Colors.white)),
        ),
      );
    }
    
    // Determine number of source options for the grid
    final numOptions = _sourceOptions.isEmpty ? 8 : _sourceOptions.length;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isUpdatingFromDevice 
              ? Colors.orange
              : (widget.isConnected ? Colors.blue : Colors.grey),
          width: _isUpdatingFromDevice ? 3 : 2,
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Source selector name
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
          
          // Current selection display
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: _isUpdatingFromDevice ? Colors.orange.withOpacity(0.3) : Colors.black38,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Text(
                  'Current: ',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Expanded(
                  child: Text(
                    _getCurrentOptionLabel(),
                    style: TextStyle(
                      color: _isUpdatingFromDevice ? Colors.orange : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          
          // Connection and address count
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isConnected ? Icons.check_circle : Icons.error_outline,
                color: widget.isConnected ? Colors.green : Colors.red,
                size: 10,
              ),
              const SizedBox(width: 4),
              Text(
                widget.isConnected ? 'Connected' : 'Disconnected',
                style: TextStyle(
                  color: widget.isConnected ? Colors.green : Colors.red,
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.link,
                color: Colors.blue,
                size: 10,
              ),
              const SizedBox(width: 2),
              Text(
                '${_addressParamPairs.length}',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Grid of source selection buttons
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
                childAspectRatio: 1.5,
              ),
              itemCount: numOptions > 12 ? 12 : numOptions, // Limit to 12 options
              itemBuilder: (context, index) {
                final isSelected = _sourceValue == index;
                final label = _sourceOptions.isNotEmpty && index < _sourceOptions.length 
                    ? _sourceOptions[index]['label'] 
                    : (index + 1).toString();
                    
                return ElevatedButton(
                  onPressed: widget.isConnected ? () => _selectSource(index) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected 
                        ? (_isUpdatingFromDevice ? Colors.orange : Colors.blue) 
                        : Colors.grey[800],
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: Text(
                    label ?? (index + 1).toString(),
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
          
          // Show more options button if there are more than 12
          if (numOptions > 12)
            TextButton(
              onPressed: widget.isConnected ? _showAllOptions : null,
              child: const Text('More Options...', style: TextStyle(fontSize: 10)),
            ),
          
          // Show a chip or indicator for number of addresses
          _addressParamPairs.length > 1 
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_addressParamPairs.length} destinations',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              )
            : Text(
                '${_addressParamPairs[0]['address']}:${_addressParamPairs[0]['paramId']}',
                style: TextStyle(color: Colors.grey[600], fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
        ],
      ),
    );
  }
  
  // Select a source and send to all addresses
  void _selectSource(int index) {
    if (!widget.isConnected || _addressParamPairs.isEmpty) return;
    
    debugPrint('XmlSourceControl: Selecting source $index for ${widget.control.name} and sending to ${_addressParamPairs.length} destinations');
    
    setState(() {
      _sourceValue = index;
    });
    
    // Send to all address/paramId pairs
    for (var pair in _addressParamPairs) {
      debugPrint('  Sending to ${pair['address']}:${pair['paramId']}');
      _controlService.setSourceValue(pair['address']!, pair['paramId']!, index);
    }
  }
  
  // Show dialog with all options
  void _showAllOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select ${widget.control.name}'),
        content: SizedBox(
          width: double.minPositive,
          height: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _sourceOptions.isEmpty ? 8 : _sourceOptions.length,
            itemBuilder: (context, index) {
              final label = _sourceOptions.isNotEmpty && index < _sourceOptions.length 
                  ? _sourceOptions[index]['label'] 
                  : 'Input ${index + 1}';
                  
              return ListTile(
                title: Text(label ?? 'Input ${index + 1}'),
                selected: _sourceValue == index,
                onTap: () {
                  _selectSource(index);
                  Navigator.of(context).pop();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}