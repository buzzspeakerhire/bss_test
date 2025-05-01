/// Utility class for handling hex conversions
class HexUtils {
  /// Convert a list of bytes to a hex string
  static String bytesToHexString(List<int> bytes, {String separator = ','}) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(separator);
  }
  
  /// Convert a hex string to a list of bytes
  static List<int> hexStringToBytes(String hexString) {
    // Remove 0x prefix, spaces, and non-hex characters
    final cleanHex = hexString.replaceAll('0x', '').replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    
    // Process hex pairs
    final bytes = <int>[];
    for (int i = 0; i < cleanHex.length; i += 2) {
      // Make sure we have a complete byte
      if (i + 2 <= cleanHex.length) {
        bytes.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
      }
    }
    return bytes;
  }
  
  /// Format a value as a hex string with '0x' prefix
  static String formatHex(int value, {int padLength = 0}) {
    return '0x${value.toRadixString(16).padLeft(padLength, '0').toUpperCase()}';
  }
  
  /// Format a list of bytes as a hex string
  static String formatHexBytes(List<int> bytes, {String prefix = '0x'}) {
    return '$prefix${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}';
  }
}