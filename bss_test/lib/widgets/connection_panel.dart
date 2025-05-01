import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ConnectionPanel extends StatelessWidget {
  final TextEditingController ipAddressController;
  final TextEditingController portController;
  final bool isConnected;
  final bool isConnecting;
  final Function() onConnect;
  final Function() onDisconnect;
  final Function() onOpenPanelLoader;
  
  const ConnectionPanel({
    super.key,
    required this.ipAddressController,
    required this.portController,
    required this.isConnected,
    required this.isConnecting,
    required this.onConnect,
    required this.onDisconnect,
    required this.onOpenPanelLoader,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Connection Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ipAddressController,
                    decoration: const InputDecoration(
                      labelText: 'IP Address',
                      border: OutlineInputBorder(),
                      hintText: '192.168.0.20',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: portController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                      hintText: '1023',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  onPressed: isConnected || isConnecting ? null : onConnect,
                  child: const Text('Connect'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: isConnected ? onDisconnect : null,
                  child: const Text('Disconnect'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: onOpenPanelLoader,
                  child: const Text('Open Panel Loader'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}