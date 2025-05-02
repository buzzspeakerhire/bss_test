// lib/services/message_processor_service.dart

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
  bool _useDirectProcessing = true;
  
  // Initialize the service - simplified to use direct processing for reliability
  Future<void> initialize() async {
    // If already initialized, just return
    if (_messageProcessorIsolate != null) return;
    
    Logger().log('Initializing message processor service - using direct processing for reliability');
    
    // Use direct processing for more reliable operation
    _useDirectProcessing = true;
    return;
  }
  
  // Process a message
  void processMessage(List<int> message) {
    try {
      Logger().log('Processing message of length: ${message.length}');
      final processedMessage = _processMessageDirect(message);
      if (processedMessage != null) {
        Logger().log('Successfully processed message: ${processedMessage['type']}');
        _safeAddToStream(_processedMessageController, processedMessage);
      } else {
        Logger().log('Failed to process message: null result');
      }
    } catch (e) {
      Logger().log('Error processing message: $e');
    }
  }
  
  // Direct processing method
  Map<String, dynamic>? _processMessageDirect(List<int> message) {
    try {
      return _processMessageInIsolate(message);
    } catch (e) {
      Logger().log('Error in direct message processing: $e');
      return {'error': 'Processing error', 'message': e.toString()};
    }
  }
  
  // Process a message - static implementation used by both direct and isolate paths
  static Map<String, dynamic>? _processMessageInIsolate(List<int> message) {
    try {
      // Check for valid message length
      if (message.length < 3) {
        debugPrint('Message too short: ${message.length}');
        return null;
      }
      
      // Log the hex representation of the message
      String hexMessage = message.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      debugPrint('Processing message: $hexMessage');
      
      // Extract the body (between start and end bytes)
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
      
      // Log unsubstituted body
      String hexUnsubBody = unsubstitutedBody.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      debugPrint('Unsubstituted body: $hexUnsubBody');
      
      // Verify checksum
      if (unsubstitutedBody.length < 2) {
        debugPrint('Unsubstituted body too short: ${unsubstitutedBody.length}');
        return null;
      }
      
      int receivedChecksum = unsubstitutedBody.last;
      unsubstitutedBody.removeLast();
      
      int calculatedChecksum = 0;
      for (int b in unsubstitutedBody) {
        calculatedChecksum ^= b;
      }
      
      if (receivedChecksum != calculatedChecksum) {
        debugPrint('Checksum mismatch: received=$receivedChecksum, calculated=$calculatedChecksum');
        return {'error': 'Checksum mismatch', 'receivedChecksum': receivedChecksum, 'calculatedChecksum': calculatedChecksum};
      }
      
      // Parse message
      if (unsubstitutedBody.isEmpty) {
        debugPrint('Empty body after checksum removal');
        return null;
      }
      
      int msgType = unsubstitutedBody[0];
      if (msgType == 0x88) { // SET message
        // Extract address, paramId, and value
        if (unsubstitutedBody.length < 13) {
          debugPrint('SET message too short: ${unsubstitutedBody.length}');
          return null;
        }
        
        List<int> address = unsubstitutedBody.sublist(1, 7); // 6 bytes address
        int paramId = (unsubstitutedBody[7] << 8) | unsubstitutedBody[8];
        int value = (unsubstitutedBody[9] << 24) | 
                   (unsubstitutedBody[10] << 16) | 
                   (unsubstitutedBody[11] << 8) | 
                    unsubstitutedBody[12];
        
        // Debug output for SET message
        String addressHex = address.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
        debugPrint('SET message - address: 0x$addressHex, paramId: 0x${paramId.toRadixString(16)}, value: $value');
        
        return {
          'type': 'SET',
          'address': address,
          'paramId': paramId,
          'value': value
        };
      } else if (msgType == 0x8D) { // SET_PERCENT message
        // Similar to SET but with percent value
        if (unsubstitutedBody.length < 13) {
          debugPrint('SET_PERCENT message too short: ${unsubstitutedBody.length}');
          return null;
        }
        
        List<int> address = unsubstitutedBody.sublist(1, 7);
        int paramId = (unsubstitutedBody[7] << 8) | unsubstitutedBody[8];
        int value = (unsubstitutedBody[9] << 24) | 
                   (unsubstitutedBody[10] << 16) | 
                   (unsubstitutedBody[11] << 8) | 
                    unsubstitutedBody[12];
        
        // Debug output for SET_PERCENT message
        String addressHex = address.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
        debugPrint('SET_PERCENT message - address: 0x$addressHex, paramId: 0x${paramId.toRadixString(16)}, value: $value');
        
        return {
          'type': 'SET_PERCENT',
          'address': address,
          'paramId': paramId,
          'value': value
        };
      } else if (msgType == 0x06) { // ACK
        debugPrint('ACK message received');
        return {'type': 'ACK'};
      } else if (msgType == 0x15) { // NAK
        debugPrint('NAK message received');
        return {'type': 'NAK'};
      }
      
      debugPrint('Unknown message type: ${msgType.toRadixString(16)}');
      return {'type': 'UNKNOWN', 'msgType': msgType};
    } catch (e) {
      debugPrint('Error processing message: $e');
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