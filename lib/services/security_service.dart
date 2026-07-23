// lib/services/security_service.dart
// Task B: Cryptographic Signing + LSB Steganographic Watermark
// Handles HMAC-SHA256 signature generation and pixel-level watermark embed/extract.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../utils/constants.dart';

// ─── Watermark Payload Model ─────────────────────────────────────────────────

/// Structured payload embedded into every VeriPic image.
class WatermarkPayload {
  final String signature; // HMAC-SHA256 hex
  final double latitude;
  final double longitude;
  final double altitude;
  final int timestampEpoch; // UTC milliseconds since epoch
  final String deviceId;
  final String imageHash; // SHA-256 of original raw bytes

  const WatermarkPayload({
    required this.signature,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.timestampEpoch,
    required this.deviceId,
    required this.imageHash,
  });

  Map<String, dynamic> toJson() => {
        'sig': signature,
        'lat': latitude,
        'lng': longitude,
        'alt': altitude,
        'ts': timestampEpoch,
        'did': deviceId,
        'hash': imageHash,
      };

  factory WatermarkPayload.fromJson(Map<String, dynamic> j) => WatermarkPayload(
        signature: j['sig'] as String,
        latitude: (j['lat'] as num).toDouble(),
        longitude: (j['lng'] as num).toDouble(),
        altitude: (j['alt'] as num).toDouble(),
        timestampEpoch: j['ts'] as int,
        deviceId: j['did'] as String,
        imageHash: j['hash'] as String,
      );

  String toJsonString() => jsonEncode(toJson());

  static WatermarkPayload? tryParse(String raw) {
    try {
      return WatermarkPayload.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

// ─── Security Service ─────────────────────────────────────────────────────────

class SecurityService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ─── Key Management ─────────────────────────────────────────────────────

  /// Returns (or initialises) the HMAC signing secret from secure storage.
  /// On first run, seeds from .env then persists in secure storage.
  static Future<String> _getSigningSecret() async {
    String? secret = await _storage.read(key: AppConstants.signingSecretKey);
    if (secret == null || secret.isEmpty) {
      // Seed from .env on first launch
      secret = dotenv.maybeGet('APP_SIGNING_SECRET') ??
          'veripic_default_secret_replace_me';
      await _storage.write(
          key: AppConstants.signingSecretKey, value: secret);
    }
    return secret;
  }

  /// Returns (or generates) a stable device UUID stored in secure storage.
  static Future<String> _getDeviceId() async {
    String? id = await _storage.read(key: AppConstants.deviceIdKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await _storage.write(key: AppConstants.deviceIdKey, value: id);
    }
    return id;
  }

  // ─── Hashing ─────────────────────────────────────────────────────────────

  /// Computes SHA-256 hash of raw image bytes.
  static String computeImageHash(Uint8List imageBytes) {
    final digest = sha256.convert(imageBytes);
    return digest.toString();
  }

  /// Builds a canonical string used as the HMAC message.
  static String _buildCanonicalMessage({
    required String imageHash,
    required double lat,
    required double lng,
    required double alt,
    required int timestampEpoch,
    required String deviceId,
  }) {
    // Fixed-precision serialization ensures deterministic output
    return [
      imageHash,
      lat.toStringAsFixed(7),
      lng.toStringAsFixed(7),
      alt.toStringAsFixed(2),
      timestampEpoch.toString(),
      deviceId,
    ].join('|');
  }

  // ─── Signing ─────────────────────────────────────────────────────────────

  /// Generates an HMAC-SHA256 signature over: SHA256(imageBytes) + GPS + timestamp.
  /// This is the primary cryptographic authenticity proof.
  static Future<String> generateImageSignature(
    Uint8List imageBytes,
    Position position,
    DateTime timestamp,
  ) async {
    final secret = await _getSigningSecret();
    final deviceId = await _getDeviceId();
    final imageHash = computeImageHash(imageBytes);
    final epochMs = timestamp.millisecondsSinceEpoch;

    final message = _buildCanonicalMessage(
      imageHash: imageHash,
      lat: position.latitude,
      lng: position.longitude,
      alt: position.altitude,
      timestampEpoch: epochMs,
      deviceId: deviceId,
    );

    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode(message));
    return digest.toString();
  }

  /// Verifies that [candidateBytes] + [payload] produce the same signature as stored.
  static Future<bool> verifySignature(
    Uint8List candidateBytes,
    WatermarkPayload payload,
  ) async {
    final secret = await _getSigningSecret();
    final currentHash = computeImageHash(candidateBytes);

    // First check: re-hash the candidate image and compare to stored hash.
    // If pixel content was modified, the hash will differ.
    if (currentHash != payload.imageHash) return false;

    // Second check: re-compute HMAC and compare.
    final message = _buildCanonicalMessage(
      imageHash: payload.imageHash,
      lat: payload.latitude,
      lng: payload.longitude,
      alt: payload.altitude,
      timestampEpoch: payload.timestampEpoch,
      deviceId: payload.deviceId,
    );

    final hmac = Hmac(sha256, utf8.encode(secret));
    final expected = hmac.convert(utf8.encode(message)).toString();
    return expected == payload.signature;
  }

  // ─── Full Frame Signing + Embedding ─────────────────────────────────────

  /// Signs the image and embeds a WatermarkPayload invisibly into its pixels.
  /// Returns PNG bytes with the watermark embedded.
  static Future<Uint8List> signAndEmbed(
    Uint8List imageBytes,
    Position position,
    DateTime timestamp,
  ) async {
    final deviceId = await _getDeviceId();
    final imageHash = computeImageHash(imageBytes);
    final epochMs = timestamp.millisecondsSinceEpoch;

    final signature = await generateImageSignature(imageBytes, position, timestamp);

    final payload = WatermarkPayload(
      signature: signature,
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      timestampEpoch: epochMs,
      deviceId: deviceId,
      imageHash: imageHash,
    );

    return embedWatermark(imageBytes, payload.toJsonString());
  }

  // ─── LSB Steganography ────────────────────────────────────────────────────

  /// Embeds [payloadString] invisibly into image bytes using LSB steganography.
  ///
  /// Layout:
  ///   Bytes 0..3  → VPIC magic header (4 bytes)
  ///   Bytes 4..7  → uint32 payload byte length (big-endian)
  ///   Bytes 8..N  → UTF-8 payload bytes
  ///
  /// Each byte of the full header+payload is encoded bit-by-bit into the
  /// [AppConstants.lsbBitsPerChannel] least-significant bits of the Red
  /// channel of sequential pixels.
  ///
  /// The image is decoded to PNG (lossless) before embedding to prevent
  /// JPEG quantization from destroying the watermark.
  static Uint8List embedWatermark(Uint8List imageBytes, String payloadString) {
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('embedWatermark: cannot decode image');

    final payloadBytes = utf8.encode(payloadString);
    final magic = AppConstants.watermarkMagic;
    final lengthBytes = _uint32ToBytes(payloadBytes.length);

    // Full byte sequence to embed: magic + length + payload
    final fullData = Uint8List.fromList([...magic, ...lengthBytes, ...payloadBytes]);
    final bits = _bytesToBits(fullData);

    final bitsPerPixel = AppConstants.lsbBitsPerChannel;
    final requiredPixels = (bits.length / bitsPerPixel).ceil();

    if (image.width * image.height < requiredPixels) {
      throw Exception(
          'Image too small to embed watermark. Need $requiredPixels pixels, '
          'have ${image.width * image.height}.');
    }

    // Embed bits into R channel LSBs
    int bitIndex = 0;
    for (int i = 0; i < image.width * image.height && bitIndex < bits.length; i++) {
      final x = i % image.width;
      final y = i ~/ image.width;
      final pixel = image.getPixel(x, y);

      int r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      final a = pixel.a.toInt();

      // Clear the LSBs in R channel, then embed bits
      r = r & ~((1 << bitsPerPixel) - 1); // clear bottom N bits
      for (int b2 = bitsPerPixel - 1; b2 >= 0 && bitIndex < bits.length; b2--) {
        r |= (bits[bitIndex] << b2);
        bitIndex++;
      }

      image.setPixelRgba(x, y, r, g, b, a);
    }

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Extracts a previously embedded watermark payload string from image bytes.
  /// Returns null if no valid VeriPic watermark is found.
  static String? extractWatermark(Uint8List imageBytes) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;

    final bitsPerPixel = AppConstants.lsbBitsPerChannel;
    // We need to read at least the header: 4 (magic) + 4 (length) = 8 bytes = 64 bits
    final headerBytes = 8;
    final headerBitsNeeded = headerBytes * 8;
    final headerPixelsNeeded = (headerBitsNeeded / bitsPerPixel).ceil();

    if (image.width * image.height < headerPixelsNeeded) return null;

    // Read bits from R channel LSBs
    List<int> readBits(int pixelCount) {
      final bits = <int>[];
      for (int i = 0; i < pixelCount; i++) {
        final x = i % image.width;
        final y = i ~/ image.width;
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        for (int b = bitsPerPixel - 1; b >= 0; b--) {
          bits.add((r >> b) & 1);
        }
      }
      return bits;
    }

    // Step 1: Read header
    final headerBits = readBits(headerPixelsNeeded);
    final headerBytes_ = _bitsToBytes(headerBits.take(headerBytes * 8).toList());

    // Validate magic
    for (int i = 0; i < 4; i++) {
      if (headerBytes_[i] != AppConstants.watermarkMagic[i]) return null;
    }

    // Parse length
    final payloadLen = _bytesToUint32(headerBytes_.sublist(4, 8));
    if (payloadLen <= 0 || payloadLen > 100000) return null; // sanity check

    // Step 2: Read full payload
    final totalBytes = headerBytes + payloadLen;
    final totalBits = totalBytes * 8;
    final totalPixels = (totalBits / bitsPerPixel).ceil();

    if (image.width * image.height < totalPixels) return null;

    final allBits = readBits(totalPixels);
    final allBytes = _bitsToBytes(allBits.take(totalBytes * 8).toList());
    final payloadBytes_ = allBytes.sublist(headerBytes, headerBytes + payloadLen);

    try {
      return utf8.decode(payloadBytes_);
    } catch (_) {
      return null;
    }
  }

  // ─── Bit Utilities ────────────────────────────────────────────────────────

  static List<int> _bytesToBits(List<int> bytes) {
    final bits = <int>[];
    for (final byte in bytes) {
      for (int b = 7; b >= 0; b--) {
        bits.add((byte >> b) & 1);
      }
    }
    return bits;
  }

  static List<int> _bitsToBytes(List<int> bits) {
    final bytes = <int>[];
    for (int i = 0; i < bits.length; i += 8) {
      int byte = 0;
      for (int b = 0; b < 8 && i + b < bits.length; b++) {
        byte = (byte << 1) | bits[i + b];
      }
      bytes.add(byte);
    }
    return bytes;
  }

  static List<int> _uint32ToBytes(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }

  static int _bytesToUint32(List<int> bytes) {
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }
}
