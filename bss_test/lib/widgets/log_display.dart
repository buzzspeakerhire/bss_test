import 'package:flutter/material.dart';

class LogDisplay extends StatelessWidget {
  final List<String> logs;
  final Function() onClear;
  
  const LogDisplay({
    super.key,
    required this.logs,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: const Text('Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      initiallyExpanded: true,
      children: [
        Container(
          height: 200,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(4),
          ),
          child: logs.isEmpty 
            ? const Text(
                'No logs yet. Connect to a device to see communications.',
                style: TextStyle(fontStyle: FontStyle.italic),
              )
            : ListView.builder(
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  return Text(
                    logs[index],
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  );
                },
              ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: onClear,
          child: const Text('Clear Log'),
        ),
      ],
    );
  }
}