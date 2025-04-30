import 'package:flutter/material.dart';

/// Helper class to manage orientation and scaling for panel layouts
class OrientationHelper {
  /// Calculate the optimal scale factor to fit content to screen
  static double calculateScaleFactor(
    Size contentSize, 
    Size screenSize, {
    double padding = 0,
    double minScale = 0.1,
    double maxScale = 5.0,
  }) {
    // Adjust screen size for padding
    final availableWidth = screenSize.width - (padding * 2);
    final availableHeight = screenSize.height - (padding * 2);
    
    // Calculate scaling factors for width and height
    final scaleWidth = availableWidth / contentSize.width;
    final scaleHeight = availableHeight / contentSize.height;
    
    // Use the smaller scale factor to ensure content fits entirely
    double scaleFactor = scaleWidth < scaleHeight ? scaleWidth : scaleHeight;
    
    // Apply scaling limits
    scaleFactor = scaleFactor.clamp(minScale, maxScale);
    
    return scaleFactor;
  }
  
  /// Determine if the device is in landscape orientation
  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }
  
  /// Get the optimal transformation matrix for initial display
  static Matrix4 getOptimalTransformationMatrix(
    Size contentSize,
    Size screenSize, {
    double padding = 0,
    double offsetX = 0,
    double offsetY = 0,
  }) {
    final scaleFactor = calculateScaleFactor(
      contentSize, 
      screenSize, 
      padding: padding,
    );
    
    // Calculate centering offset
    final centeredX = (screenSize.width - (contentSize.width * scaleFactor)) / 2;
    final centeredY = (screenSize.height - (contentSize.height * scaleFactor)) / 2;
    
    // Create transformation matrix with scaling and translation
    final matrix = Matrix4.identity();
    
    // Apply scaling
    matrix.scale(scaleFactor, scaleFactor);
    
    // Apply translation for centering
    matrix.translate(
      offsetX + (centeredX / scaleFactor), 
      offsetY + (centeredY / scaleFactor),
    );
    
    return matrix;
  }
  
  /// Check if the device has a notch or dynamic island that needs to be accounted for
  static bool hasNotch(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    // If top padding is significant, device likely has a notch
    return padding.top > 24;
  }
  
  /// Get safe area padding adjustments for the current device
  static EdgeInsets getSafeAreaPadding(BuildContext context) {
    return MediaQuery.of(context).padding;
  }
  
  /// Detect if the device is a tablet (based on screen size)
  static bool isTablet(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    return shortestSide >= 600;
  }
}