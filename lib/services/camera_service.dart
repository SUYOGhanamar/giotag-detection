// lib/services/camera_service.dart
// Task A: Camera & Metadata Capture Pipeline
// Handles camera initialization, live viewfinder, GPS capture, and photo taking.

import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';

/// Represents a captured photo with its associated metadata.
class CapturedFrame {
  final Uint8List imageBytes;
  final String filePath;
  final Position gpsPosition;
  final DateTime capturedAt;

  const CapturedFrame({
    required this.imageBytes,
    required this.filePath,
    required this.gpsPosition,
    required this.capturedAt,
  });

  String get latFormatted =>
      '${gpsPosition.latitude.toStringAsFixed(6)}°';
  String get lngFormatted =>
      '${gpsPosition.longitude.toStringAsFixed(6)}°';
  String get altFormatted =>
      '${gpsPosition.altitude.toStringAsFixed(1)} m';
  String get accuracyFormatted =>
      '±${gpsPosition.accuracy.toStringAsFixed(0)} m';
}

/// Camera service managing the full capture lifecycle.
class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initialized = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _initialized;

  // ─── Initialization ────────────────────────────────────────────────────────

  /// Discovers available cameras and initializes the rear-facing camera
  /// at the highest available resolution.
  Future<void> initialize() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      throw Exception('No cameras available on this device.');
    }

    // Prefer rear camera; fall back to first available
    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.ultraHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();
    _initialized = true;
  }

  // ─── GPS ──────────────────────────────────────────────────────────────────

  /// Requests location permission and returns current high-accuracy GPS position.
  Future<Position> _fetchGpsPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Location permission permanently denied. Open Settings to enable.');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
      timeLimit: const Duration(seconds: 15),
    );
  }

  /// Streams live GPS positions for the HUD overlay.
  Stream<Position> get liveGpsStream => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      );

  // ─── Capture ──────────────────────────────────────────────────────────────

  /// Captures a photo and simultaneously records the GPS position and UTC timestamp.
  /// Returns a [CapturedFrame] with all metadata attached.
  Future<CapturedFrame> capturePhoto() async {
    if (_controller == null || !_initialized) {
      throw Exception('Camera not initialized. Call initialize() first.');
    }

    // Capture GPS and image in parallel for minimal timestamp skew
    final captureTime = DateTime.now().toUtc();
    final results = await Future.wait([
      _fetchGpsPosition(),
      _controller!.takePicture(),
    ]);

    final position = results[0] as Position;
    final xFile = results[1] as XFile;
    final imageBytes = await File(xFile.path).readAsBytes();

    return CapturedFrame(
      imageBytes: imageBytes,
      filePath: xFile.path,
      gpsPosition: position,
      capturedAt: captureTime,
    );
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
    _initialized = false;
  }
}
