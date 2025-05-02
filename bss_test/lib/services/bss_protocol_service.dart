// lib/services/bss_protocol_service.dart

import '../utils/logger.dart';
import 'dart:math';

/// Service that handles the BSS London Direct Inject protocol
class BssProtocolService {
  // Singleton instance
  static final BssProtocolService _instance = BssProtocolService._internal();
  factory BssProtocolService() => _instance;
  BssProtocolService._internal();
  
  // Protocol message types
  static const int MSG_TYPE_SET = 0x88;
  static const int MSG_TYPE_SUBSCRIBE = 0x89;
  static const int MSG_TYPE_UNSUBSCRIBE = 0x8A;
  static const int MSG_TYPE_RECALL_PRESET = 0x8C;
  static const int MSG_TYPE_SET_PERCENT = 0x8D;
  static const int MSG_TYPE_SUBSCRIBE_PERCENT = 0x8E;
  static const int MSG_TYPE_UNSUBSCRIBE_PERCENT = 0x8F;
  static const int MSG_TYPE_BUMP_PERCENT = 0x90;
  
  // Special bytes
  static const int START_BYTE = 0x02;
  static const int END_BYTE = 0x03;
  static const int ACK_BYTE = 0x06;
  static const int NAK_BYTE = 0x15;
  static const int ESCAPE_BYTE = 0x1B;

  // BSS Fader value constants (based on docs)
  static const int BSS_MIN_VALUE = -280617;  // -80dB
  static const int BSS_MAX_VALUE = 100000;   // +10dB
  static const int BSS_UNITY_VALUE = 0;      // 0dB
  static const double BSS_UNITY_NORMALIZED = 0.7373; // Point where 0dB occurs on fader
  
  // New constants for hybrid mapping
  static const double DB_10_NEGATIVE = -10.0; // -10dB boundary
  static const int BSS_10DB_NEGATIVE_VALUE = -30100; // Estimated device value for -10dB
  static const double NORMALIZED_10DB_NEGATIVE = 0.6; // Estimated normalized value for -10dB
  
  // Parse HiQnet address string to list of bytes
  List<int> parseHiQnetAddress(String addressHex) {
    final hexString = addressHex.replaceAll("0x", "").replaceAll(" ", "");
    final bytes = <int>[];
    
    for (int i = 0; i < hexString.length; i += 2) {
      if (i + 2 <= hexString.length) {
        bytes.add(int.parse(hexString.substring(i, i + 2), radix: 16));
      }
    }
    
    return bytes;
  }
  
  // Generate a command with checksum and byte substitution
  List<int> generateCommand(int commandType, List<int> addressBytes, int paramId, [int value = 0, int meterRate = 0]) {
    // Command structure:
    // 0x02 (start) + commandType + Address + ParamID + Value (optional) + Checksum + 0x03 (end)
    
    final command = <int>[commandType]; // Command type (SET, SUBSCRIBE, etc.)
    
    // Add address bytes
    command.addAll(addressBytes);
    
    // Add parameter ID (2 bytes)
    command.add((paramId >> 8) & 0xFF); // High byte
    command.add(paramId & 0xFF);        // Low byte
    
    // Add value (4 bytes) - only for SET commands
    if (commandType == MSG_TYPE_SET || commandType == MSG_TYPE_SET_PERCENT || commandType == MSG_TYPE_BUMP_PERCENT) {
      command.add((value >> 24) & 0xFF); // Byte 1 (MSB)
      command.add((value >> 16) & 0xFF); // Byte 2
      command.add((value >> 8) & 0xFF);  // Byte 3
      command.add(value & 0xFF);         // Byte 4 (LSB)
    } 
    // For meter parameter subscription, add meter rate
    else if ((commandType == MSG_TYPE_SUBSCRIBE || commandType == MSG_TYPE_SUBSCRIBE_PERCENT) && meterRate > 0) {
      command.add(0x00);                    // Byte 1 (MSB)
      command.add(0x00);                    // Byte 2
      command.add((meterRate >> 8) & 0xFF); // Byte 3
      command.add(meterRate & 0xFF);        // Byte 4 (LSB)
    }
    // For other commands that need data payload
    else if (commandType == MSG_TYPE_SUBSCRIBE || commandType == MSG_TYPE_UNSUBSCRIBE || 
             commandType == MSG_TYPE_SUBSCRIBE_PERCENT || commandType == MSG_TYPE_UNSUBSCRIBE_PERCENT) {
      command.add(0x00); // Byte 1 (MSB)
      command.add(0x00); // Byte 2
      command.add(0x00); // Byte 3
      command.add(0x00); // Byte 4 (LSB)
    }
    
    // Calculate checksum (XOR of all bytes in the command)
    int checksum = 0;
    for (int byte in command) {
      checksum ^= byte;
    }
    command.add(checksum);
    
    // Perform byte substitution
    final substitutedCommand = <int>[];
    for (int byte in command) {
      if (byte == START_BYTE) {
        substitutedCommand.addAll([ESCAPE_BYTE, 0x82]);
      } else if (byte == END_BYTE) {
        substitutedCommand.addAll([ESCAPE_BYTE, 0x83]);
      } else if (byte == ACK_BYTE) {
        substitutedCommand.addAll([ESCAPE_BYTE, 0x86]);
      } else if (byte == NAK_BYTE) {
        substitutedCommand.addAll([ESCAPE_BYTE, 0x95]);
      } else if (byte == ESCAPE_BYTE) {
        substitutedCommand.addAll([ESCAPE_BYTE, 0x9B]);
      } else {
        substitutedCommand.add(byte);
      }
    }
    
    // Add start and end bytes
    return [START_BYTE, ...substitutedCommand, END_BYTE];
  }
  
  // Generate a SET command (0x88)
  List<int> generateSetCommand(List<int> addressBytes, int paramId, int value) {
    return generateCommand(MSG_TYPE_SET, addressBytes, paramId, value);
  }
  
  // Generate a SET command from string address
  List<int> generateSetCommandFromString(String addressHex, String paramIdHex, int value) {
    final address = parseHiQnetAddress(addressHex);
    final paramId = int.parse(paramIdHex.replaceAll("0x", ""), radix: 16);
    return generateSetCommand(address, paramId, value);
  }
  
  // Generate a SET_PERCENT command (0x8D)
  List<int> generateSetPercentCommand(List<int> addressBytes, int paramId, int percentValue) {
    return generateCommand(MSG_TYPE_SET_PERCENT, addressBytes, paramId, percentValue);
  }
  
  // Generate a SUBSCRIBE command (0x89) with meter rate option
  List<int> generateSubscribeCommand(List<int> addressBytes, int paramId, [int meterRate = 0]) {
    return generateCommand(MSG_TYPE_SUBSCRIBE, addressBytes, paramId, 0, meterRate);
  }
  
  // Generate a SUBSCRIBE_PERCENT command (0x8E) with meter rate option
  List<int> generateSubscribePercentCommand(List<int> addressBytes, int paramId, [int meterRate = 0]) {
    return generateCommand(MSG_TYPE_SUBSCRIBE_PERCENT, addressBytes, paramId, 0, meterRate);
  }
  
  // Generate an UNSUBSCRIBE command (0x8A)
  List<int> generateUnsubscribeCommand(List<int> addressBytes, int paramId) {
    return generateCommand(MSG_TYPE_UNSUBSCRIBE, addressBytes, paramId);
  }
  
  // Generate an UNSUBSCRIBE_PERCENT command (0x8F)
  List<int> generateUnsubscribePercentCommand(List<int> addressBytes, int paramId) {
    return generateCommand(MSG_TYPE_UNSUBSCRIBE_PERCENT, addressBytes, paramId);
  }
  
  // Convert dB value to normalized range for meter display (0.0 to 1.0)
  double dbToNormalizedValue(double dbValue, {double minDb = -80.0, double maxDb = 40.0}) {
    final normalizedValue = (dbValue - minDb) / (maxDb - minDb);
    return normalizedValue.clamp(0.0, 1.0);
  }
  
  // Convert normalized value (0.0 to 1.0) to dB for meter display
  double normalizedToDbValue(double normalizedValue, {double minDb = -80.0, double maxDb = 40.0}) {
    return minDb + normalizedValue * (maxDb - minDb);
  }
  
  // Convert normalized value (0.0 to 1.0) to device value for faders
  int normalizedToFaderValue(double normalizedValue) {
    Logger().log('Converting normalized fader value: $normalizedValue');
    
    double deviceValueDouble;
    
    // Handle edge cases
    if (normalizedValue <= 0.0) {
      return BSS_MIN_VALUE;  // Minimum (-80dB)
    } 
    else if (normalizedValue >= 1.0) {
      return BSS_MAX_VALUE;  // Maximum (+10dB)
    }
    else if ((normalizedValue - BSS_UNITY_NORMALIZED).abs() < 0.001) {
      return BSS_UNITY_VALUE;  // Unity (0dB)
    }
    
    // Hybrid approach:
    // 1. Logarithmic from -80dB to -10dB
    // 2. Linear from -10dB to +10dB
    if (normalizedValue <= NORMALIZED_10DB_NEGATIVE) {
      // Logarithmic scaling for -80dB to -10dB
      // Map 0.0 -> -80dB (BSS_MIN_VALUE), NORMALIZED_10DB_NEGATIVE -> -10dB (BSS_10DB_NEGATIVE_VALUE)
      double normalizedInRange = normalizedValue / NORMALIZED_10DB_NEGATIVE; // 0-1 within this range
      
      // Convert to dB on logarithmic scale (exponential mapping)
      double dbRange = 80.0 - 10.0; // Range from -80 to -10 = 70dB
      double dbValue = -80.0 + (pow(normalizedInRange, 0.5) * dbRange); // Square root for log curve
      
      // Convert dB to device value
      if (dbValue <= -60.0) {
        // For very low values, use special scaling
        double attenFactor = (dbValue + 80.0) / 70.0; // 0-1 range within the -80 to -10 range
        deviceValueDouble = BSS_MIN_VALUE * (1.0 - attenFactor) + BSS_10DB_NEGATIVE_VALUE * attenFactor;
      } else {
        // For higher values, use more precise calculation
        double fraction = (dbValue + 80.0) / 70.0; // 0-1 range 
        deviceValueDouble = BSS_MIN_VALUE + fraction * (BSS_10DB_NEGATIVE_VALUE - BSS_MIN_VALUE);
      }
    } else {
      // Linear scaling for -10dB to +10dB (above NORMALIZED_10DB_NEGATIVE)
      double normalizedInRange = (normalizedValue - NORMALIZED_10DB_NEGATIVE) / 
                                 (1.0 - NORMALIZED_10DB_NEGATIVE); // 0-1 within this range
      
      deviceValueDouble = BSS_10DB_NEGATIVE_VALUE + 
                        normalizedInRange * (BSS_MAX_VALUE - BSS_10DB_NEGATIVE_VALUE);
    }
    
    // Round to integer and apply range limits
    int deviceValue = deviceValueDouble.round();
    deviceValue = deviceValue.clamp(BSS_MIN_VALUE, BSS_MAX_VALUE);
    
    Logger().log('Hybrid mapping calculated device value: $deviceValue');
    return deviceValue;
  }
  
  // Convert device value to normalized value (0.0 to 1.0) for faders
  double faderValueToNormalized(int deviceValue) {
    // Enhanced logging for debugging
    Logger().log('=== FADER VALUE CONVERSION DEBUG ===');
    Logger().log('RAW PROCESSOR VALUE: $deviceValue (decimal)');
    Logger().log('RAW PROCESSOR VALUE: 0x${deviceValue.toRadixString(16).toUpperCase()} (hex)');
    
    // Handle signed values
    double signedValue = deviceValue.toDouble();
    if (deviceValue > 0x7FFFFFFF) {
      signedValue = deviceValue - 0x100000000;
      Logger().log('CONVERTED TO SIGNED: $signedValue (from unsigned value)');
    } else {
      Logger().log('VALUE IS ALREADY SIGNED: $signedValue');
    }
    
    double normalizedValue;
    
    // Hybrid approach:
    // 1. Logarithmic from -80dB to -10dB
    // 2. Linear from -10dB to +10dB
    
    // Handle edge cases
    if (signedValue <= BSS_MIN_VALUE) {
      normalizedValue = 0.0;
    } 
    else if (signedValue >= BSS_MAX_VALUE) {
      normalizedValue = 1.0;
    }
    else if (signedValue == BSS_UNITY_VALUE) {
      normalizedValue = BSS_UNITY_NORMALIZED;
    }
    // Below -10dB (logarithmic range)
    else if (signedValue <= BSS_10DB_NEGATIVE_VALUE) {
      // Logarithmic scaling
      double fraction = (signedValue - BSS_MIN_VALUE) / (BSS_10DB_NEGATIVE_VALUE - BSS_MIN_VALUE);
      fraction = pow(fraction, 2.0).toDouble(); // Square for log curve (inverse of square root)
      normalizedValue = fraction * NORMALIZED_10DB_NEGATIVE;
    }
    // Above -10dB (linear range)
    else {
      // Linear scaling
      double fraction = (signedValue - BSS_10DB_NEGATIVE_VALUE) / 
                       (BSS_MAX_VALUE - BSS_10DB_NEGATIVE_VALUE);
      normalizedValue = NORMALIZED_10DB_NEGATIVE + fraction * (1.0 - NORMALIZED_10DB_NEGATIVE);
    }
    
    // Ensure value is within valid range
    normalizedValue = normalizedValue.clamp(0.0, 1.0);
    
    // Calculate approximate dB for logging
    double dbValue;
    if (signedValue >= 0) {
      dbValue = (signedValue / BSS_MAX_VALUE.toDouble()) * 10.0; // 0 to +10dB
      Logger().log('ESTIMATED dB VALUE: +${dbValue.toStringAsFixed(1)}dB');
    } else if (signedValue >= BSS_10DB_NEGATIVE_VALUE) {
      // Linear range from -10dB to 0dB
      double fraction = (signedValue - BSS_10DB_NEGATIVE_VALUE) / (BSS_UNITY_VALUE - BSS_10DB_NEGATIVE_VALUE);
      dbValue = -10.0 + fraction * 10.0;
      Logger().log('ESTIMATED dB VALUE: ${dbValue.toStringAsFixed(1)}dB (linear range)');
    } else {
      // Logarithmic range from -80dB to -10dB
      double fraction = (signedValue - BSS_MIN_VALUE) / (BSS_10DB_NEGATIVE_VALUE - BSS_MIN_VALUE);
      dbValue = -80.0 + fraction * 70.0; // 70dB range
      Logger().log('ESTIMATED dB VALUE: ${dbValue.toStringAsFixed(1)}dB (logarithmic range)');
    }
    
    Logger().log('HYBRID MAPPING: value=$signedValue');
    Logger().log('FINAL NORMALIZED VALUE: ${normalizedValue.toStringAsFixed(6)}');
    Logger().log('FINAL PERCENT VALUE: ${(normalizedValue * 100).toStringAsFixed(2)}%');
    Logger().log('=== END FADER CONVERSION DEBUG ===');
    
    return normalizedValue;
  }
}