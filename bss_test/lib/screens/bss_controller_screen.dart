import 'package:flutter/material.dart';
import '../services/connection_service.dart';
import '../services/control_communication_service.dart';
import '../utils/logger.dart';
import '../widgets/connection_panel.dart';
import '../widgets/control_panels/fader_panel.dart';
import '../widgets/control_panels/button_panel.dart';
import '../widgets/control_panels/meter_panel.dart';
import '../widgets/control_panels/source_selector_panel.dart';
import '../widgets/log_display.dart';
import 'panel_screens/panel_loader_screen.dart';

class BSSControllerScreen extends StatefulWidget {
  const BSSControllerScreen({super.key});

  @override
  State<BSSControllerScreen> createState() => _BSSControllerScreenState();
}

class _BSSControllerScreenState extends State<BSSControllerScreen> {
  // Services
  final _connectionService = ConnectionService();
  final _controlService = ControlCommunicationService();
  final _logger = Logger();
  
  // Connection status
  bool _isConnected = false;
  bool _isConnecting = false;
  
  // Text controllers for global control
  final _ipAddressController = TextEditingController(text: "192.168.0.20");
  final _portController = TextEditingController(text: "1023");
  
  @override
  void initState() {
    super.initState();
    
    // Listen for connection status changes
    _connectionService.onConnectionStatusChanged.listen((isConnected) {
      setState(() {
        _isConnected = isConnected;
        _isConnecting = _connectionService.isConnecting;
      });
    });
  }

  @override
  void dispose() {
    _ipAddressController.dispose();
    _portController.dispose();
    super.dispose();
  }

  // Connect to the device
  Future<void> _connect() async {
    final ip = _ipAddressController.text;
    final port = int.parse(_portController.text);
    
    final success = await _controlService.connect(
      ip: ip,
      port: port,
    );
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connected to device')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to connect')),
      );
    }
  }
  
  // Disconnect from the device
  void _disconnect() {
    _controlService.disconnect();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Disconnected from device')),
    );
  }
  
  // Open the panel loader screen
  void _openPanelLoader() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PanelLoaderScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BSS Controller'),
        actions: [
          // Connection status indicator
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected ? Colors.green : 
                           _isConnecting ? Colors.orange : Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isConnected ? 'Connected' : 
                  _isConnecting ? 'Connecting...' : 'Disconnected'
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection settings
            ConnectionPanel(
              ipAddressController: _ipAddressController,
              portController: _portController,
              isConnected: _isConnected,
              isConnecting: _isConnecting,
              onConnect: _connect,
              onDisconnect: _disconnect,
              onOpenPanelLoader: _openPanelLoader,
            ),
            
            const SizedBox(height: 16),
            
            // Meter visualization
            MeterPanel(
              isConnected: _isConnected,
            ),
            
            const SizedBox(height: 16),
            
            // Fader control
            FaderPanel(
              isConnected: _isConnected,
            ),
            
            const SizedBox(height: 16),
            
            // Button control
            ButtonPanel(
              isConnected: _isConnected,
            ),
            
            const SizedBox(height: 16),
            
            // Source selector control
            SourceSelectorPanel(
              isConnected: _isConnected,
            ),
            
            const SizedBox(height: 16),
            
            // Log display
            LogDisplay(
              logs: _logger.logs,
              onClear: () => _logger.clear(),
            ),
          ],
        ),
      ),
    );
  }
}