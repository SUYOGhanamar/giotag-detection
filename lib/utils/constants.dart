// lib/utils/constants.dart
// Application-wide constants for VeriPic

class AppConstants {
  // GPS tolerance for watermark vs EXIF comparison (in degrees, ~111m per degree)
  static const double gpsToleranceDegrees = 0.001; // ~111 meters

  // Timestamp tolerance for watermark vs EXIF comparison
  static const int timestampToleranceSeconds = 10;

  // LSB steganography: bits per channel used (1 or 2)
  static const int lsbBitsPerChannel = 2;

  // Watermark magic header (4 bytes) to detect VeriPic watermarks
  static const List<int> watermarkMagic = [0x56, 0x50, 0x49, 0x43]; // 'VPIC'

  // NVIDIA API endpoint
  static const String nvidiaApiBase = 'https://integrate.api.nvidia.com/v1';
  static const String nvidiaChatEndpoint = '$nvidiaApiBase/chat/completions';

  // Deepfake score thresholds
  static const double deepfakeHighThreshold   = 0.65; // above → deepfake
  static const double deepfakeMediumThreshold = 0.35; // above → suspicious

  // Secure storage keys
  static const String signingSecretKey = 'veripic_signing_secret';
  static const String deviceIdKey      = 'veripic_device_id';
}
