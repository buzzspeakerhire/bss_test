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
  
  // Flag to indicate if direct processing should be used
  bool _useDirectProcessing = false;
  
  // Initialize the isolate for message processing
  Future<void> initialize() async {
    // If already initialized, just return
    if (_messageProcessorIsolate != null) return;
    
    try {
      _receivePort = ReceivePort();
      _messageProcessorIsolate = await Isolate.spawn(
        _messageProcessorEntryPoint, 
        _receivePort!.sendPort
      );
      
      _receivePort!.listen((message) {
        try {
          if (message is SendPort) {
            _sendPort = message;
            Logger().log('Message processor isolate connected');
          } else if (message is Map) {
            // Handle processed messages from isolate
            if (message['type'] == 'processedMessage') {
              _safeAddToStream(_processedMessageController, message['data']);
            } else if (message['type'] == 'log') {
              Logger().log(message['message']);
            }
          }
        } catch (e) {
          Logger().log('Error handling isolate message: $e');
        }
      }, onError: (e) {
        Logger().log('Error from isolate: $e');
        _useDirectProcessing = true;
      });
      
      Logger().log('Message processor initialized');
    } catch (e) {
      Logger().log('Failed to initialize message processor: $e');
      // Clean up any partial initialization
      _messageProcessorIsolate?.kill(priority: Isolate.immediate);
      _messageProcessorIsolate = null;
      _receivePort?.close();
      _receivePort = null;
      
      // Fall back to direct processing
      _useDirectProcessing = true;
      Logger().log('Using direct message processing as fallback');
    }
  }
  
  // Process a message
  void processMessage(List<int> message) {
    if (_sendPort != null && !_useDirectProcessing) {
      // Send to isolate
      _sendPort!.send(message);
    } else {
      // Fallback to direct processing
      try {
        final processedMessage = _processMessageDirect(message);
        if (processedMessage != null) {
          _safeAddToStream(_processedMessageController, processedMessage);
        }
      } catch (e) {
        Logger().log('Error processing message directly: $e');
      }
    }
  }
  
  // Direct processing method as fallback
  Map<String, dynamic>? _processMessageDirect(List<int> message) {
    try {
      return _processMessageInIsolate(message);
    } catch (e) {
      Logger().log('Error in direct message processing: $e');
      return {'error': 'Processing error', 'message': e.toString()};
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
  
  // Process a message in the isolate or directly
  static Map<String, dynamic>? _processMessageInIsolate(List<int> message) {
    try {
      // Check for valid message length
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
        return {'error': 'Checksum mismatch', 'receivedChecksum': receivedChecksum, 'calculatedChecksum': calculatedChecksum};
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
      
      return {'type': 'UNKNOWN', 'msgType': msgType};
    } catch (e) {
      return {'error': 'Processing error', 'message': e.toString()};
    }
  }
  
  // Helper method to safely add data to a stream without blocking
  void _safeAddToStream<T>(StreamController<T> controller, T data) {
    if (!controller.isClosed) {
      try {
        controller.add(data);
      } catch (e) {
        Logger().log('Error adding to stream: $e');
      }
    }
  }
  
  // Clean up resources
  void dispose() {
    _messageProcessorIsolate?.kill(priority: Isolate.immediate);
    _messageProcessorIsolate = null;
    _receivePort?.close();
    _receivePort = null;
    _processedMessageController.close();
  }
}