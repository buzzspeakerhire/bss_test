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
  
  // Enhanced multi-address tracking
  Map<String, List<Map<String, String>>> _faderAddressMappings = {};
  Map<String, List<Map<String, String>>> _sourceAddressMappings = {};
  
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
    
    // Build mapping of address pairs for debugging and management
    _buildAddressMappings();
    
    // Print debug info for controls
    debugPrint('Found ${_faders.length} faders and ${_sourceSelectors.length} source selectors');
    _logMultiAddressControls();
  }
  
  // Enhanced: Build a mapping of all address pairs by control name for better tracking
  void _buildAddressMappings() {
    _faderAddressMappings.clear();
    _sourceAddressMappings.clear();
    
    // Process faders
    for (var fader in _faders) {
      final addressPairs = fader.getAddressParameterPairs();
      if (addressPairs.isNotEmpty) {
        _faderAddressMappings[fader.name] = List.from(addressPairs);
      }
    }
    
    // Process source selectors
    for (var selector in _sourceSelectors) {
      final addressPairs = selector.getAddressParameterPairs();
      if (addressPairs.isNotEmpty) {
        _sourceAddressMappings[selector.name] = List.from(addressPairs);
      }
    }
  }
  
  // Enhanced logging for multi-address controls
  void _logMultiAddressControls() {
    // Log faders with multiple addresses
    int multiAddressFaderCount = 0;
    
    for (var name in _faderAddressMappings.keys) {
      final addressPairs = _faderAddressMappings[name]!;
      if (addressPairs.length > 1) {
        multiAddressFaderCount++;
        debugPrint('MULTI-ADDRESS FADER: $name has ${addressPairs.length} address/parameter pairs:');
        for (var pair in addressPairs) {
          debugPrint('  • ${pair['address']}:${pair['paramId']}');
        }
      }
    }
    
    // Log source selectors with multiple addresses
    int multiAddressSourceCount = 0;
    
    for (var name in _sourceAddressMappings.keys) {
      final addressPairs = _sourceAddressMappings[name]!;
      if (addressPairs.length > 1) {
        multiAddressSourceCount++;
        debugPrint('MULTI-ADDRESS SOURCE SELECTOR: $name has ${addressPairs.length} address/parameter pairs:');
        for (var pair in addressPairs) {
          debugPrint('  • ${pair['address']}:${pair['paramId']}');
        }
      }
    }
    
    debugPrint('SUMMARY: Found $multiAddressFaderCount multi-address faders and $multiAddressSourceCount multi-address source selectors');
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
      // ENHANCED: Ensure a cleaner standardized format
      final strippedAddress = address.substring(2).replaceAll(" ", "");
      final hexPart = strippedAddress.toUpperCase();
      return '0x$hexPart';
    }
    return address;
  }
  
  // Helper to normalize parameter ID case
  String? _normalizeParamIdCase(String? paramId) {
    if (paramId == null) return null;
    
    if (paramId.startsWith('0x') || paramId.startsWith('0X')) {
      // ENHANCED: Ensure a cleaner standardized format
      final strippedParam = paramId.substring(2).replaceAll(" ", "");
      final hexPart = strippedParam.toUpperCase();
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
          // ENHANCED: Add a debug button to help diagnose multi-address issues
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: _logMultiAddressControls,
            tooltip: 'Debug multi-address controls',
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
  
  // Force refresh all controls - ENHANCED for multi-address support
  void _refreshAllControls() {
    debugPrint('Refreshing all controls');
    
    // We need to re-subscribe to all control addresses
    int totalSubscriptions = 0;
    
    // Refresh faders
    for (var fader in _faders) {
      final addressPairs = fader.getAddressParameterPairs();
      for (var pair in addressPairs) {
        final address = pair['address'];
        final paramId = pair['paramId'];
        if (address != null && paramId != null) {
          _controlService.subscribeFaderValue(address, paramId);
          totalSubscriptions++;
          debugPrint('Re-subscribed to fader ${fader.name}: $address:$paramId');
          
          // Also subscribe to N-gain related parameters
          try {
            // Standard paramId format without 0x prefix for numeric comparisons
            final paramHex = paramId.toLowerCase().replaceAll("0x", "");
            final paramNum = int.tryParse(paramHex, radix: 16);
            
            if (paramNum != null) {
              // If this is a standard gain parameter (0x0)
              if (paramNum == 0) {
                // Also subscribe to N-gain master (0x60)
                _controlService.subscribeFaderValue(address, "0x60");
                totalSubscriptions++;
                debugPrint('Re-subscribed to N-gain master for ${fader.name}: $address:0x60');
              } 
              // If this is N-gain master (0x60)
              else if (paramNum == 0x60) {
                // Also subscribe to standard gain (0x0)
                _controlService.subscribeFaderValue(address, "0x0");
                totalSubscriptions++;
                debugPrint('Re-subscribed to standard gain for ${fader.name}: $address:0x0');
              }
              // If this is a channel gain parameter (0x1-0x10)
              else if (paramNum > 0 && paramNum <= 0x10) {
                // Also subscribe to adjacent channels
                _controlService.subscribeFaderValue(address, "0x0"); // Channel 1
                totalSubscriptions++;
                debugPrint('Re-subscribed to Channel 1 for ${fader.name}: $address:0x0');
                
                // N-gain master
                _controlService.subscribeFaderValue(address, "0x60");
                totalSubscriptions++;
                debugPrint('Re-subscribed to N-gain master for ${fader.name}: $address:0x60');
              }
            }
          } catch (e) {
            debugPrint('Error in extended subscriptions: $e');
          }
        }
      }
    }
    
    // Refresh source selectors
    for (var selector in _sourceSelectors) {
      final addressPairs = selector.getAddressParameterPairs();
      for (var pair in addressPairs) {
        final address = pair['address'];
        final paramId = pair['paramId'];
        if (address != null && paramId != null) {
          _controlService.subscribeSourceValue(address, paramId);
          totalSubscriptions++;
          debugPrint('Re-subscribed to selector ${selector.name}: $address:$paramId');
        }
      }
    }
    
    debugPrint('Refresh completed - sent $totalSubscriptions subscription requests');
    
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
  
  double _faderValue = 0.5;
  bool _isDragging = false;
  DateTime _lastUpdateTime = DateTime.now();
  
  // Lists for multiple addresses
  List<Map<String, String>> _addressParamPairs = [];
  
  // Track subscriptions
  List<StreamSubscription> _subscriptions = [];
  
  // Enhanced data for multi-address debugging
  Map<String, double> _lastValueByAddress = {};
  Map<String, DateTime> _lastUpdateByAddress = {};
  
  // UI update info
  bool _isUpdatingFromDevice = false;
  String _lastUpdateSource = "";
  
  @override
  void initState() {
    super.initState();
    
    // Get all addresses and parameter IDs
    _initializeAddresses();
    
    // Debug logging for multi-address faders
    if (_addressParamPairs.length > 1) {
      debugPrint('MULTI-ADDRESS FADER: ${widget.control.name} has ${_addressParamPairs.length} address/parameter pairs:');
      for (var pair in _addressParamPairs) {
        debugPrint('  • ${pair['address']}:${pair['paramId']}');
      }
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
    
    // IMPROVED: Listen for fader updates with enhanced matching logic
    var faderSub = _faderComm.onFaderUpdate.listen((data) {
      final receivedAddress = widget.normalizeAddressCase(data['address'].toString());
      final receivedParamId = widget.normalizeParamIdCase(data['paramId'].toString());
      final value = data['value'] as double;
      
      // Log received update for debugging
      debugPrint('XmlFaderControl ${widget.control.name}: Received update from FaderComm:');
      debugPrint('  Received: $receivedAddress:$receivedParamId, value: $value');
      
      // Store value by address for tracking
      final addressKey = '$receivedAddress:$receivedParamId';
      _lastValueByAddress[addressKey] = value;
      _lastUpdateByAddress[addressKey] = DateTime.now();
      
      // Check if this update is for any of our address/paramId pairs with enhanced matching
      _tryMatchAndUpdateFader(receivedAddress, receivedParamId, value, "FaderComm");
    });
    _subscriptions.add(faderSub);
    
    // IMPROVED: Also listen directly to the control service updates
    var controlSub = _controlService.onFaderUpdate.listen((data) {
      final receivedAddress = widget.normalizeAddressCase(data['address'].toString());
      final receivedParamId = widget.normalizeParamIdCase(data['paramId'].toString());
      final value = data['value'] as double;
      
      // Log received update for debugging
      debugPrint('XmlFaderControl ${widget.control.name}: Received update from ControlService:');
      debugPrint('  Received: $receivedAddress:$receivedParamId, value: $value');
      
      // Store value by address for tracking
      final addressKey = '$receivedAddress:$receivedParamId';
      _lastValueByAddress[addressKey] = value;
      _lastUpdateByAddress[addressKey] = DateTime.now();
      
      // Check with enhanced matching logic
      _tryMatchAndUpdateFader(receivedAddress, receivedParamId, value, "ControlService");
    });
    _subscriptions.add(controlSub);
    
    // Enhanced subscription for N-gain modules and channels
    if (widget.isConnected) {
      for (var pair in _addressParamPairs) {
        final address = pair['address']!;
        final paramId = pair['paramId']!;
        
        // Primary subscription
        _controlService.subscribeFaderValue(address, paramId);
        debugPrint('XmlFaderControl: Subscribed to $address:$paramId');
        
        // Special handling for gain modules
        try {
          // Standard paramId format without 0x prefix for numeric comparisons
          final paramHex = paramId.toLowerCase().replaceAll("0x", "");
          final paramNum = int.tryParse(paramHex, radix: 16);
          
          if (paramNum != null) {
            // If this is a standard gain parameter (0x0)
            if (paramNum == 0) {
              // Also subscribe to N-gain master (0x60)
              _controlService.subscribeFaderValue(address, "0x60");
              debugPrint('XmlFaderControl: Also subscribed to N-gain master: $address:0x60');
            } 
            // If this is N-gain master (0x60)
            else if (paramNum == 0x60) {
              // Subscribe to first few channel gains
              for (int i = 0; i < 3; i++) {
                final channelParam = "0x${i.toRadixString(16)}";
                _controlService.subscribeFaderValue(address, channelParam);
                debugPrint('XmlFaderControl: Also subscribed to channel $i: $address:$channelParam');
              }
            }
            // If this is a channel gain parameter (0x1-0x10)
            else if (paramNum > 0 && paramNum <= 0x10) {
              // Also subscribe to master gain
              _controlService.subscribeFaderValue(address, "0x60");
              debugPrint('XmlFaderControl: Also subscribed to N-gain master: $address:0x60');
              
              // For channel-specific gains, try subscribing to channel 1 too
              _controlService.subscribeFaderValue(address, "0x0"); // Channel 1
              debugPrint('XmlFaderControl: Also subscribed to Channel 1: $address:0x0');
              
              // And also to adjacent channels
              if (paramNum < 0x10) {
                final nextChannel = "0x${(paramNum + 1).toRadixString(16)}";
                _controlService.subscribeFaderValue(address, nextChannel);
                debugPrint('XmlFaderControl: Also subscribed to next channel: $address:$nextChannel');
              }
            }
          }
        } catch (e) {
          debugPrint('Error in extended subscriptions: $e');
        }
      }
    }
  }
  
  // ENHANCED: New centralized matching logic with more flexible address comparison
  // and specific handling for N-gain modules
  void _tryMatchAndUpdateFader(String? receivedAddress, String? receivedParamId, double value, String source) {
    if (receivedAddress == null || receivedParamId == null || _isDragging) return;
    
    // Convert for consistent comparison
    final receivedAddressLower = receivedAddress.toLowerCase();
    final receivedParamIdLower = receivedParamId.toLowerCase();
    
    // Log received values for debugging
    debugPrint('Trying to match: $receivedAddressLower:$receivedParamIdLower');
    
    // Try to match against any of our addresses
    bool matched = false;
    for (var pair in _addressParamPairs) {
      final pairAddress = pair['address']?.toLowerCase();
      final pairParamId = pair['paramId']?.toLowerCase();
      
      // Enhanced matching strategy
      bool addressMatches = false;
      bool paramIdMatches = false;
      
      // Try direct string comparison first
      addressMatches = pairAddress == receivedAddressLower;
      paramIdMatches = pairParamId == receivedParamIdLower;
      
      // If direct match fails, try numeric comparison for both
      if (!addressMatches || !paramIdMatches) {
        try {
          // For addresses - strip 0x and compare numeric values
          final pairAddressHex = pairAddress?.replaceAll("0x", "") ?? "";
          final receivedAddressHex = receivedAddressLower.replaceAll("0x", "");
          
          // Try to match by numeric value
          if (pairAddressHex.isNotEmpty && receivedAddressHex.isNotEmpty) {
            final pairAddressNum = int.parse(pairAddressHex, radix: 16);
            final receivedAddressNum = int.parse(receivedAddressHex, radix: 16);
            addressMatches = pairAddressNum == receivedAddressNum;
          }
          
          // ENHANCED FOR N-GAIN: Handle both master gain and channel gains
          final pairParamHex = pairParamId?.replaceAll("0x", "") ?? "";
          final receivedParamHex = receivedParamIdLower.replaceAll("0x", "");
          
          if (pairParamHex.isNotEmpty && receivedParamHex.isNotEmpty) {
            final pairParamNum = int.parse(pairParamHex, radix: 16);
            final receivedParamNum = int.parse(receivedParamHex, radix: 16);
            
            // Check for exact match
            paramIdMatches = pairParamNum == receivedParamNum;
            
            // If no exact match, check for N-gain parameter patterns
            if (!paramIdMatches) {
              debugPrint('  Checking N-gain parameter matching for $pairParamNum and $receivedParamNum');
              
              // N-gain master (0x60) might map to standard gain (0x0)
              if ((pairParamNum == 0x0 && receivedParamNum == 0x60) || 
                  (pairParamNum == 0x60 && receivedParamNum == 0x0)) {
                paramIdMatches = true;
                debugPrint('  Special match: N-gain master parameter (0x60) matched with standard gain (0x0)');
              }
              // Channel gains: might need to match N-gain channel params (0x0, 0x1, 0x2...)
              // with other gain controls
              else if ((pairParamNum >= 0x0 && pairParamNum <= 0x10) && 
                       (receivedParamNum >= 0x0 && receivedParamNum <= 0x10)) {
                // This is likely a channel gain parameter - check if they're both in that range
                debugPrint('  Both parameters appear to be channel gains (0x0-0x10 range)');
                
                // For channel gains in N-gain modules (more lenient matching)
                // If the fader widget is supposed to control a specific channel,
                // we might want to match it even if channel numbers differ
                // This assumes the UI is showing the right fader for any channel
                paramIdMatches = true;
                debugPrint('  Special match: Both are in channel gain range - assuming match');
              }
            }
          }
          
          // Last resort - compare just the last digit of paramId
          if (!paramIdMatches && pairParamHex.isNotEmpty && receivedParamHex.isNotEmpty) {
            // For single-digit channel gains (0x0, 0x1, etc.)
            final pairLastDigit = pairParamHex.substring(pairParamHex.length - 1);
            final receivedLastDigit = receivedParamHex.substring(receivedParamHex.length - 1);
            paramIdMatches = pairLastDigit == receivedLastDigit;
            
            if (paramIdMatches) {
              debugPrint('  Last digit match: $pairLastDigit matches $receivedLastDigit');
            }
          }
        } catch (e) {
          debugPrint('Error in enhanced matching: $e');
        }
      }
      
      // Additional debug for channel gain detection
      if (pairParamId != null && receivedParamIdLower != null &&
          int.tryParse(pairParamId.replaceAll("0x", ""), radix: 16) != null &&
          int.tryParse(receivedParamIdLower.replaceAll("0x", ""), radix: 16) != null) {
        final pNum = int.parse(pairParamId.replaceAll("0x", ""), radix: 16);
        final rNum = int.parse(receivedParamIdLower.replaceAll("0x", ""), radix: 16);
        
        if ((pNum >= 0x0 && pNum <= 0x10) || (rNum >= 0x0 && rNum <= 0x10) || 
            pNum == 0x60 || rNum == 0x60) {
          debugPrint('  Gain parameter detected - pairParamId: $pairParamId ($pNum), receivedParamId: $receivedParamIdLower ($rNum)');
        }
      }
      
      // If we have a match, update UI
      if (addressMatches && paramIdMatches) {
        debugPrint('  ✓ MATCHED with ${pair['address']}:${pair['paramId']}');
        matched = true;
        
        final now = DateTime.now();
        
        // Update UI with visual feedback
        setState(() {
          _faderValue = value;
          _isUpdatingFromDevice = true;
          _lastUpdateSource = source;
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
        // Enhanced debug output
        debugPrint('  ✗ NO MATCH with ${pair['address']}:${pair['paramId']}');
        debugPrint('    Address match: $addressMatches, ParamId match: $paramIdMatches');
        
        // Extra debug for hex values
        try {
          final pairAddressHex = pairAddress?.replaceAll("0x", "") ?? "";
          final receivedAddressHex = receivedAddressLower.replaceAll("0x", "");
          final pairParamHex = pairParamId?.replaceAll("0x", "") ?? "";
          final receivedParamHex = receivedParamIdLower.replaceAll("0x", "");
          
          debugPrint('    Hex comparison - Pair: $pairAddressHex:$pairParamHex, Received: $receivedAddressHex:$receivedParamHex');
        } catch (e) {
          // Ignore parsing errors in debug
        }
      }
    }
    
    if (!matched) {
      debugPrint('  ✗ NO MATCH FOUND for any address/paramId pair');
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
          
          // Connection and address count - ENHANCED with better visual indication
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
              // ENHANCED: Multi-address indicator with color
              Icon(
                Icons.link,
                color: _addressParamPairs.length > 1 ? Colors.orange : Colors.blue,
                size: 10,
              ),
              const SizedBox(width: 2),
              Text(
                '${_addressParamPairs.length}',
                style: TextStyle(
                  color: _addressParamPairs.length > 1 ? Colors.orange : Colors.blue,
                  fontWeight: _addressParamPairs.length > 1 ? FontWeight.bold : FontWeight.normal,
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
          
          // ENHANCED: Multi-address indicator for more clarity
          _addressParamPairs.length > 1 
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'Multi-fader linked to ${_addressParamPairs.length} destinations',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    // Compact addresses list
                    Text(
                      _addressParamPairs.map((p) => p['address']?.substring(0, 14)).join(', '),
                      style: TextStyle(color: Colors.grey[400], fontSize: 8),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
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
        
        // ENHANCED: For N-gain modules, also send to both master and channel parameters
        try {
          final paramId = pair['paramId']!;
          final paramHex = paramId.toLowerCase().replaceAll("0x", "");
          final paramNum = int.tryParse(paramHex, radix: 16);
          
          if (paramNum != null) {
            // If this is a standard gain param (0x0), also send to master gain (0x60)
            if (paramNum == 0) {
              _controlService.setFaderValue(pair['address']!, "0x60", value);
              _faderComm.reportFaderMoved(pair['address']!, "0x60", value);
              debugPrint('  Also sending to N-gain master: ${pair['address']}:0x60');
            }
            // If this is master gain (0x60), also send to channel 1 (0x0)
            else if (paramNum == 0x60) {
              _controlService.setFaderValue(pair['address']!, "0x0", value);
              _faderComm.reportFaderMoved(pair['address']!, "0x0", value);
              debugPrint('  Also sending to Channel 1: ${pair['address']}:0x0');
            }
            // If this is a channel gain, also send to master gain
            else if (paramNum > 0 && paramNum <= 0x10) {
              _controlService.setFaderValue(pair['address']!, "0x60", value);
              _faderComm.reportFaderMoved(pair['address']!, "0x60", value);
              debugPrint('  Also sending to N-gain master: ${pair['address']}:0x60');
            }
          }
        } catch (e) {
          debugPrint('Error in sending to additional N-gain parameters: $e');
        }
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
  
  // Enhanced data for multi-address debugging
  Map<String, int> _lastValueByAddress = {};
  Map<String, DateTime> _lastUpdateByAddress = {};
  
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
    if (_addressParamPairs.length > 1) {
      debugPrint('MULTI-ADDRESS SOURCE SELECTOR: ${widget.control.name} has ${_addressParamPairs.length} address/parameter pairs:');
      for (var pair in _addressParamPairs) {
        debugPrint('  • ${pair['address']}:${pair['paramId']}');
      }
    }
    
    debugPrint('XmlSourceControl: Source Options: ${_sourceOptions.length}');
    
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
    
    // IMPROVED: Better source update handling with enhanced matching logic
    var sourceSub = _controlService.onSourceUpdate.listen((data) {
      final receivedAddress = widget.normalizeAddressCase(data['address'].toString());
      final receivedParamId = widget.normalizeParamIdCase(data['paramId'].toString());
      final value = data['value'] as int;
      
      // Log received update for debugging
      debugPrint('XmlSourceControl ${widget.control.name}: Received update, checking if matches:');
      debugPrint('  Received: $receivedAddress:$receivedParamId, value: $value');
      
      // Store value by address for tracking
      final addressKey = '$receivedAddress:$receivedParamId';
      _lastValueByAddress[addressKey] = value;
      _lastUpdateByAddress[addressKey] = DateTime.now();
      
      // Check with enhanced matching logic
      _tryMatchAndUpdateSource(receivedAddress, receivedParamId, value, "ControlService");
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
  
  // ENHANCED: New centralized matching logic with more flexible address comparison
  void _tryMatchAndUpdateSource(String? receivedAddress, String? receivedParamId, int value, String source) {
    if (receivedAddress == null || receivedParamId == null) return;
    
    // Convert for consistent comparison
    final receivedAddressLower = receivedAddress.toLowerCase();
    final receivedParamIdLower = receivedParamId.toLowerCase();
    
    // Try to match against any of our addresses
    bool matched = false;
    for (var pair in _addressParamPairs) {
      final pairAddress = pair['address']?.toLowerCase();
      final pairParamId = pair['paramId']?.toLowerCase();
      
      // Enhanced matching strategy
      bool addressMatches = false;
      bool paramIdMatches = false;
      
      // Try direct string comparison first
      addressMatches = pairAddress == receivedAddressLower;
      paramIdMatches = pairParamId == receivedParamIdLower;
      
      // If direct match fails, try numeric comparison for both
      if (!addressMatches || !paramIdMatches) {
        try {
          // For addresses - strip 0x and compare numeric values
          final pairAddressHex = pairAddress?.replaceAll("0x", "") ?? "";
          final receivedAddressHex = receivedAddressLower.replaceAll("0x", "");
          
          // Try to match by numeric value
          if (pairAddressHex.isNotEmpty && receivedAddressHex.isNotEmpty) {
            final pairAddressNum = int.parse(pairAddressHex, radix: 16);
            final receivedAddressNum = int.parse(receivedAddressHex, radix: 16);
            addressMatches = pairAddressNum == receivedAddressNum;
          }
          
          // For paramIds - strip 0x and compare numeric values 
          final pairParamHex = pairParamId?.replaceAll("0x", "") ?? "";
          final receivedParamHex = receivedParamIdLower.replaceAll("0x", "");
          
          if (pairParamHex.isNotEmpty && receivedParamHex.isNotEmpty) {
            final pairParamNum = int.parse(pairParamHex, radix: 16);
            final receivedParamNum = int.parse(receivedParamHex, radix: 16);
            paramIdMatches = pairParamNum == receivedParamNum;
          }
          
          // Last resort - compare just the last digit of paramId
          if (!paramIdMatches && pairParamHex.isNotEmpty && receivedParamHex.isNotEmpty) {
            final pairLastDigit = pairParamHex.substring(pairParamHex.length - 1);
            final receivedLastDigit = receivedParamHex.substring(receivedParamHex.length - 1);
            paramIdMatches = pairLastDigit == receivedLastDigit;
          }
        } catch (e) {
          debugPrint('Error in enhanced matching: $e');
        }
      }
      
      // If we have a match, update UI
      if (addressMatches && paramIdMatches) {
        debugPrint('  ✓ MATCHED with ${pair['address']}:${pair['paramId']}');
        matched = true;
        
        final now = DateTime.now();
        
        // Update UI with visual feedback
        setState(() {
          _sourceValue = value;
          _isUpdatingFromDevice = true;
          _lastUpdateSource = source;
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
        // Enhanced debug output
        debugPrint('  ✗ NO MATCH with ${pair['address']}:${pair['paramId']}');
        debugPrint('    Address match: $addressMatches, ParamId match: $paramIdMatches');
        
        // Extra debug for hex values
        try {
          final pairAddressHex = pairAddress?.replaceAll("0x", "") ?? "";
          final receivedAddressHex = receivedAddressLower.replaceAll("0x", "");
          final pairParamHex = pairParamId?.replaceAll("0x", "") ?? "";
          final receivedParamHex = receivedParamIdLower.replaceAll("0x", "");
          
          debugPrint('    Hex comparison - Pair: $pairAddressHex:$pairParamHex, Received: $receivedAddressHex:$receivedParamHex');
        } catch (e) {
          // Ignore parsing errors in debug
        }
      }
    }
    
    if (!matched) {
      debugPrint('  ✗ NO MATCH FOUND for any address/paramId pair');
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
          
          // Connection and address count - ENHANCED for multi-address
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
              // ENHANCED: Multi-address indicator with color
              Icon(
                Icons.link,
                color: _addressParamPairs.length > 1 ? Colors.orange : Colors.blue,
                size: 10,
              ),
              const SizedBox(width: 2),
              Text(
                '${_addressParamPairs.length}',
                style: TextStyle(
                  color: _addressParamPairs.length > 1 ? Colors.orange : Colors.blue,
                  fontWeight: _addressParamPairs.length > 1 ? FontWeight.bold : FontWeight.normal,
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
          
          // ENHANCED: Multi-address indicator for more clarity
          _addressParamPairs.length > 1 
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'Multi-selector linked to ${_addressParamPairs.length} destinations',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    // Compact addresses list
                    Text(
                      _addressParamPairs.map((p) => p['address']?.substring(0, 14)).join(', '),
                      style: TextStyle(color: Colors.grey[400], fontSize: 8),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
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
  
  // ENHANCED: Select a source and send to ALL linked addresses
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