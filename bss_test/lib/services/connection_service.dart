import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../utils/logger.dart';

class ConnectionService {
  // Singleton instance
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;
  ConnectionService._internal();
  
  // Connection state
  bool isConnecting = false;
  bool isConnected = false;
  Socket? socket;
  StreamSubscription<Uint8List>? socketSubscription;
  
  // Connection parameters
  String ipAddress = "192.168.0.20";
  int port = 1023;
  
  // Stream controllers for event notification
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _dataReceivedController = StreamController<Uint8List>.broadcast();
  final _messageProcessorController = StreamController<List<int>>.broadcast();
  
  // Public stream getters
  Stream<bool> get onConnectionStatusChanged => _connectionStatusController.stream;
  Stream<Uint8List> get onDataReceived => _dataReceivedController.stream;
  Stream<List<int>> get onMessageExtracted => _messageProcessorController.stream;
  
  // Buffer for incoming data
  final List<int> _buffer = [];
  
  // Connect to the BSS device
  Future<bool> connect({String? ip, int? portNum}) async {
    if (isConnected || isConnecting) return false;
    
    ipAddress = ip ?? ipAddress;
    port = portNum ?? port;
    
    isConnecting = true;
    _notifyConnectionStatus();
    
    try {
      // Set a connection timeout
      socket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 5));
      
      isConnected = true;
      isConnecting = false;
      _buffer.clear();
      
      _notifyConnectionStatus();
      Logger().log('Connected to $ipAddress:$port');
      
      // Configure socket for better throughput
      socket!.setOption(SocketOption.tcpNoDelay, true);
      
      // Listen for responses from the device
      socketSubscription = socket!.listen(
        (Uint8List data) {
          try {
            // Add data to buffer
            _buffer.addAll(data);
            
            // Notify listeners of raw data
            _safeAddToStream(_dataReceivedController, data);
            
            // Process complete messages
            _processBuffer();
          } catch (e) {
            Logger().log('Error handling socket data: $e');
          }
        },
        onError: (error) {
          Logger().log('Socket error: $error');
          disconnect();
        },
        onDone: () {
          Logger().log('Socket closed');
          disconnect();
        },
        cancelOnError: false,
      );
      
      return true;
    } catch (e) {
      isConnecting = false;
      _notifyConnectionStatus();
      Logger().log('Failed to connect: $e');
      return false;
    }
  }
  
  // Disconnect from the device
  void disconnect() {
    if (!isConnected && !isConnecting) return;
    
    socketSubscription?.cancel();
    socketSubscription = null;
    
    try {
      socket?.close();
    } catch (e) {
      Logger().log('Error closing socket: $e');
    }
    
    socket = null;
    
    isConnected = false;
    isConnecting = false;
    
    _notifyConnectionStatus();
    Logger().log('Disconnected from device');
  }
  
  // Send data to the device
  Future<bool> sendData(List<int> data) async {
    if (!isConnected || socket == null) {
      Logger().log('Not connected to device');
      return false;
    }
    
    try {
      socket!.add(Uint8List.fromList(data));
      return true;
    } catch (e) {
      Logger().log('Failed to send data: $e');
      return false;
    }
  }
  
  // Process the buffer to extract complete messages
  void _processBuffer() {
    try {
      // Process complete messages
      while (_buffer.isNotEmpty) {
        // Look for start byte
        int startIndex = _buffer.indexOf(0x02);
        if (startIndex == -1) {
          _buffer.clear();
          return;
        }
        
        // Remove data before start byte
        if (startIndex > 0) {
          _buffer.removeRange(0, startIndex);
        }
        
        // Look for end byte
        int endIndex = _buffer.indexOf(0x03);
        if (endIndex == -1 || _buffer.length < endIndex + 1) {
          // Not a complete message yet, but keep buffer
          // Set a reasonable buffer size limit to prevent memory issues
          if (_buffer.length > 4096) {
            _buffer.removeRange(0, _buffer.length - 2048);
            Logger().log('Buffer size limited to prevent overflow');
          }
          return;
        }
        
        // Extract the message (including start and end bytes)
        List<int> message = _buffer.sublist(0, endIndex + 1);
        _buffer.removeRange(0, endIndex + 1);
        
        // Forward the message to the message processor - use non-blocking call
        _safeAddToStream(_messageProcessorController, message);
      }
    } catch (e) {
      Logger().log('Error processing buffer: $e');
      // Clear buffer on error to prevent repeated crashes
      _buffer.clear();
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
  
  // Notify connection status changes
  void _notifyConnectionStatus() {
    _safeAddToStream(_connectionStatusController, isConnected);
  }
  
  // Clean up resources
  void dispose() {
    disconnect();
    _connectionStatusController.close();
    _dataReceivedController.close();
    _messageProcessorController.close();
  }
}