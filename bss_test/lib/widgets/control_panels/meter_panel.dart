import 'package:flutter/material.dart';
import '../../services/control_communication_service.dart';

class MeterPanel extends StatefulWidget {
  final bool isConnected;
  
  const MeterPanel({
    super.key,
    required this.isConnected,
  });

  @override
  State<MeterPanel> createState() => _MeterPanelState();
}

class _MeterPanelState extends State<MeterPanel> {
  final _controlService = ControlCommunicationService();
  
  // Text controllers
  final _meterHiQnetAddressController = TextEditingController(text: "0x2D6803000200");
  final _meterParamIdController = TextEditingController(text: "0x0");
  
  // Control values
  double _meterValue = 0.0; // -80dB to +40dB, normalized to a 0.0-1.0 range
  bool _autoRefreshMeter = true;
  int _meterRefreshRateValue = 100; // Default 100ms (10 updates per second)
  
  @override
  void initState() {
    super.initState();
    
    // Listen for meter updates
    _controlService.onMeterUpdate.listen((data) {
      setState(() {
        _meterValue = data['value'];
      });
    });
  }
  
  @override
  void dispose() {
    _meterHiQnetAddressController.dispose();
    _meterParamIdController.dispose();
    super.dispose();
  }
  
  // Toggle auto refresh of meter
  void _toggleAutoRefreshMeter(bool value) {
    setState(() {
      _autoRefreshMeter = value;
    });
    
    _controlService.setAutoRefreshMeter(value);
  }
  
  // Update refresh rate
  void _updateRefreshRate(double value) {
    setState(() {
      _meterRefreshRateValue = value.round();
    });
  }
  
  // Apply new refresh rate
  void _applyRefreshRate() {
    _controlService.setMeterRefreshRate(_meterRefreshRateValue);
  }
  
  // Refresh meter now
  void _refreshMeterNow() {
    // This would trigger a one-time refresh
    // Implementation depends on your protocol details
  }
  
  // Get color based on meter value
  Color _getDbColor(double normalizedValue) {
    if (normalizedValue < 0.7) {
      return Colors.green;
    } else if (normalizedValue < 0.9) {
      return Colors.amber;
    } else {
      return Colors.red;
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
            const Text('Signal Meter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _meterHiQnetAddressController,
                    decoration: const InputDecoration(
                      labelText: 'HiQnet Address',
                      border: OutlineInputBorder(),
                      hintText: 'Example: 0x2D6803000200',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _meterParamIdController,
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
            
            // Meter Refresh Rate slider
            Row(
              children: [
                const Text('Meter Refresh Rate:'),
                Expanded(
                  child: Slider(
                    value: _meterRefreshRateValue.toDouble(),
                    min: 10,    // 10ms (very fast)
                    max: 1000,  // 1000ms (1 second)
                    divisions: 99,
                    label: '${_meterRefreshRateValue}ms',
                    onChanged: (value) => _updateRefreshRate(value),
                    onChangeEnd: (value) {
                      if (widget.isConnected && _autoRefreshMeter) {
                        _applyRefreshRate();
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text('${_meterRefreshRateValue}ms'),
                ),
              ],
            ),
            
            Row(
              children: [
                const Text('Auto-refresh:'),
                const SizedBox(width: 8),
                Switch(
                  value: _autoRefreshMeter,
                  onChanged: widget.isConnected ? _toggleAutoRefreshMeter : null,
                ),
                const SizedBox(width: 8),
                Text(_autoRefreshMeter ? 'ON' : 'OFF'),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Meter visualization - improved with smoother animation and peak hold
            Container(
              height: 90,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('-80dB', style: TextStyle(fontSize: 12)),
                        const Text('-40dB', style: TextStyle(fontSize: 12)),
                        const Text('0dB', style: TextStyle(fontSize: 12)),
                        const Text('+20dB', style: TextStyle(fontSize: 12)),
                        const Text('+40dB', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Calculate the width of the meter bar
                          final meterWidth = constraints.maxWidth * _meterValue;
                          final dbValue = -80 + _meterValue * 120;
                          
                          return Stack(
                            children: [
                              // Background with level markings
                              Container(
                                width: constraints.maxWidth,
                                decoration: BoxDecoration(
                                  color: Colors.black12,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Row(
                                  children: [
                                    Container(width: constraints.maxWidth * (20/120), color: Colors.black.withAlpha(8)),
                                    Container(width: constraints.maxWidth * (20/120), color: Colors.black.withAlpha(15)),
                                    Container(width: constraints.maxWidth * (20/120), color: Colors.black.withAlpha(23)),
                                    Container(width: constraints.maxWidth * (20/120), color: Colors.black.withAlpha(31)),
                                    Container(width: constraints.maxWidth * (20/120), color: Colors.black.withAlpha(38)),
                                    Container(width: constraints.maxWidth * (20/120), color: Colors.black.withAlpha(46)),
                                  ],
                                ),
                              ),
                              // Meter bar with animated transition
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 100),
                                width: meterWidth,
                                decoration: BoxDecoration(
                                  color: _getDbColor(_meterValue),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              // Current value text
                              Positioned.fill(
                                child: Center(
                                  child: Text(
                                    '${dbValue.toStringAsFixed(1)} dB',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _meterValue > 0.4 ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  // Numeric readout for additional verification
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                    child: Text(
                      'Rate: ${_meterRefreshRateValue}ms   Value: ${(-80 + _meterValue * 120).toStringAsFixed(1)}dB',
                      style: const TextStyle(fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  onPressed: widget.isConnected ? _refreshMeterNow : null,
                  child: const Text('Refresh Meter Now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}