import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import '../utils/logger.dart';

/// Service for processing BSS protocol messages
class MessageProcessorService {
  // Singleton instance
  static final MessageProcessorService _instance = MessageProcessorService._internal();
  factory MessageProcessorService() => _instance;
  MessageProcessorService._internal();
  
  // Isolate for message processing
  Isolate? _messageProcessorIsolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  
  // Stream controller for processed messages
  final _processedMessageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onProcessedMessage => _processedMessageController.stream;
  
  // Initialize the isolate for message processing
  Future<void> initialize() async {
    if (_messageProcessorIsolate != null) return;
    
    _receivePort = ReceivePort();
    _messageProcessorIsolate = await Isolate.spawn(
      _messageProcessorEntryPoint, 
      _receivePort!.sendPort
    );
    
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
      } else if (message is Map) {
        // Handle processed messages from isolate
        if (message['type'] == 'processedMessage') {
          _processedMessageController.add(message['data']);
        } else if (message['type'] == 'log') {
          Logger().log(message['message']);
        }
      }
    });
    
    Logger().log('Message processor initialized');
  }
  
  // Process a message
  void processMessage(List<int> message) {
    if (_sendPort != null) {
      _sendPort!.send(message);
    } else {
      Logger().log('Message processor not initialized');
    }
  }
  
  // Static entry point for the isolate
  static void _messageProcessorEntryPoint(SendPort sendPort) {
    final ReceivePort receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    
    receivePort.listen((message) {
      if (message is List<int>) {
        // Process the message
        try {
          final processedMessage = _processMessageInIsolate(message);
          if (processedMessage != null) {
            sendPort.send({
              'type': 'processedMessage',
              'data': processedMessage
            });
          }
        } catch (e) {
          sendPort.send({
            'type': 'log',
            'message': 'Error processing message in isolate: $e'
          });
        }
      }
    });
  }
  
  // Process a message in the isolate
  static Map<String, dynamic>? _processMessageInIsolate(List<int> message) {
    // Remove start and end bytes
    if (message.length < 3) return null;
    
    List<int> body = message.sublist(1, message.length - 1);
    
    // Perform byte substitution reversal
    List<int> unsubstitutedBody = [];
    for (int i = 0; i < body.length; i++) {
      if (body[i] == 0x1B && i + 1 < body.length) {
        if (body[i + 1] == 0x82) {
          unsubstitutedBody.add(0x02);
          i++;
        } else if (body[i + 1] == 0x83) {
          unsubstitutedBody.add(0x03);
          i++;
        } else if (body[i + 1] == 0x86) {
          unsubstitutedBody.add(0x06);
          i++;
        } else if (body[i + 1] == 0x95) {
          unsubstitutedBody.add(0x15);
          i++;
        } else if (body[i + 1] == 0x9B) {
          unsubstitutedBody.add(0x1B);
          i++;
        } else {
          unsubstitutedBody.add(body[i]);
        }
      } else {
        unsubstitutedBody.add(body[i]);
      }
    }
    
    // Verify checksum
    if (unsubstitutedBody.length < 2) return null;
    
    int receivedChecksum = unsubstitutedBody.last;
    unsubstitutedBody.removeLast();
    
    int calculatedChecksum = 0;
    for (int b in unsubstitutedBody) {
      calculatedChecksum ^= b;
    }
    
    if (receivedChecksum != calculatedChecksum) {
      return {'error': 'Checksum mismatch'};
    }
    
    // Parse message
    if (unsubstitutedBody.isEmpty) return null;
    
    int msgType = unsubstitutedBody[0];
    if (msgType == 0x88) { // SET message
      // Extract address, paramId, and value
      if (unsubstitutedBody.length < 13) return null;
      
      List<int> address = unsubstitutedBody.sublist(1, 7); // 6 bytes address
      int paramId = (unsubstitutedBody[7] << 8) | unsubstitutedBody[8];
      int value = (unsubstitutedBody[9] << 24) | 
                 (unsubstitutedBody[10] << 16) | 
                 (unsubstitutedBody[11] << 8) | 
                  unsubstitutedBody[12];
      
      return {
        'type': 'SET',
        'address': address,
        'paramId': paramId,
        'value': value
      };
    } else if (msgType == 0x8D) { // SET_PERCENT message
      // Similar to SET but with percent value
      if (unsubstitutedBody.length < 13) return null;
      
      List<int> address = unsubstitutedBody.sublist(1, 7);
      int paramId = (unsubstitutedBody[7] << 8) | unsubstitutedBody[8];
      int value = (unsubstitutedBody[9] << 24) | 
                 (unsubstitutedBody[10] << 16) | 
                 (unsubstitutedBody[11] << 8) | 
                  unsubstitutedBody[12];
      
      return {
        'type': 'SET_PERCENT',
        'address': address,
        'paramId': paramId,
        'value': value
      };
    } else if (msgType == 0x06) { // ACK
      return {'type': 'ACK'};
    } else if (msgType == 0x15) { // NAK
      return {'type': 'NAK'};
    }
    
    return null;
  }
  
  // Clean up resources
  void dispose() {
    _messageProcessorIsolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _processedMessageController.close();
  }
}