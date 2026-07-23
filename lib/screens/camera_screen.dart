// lib/screens/camera_screen.dart
// Task B (UI): Full-screen camera with live GPS/UTC HUD and cryptographic signing

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/camera_service.dart';
import '../services/security_service.dart';

// ─── Camera Screen ────────────────────────────────────────────────────────────

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin {
  final CameraService _cameraService = CameraService();

  // State
  bool _permissionsGranted = false;
  bool _initializing = true;
  String? _errorMessage;
  bool _isSigning = false;
  bool _isCapturing = false;
  String _signingStep = '';
  CapturedFrame? _lastCapture;
  String? _savedPath;

  // Live HUD data
  Position? _livePosition;
  DateTime _utcTime = DateTime.now().toUtc();
  StreamSubscription<Position>? _gpsSub;
  Timer? _clockTimer;
  double _gpsAccuracy = 0;

  // Animations
  late AnimationController _shutterCtrl;
  late Animation<double> _shutterAnim;
  late AnimationController _hudPulseCtrl;
  late Animation<double> _hudPulse;
  late AnimationController _scanCtrl;
  late Animation<double> _scanAnim;

  @override
  void initState() {
    super.initState();

    _shutterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _shutterAnim = Tween<double>(begin: 1.0, end: 0.85).animate(
        CurvedAnimation(parent: _shutterCtrl, curve: Curves.easeInOut));

    _hudPulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _hudPulse = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _hudPulseCtrl, curve: Curves.easeInOut));

    _scanCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
    _scanAnim = Tween<double>(begin: 0.0, end: 1.0).animate(_scanCtrl);

    _requestPermissionsAndInit();
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _clockTimer?.cancel();
    _shutterCtrl.dispose();
    _hudPulseCtrl.dispose();
    _scanCtrl.dispose();
    _cameraService.dispose();
    super.dispose();
  }

  // ─── Permissions & Init ─────────────────────────────────────────────────────

  Future<void> _requestPermissionsAndInit() async {
    final cameraStatus = await Permission.camera.request();
    final locationStatus = await Permission.location.request();

    if (!cameraStatus.isGranted || !locationStatus.isGranted) {
      if (mounted) {
        setState(() {
          _permissionsGranted = false;
          _initializing = false;
          _errorMessage = !cameraStatus.isGranted
              ? 'Camera permission required to use VeriPic.'
              : 'Location permission required for geotagging.';
        });
      }
      return;
    }

    setState(() => _permissionsGranted = true);
    await _initCamera();
    _startGpsStream();
    _startClock();
  }

  Future<void> _initCamera() async {
    try {
      await _cameraService.initialize();
      if (mounted) setState(() => _initializing = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _errorMessage = 'Camera init failed: $e';
        });
      }
    }
  }

  void _startGpsStream() {
    _gpsSub = _cameraService.liveGpsStream.listen((pos) {
      if (mounted) {
        setState(() {
          _livePosition = pos;
          _gpsAccuracy = pos.accuracy;
        });
      }
    }, onError: (_) {});
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _utcTime = DateTime.now().toUtc());
    });
  }

  // ─── Capture & Sign ─────────────────────────────────────────────────────────

  Future<void> _onCapture() async {
    if (_isCapturing || _isSigning) return;

    HapticFeedback.heavyImpact();

    // Shutter animation
    _shutterCtrl.forward().then((_) => _shutterCtrl.reverse());

    setState(() => _isCapturing = true);

    try {
      // Capture photo + GPS simultaneously
      final frame = await _cameraService.capturePhoto();
      if (!mounted) return;

      setState(() {
        _isCapturing = false;
        _isSigning = true;
        _lastCapture = frame;
        _signingStep = 'Computing SHA-256 image hash…';
      });

      // Step 1: Hash
      await Future.delayed(const Duration(milliseconds: 100));

      setState(() => _signingStep = 'Generating HMAC-SHA256 signature…');
      final signedBytes = await SecurityService.signAndEmbed(
        frame.imageBytes,
        frame.gpsPosition,
        frame.capturedAt,
      );

      setState(() => _signingStep = 'Embedding steganographic watermark…');
      await Future.delayed(const Duration(milliseconds: 300));

      // Save watermarked image to disk (overwrite original)
      final file = File(frame.filePath.replaceAll('.jpg', '_veripic.png'));
      await file.writeAsBytes(signedBytes);

      setState(() => _signingStep = 'Finalising secure payload…');
      await Future.delayed(const Duration(milliseconds: 200));

      setState(() {
        _isSigning = false;
        _savedPath = file.path;
      });

      HapticFeedback.mediumImpact();
      _showSuccessDialog(frame, file.path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _isSigning = false;
        });
        _showError('Capture failed: $e');
      }
    }
  }

  // ─── UI Helpers ─────────────────────────────────────────────────────────────

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFFFF4D6A),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSuccessDialog(CapturedFrame frame, String path) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _CaptureSuccessDialog(frame: frame, savedPath: path),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_permissionsGranted || _errorMessage != null) {
      return _buildPermissionError();
    }
    if (_initializing) {
      return _buildLoading();
    }
    if (!_cameraService.isInitialized) {
      return _buildLoading();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ─────────────────────────────────────────────
          _CameraViewfinder(controller: _cameraService.controller!),

          // ── Scanning line overlay ──────────────────────────────────────
          if (!_isSigning && !_isCapturing)
            AnimatedBuilder(
              animation: _scanAnim,
              builder: (_, __) => _ScanLineOverlay(progress: _scanAnim.value),
            ),

          // ── Corner guides ──────────────────────────────────────────────
          const _CornerGuides(),

          // ── Top HUD ───────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _TopHUD(
                utcTime: _utcTime,
                position: _livePosition,
                gpsAccuracy: _gpsAccuracy,
                hudPulse: _hudPulse,
              ),
            ),
          ),

          // ── Signing overlay ────────────────────────────────────────────
          if (_isSigning) _SigningOverlay(step: _signingStep),

          // ── Bottom controls ────────────────────────────────────────────
          if (!_isSigning)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: _BottomControls(
                  onCapture: _onCapture,
                  isCapturing: _isCapturing,
                  shutterAnim: _shutterAnim,
                  position: _livePosition,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoading() => Scaffold(
        backgroundColor: const Color(0xFF07090F),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  color: Color(0xFF00D4FF),
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Initializing VeriPic Camera…',
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF94A3B8), fontSize: 14),
              ),
            ],
          ),
        ),
      );

  Widget _buildPermissionError() => Scaffold(
        backgroundColor: const Color(0xFF07090F),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.camera_alt_outlined,
                    size: 64, color: Color(0xFF475569)),
                const SizedBox(height: 24),
                Text(
                  _errorMessage ?? 'Permission required',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFFF1F5F9),
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Grant Camera and Location permissions to use VeriPic.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF475569), fontSize: 13),
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: () => openAppSettings(),
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('Open Settings'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ─── Camera Viewfinder ─────────────────────────────────────────────────────────

class _CameraViewfinder extends StatelessWidget {
  final CameraController controller;
  const _CameraViewfinder({required this.controller});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final deviceRatio = size.width / size.height;
        final previewRatio = controller.value.aspectRatio;
        final scale = deviceRatio < previewRatio
            ? previewRatio / deviceRatio
            : deviceRatio / previewRatio;
        return Transform.scale(
          scale: scale,
          child: Center(child: CameraPreview(controller)),
        );
      },
    );
  }
}

// ─── Scan Line Overlay ─────────────────────────────────────────────────────────

class _ScanLineOverlay extends StatelessWidget {
  final double progress;
  const _ScanLineOverlay({required this.progress});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final y = (progress * h).clamp(0.0, h - 2.0);
    return CustomPaint(
      painter: _ScanLinePainter(y: y),
    );
  }
}

class _ScanLinePainter extends CustomPainter {
  final double y;
  _ScanLinePainter({required this.y});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF00D4FF).withOpacity(0.6),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, y - 1, size.width, 2));
    canvas.drawRect(Rect.fromLTWH(0, y - 1, size.width, 2), paint);
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => old.y != y;
}

// ─── Corner Guides ─────────────────────────────────────────────────────────────

class _CornerGuides extends StatelessWidget {
  const _CornerGuides();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CornerPainter());
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00D4FF).withOpacity(0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    const margin = 40.0;
    const len = 24.0;

    // Top-left
    canvas.drawPath(
        Path()
          ..moveTo(margin, margin + len)
          ..lineTo(margin, margin)
          ..lineTo(margin + len, margin),
        paint);
    // Top-right
    canvas.drawPath(
        Path()
          ..moveTo(size.width - margin - len, margin)
          ..lineTo(size.width - margin, margin)
          ..lineTo(size.width - margin, margin + len),
        paint);
    // Bottom-left
    canvas.drawPath(
        Path()
          ..moveTo(margin, size.height - margin - len)
          ..lineTo(margin, size.height - margin)
          ..lineTo(margin + len, size.height - margin),
        paint);
    // Bottom-right
    canvas.drawPath(
        Path()
          ..moveTo(size.width - margin - len, size.height - margin)
          ..lineTo(size.width - margin, size.height - margin)
          ..lineTo(size.width - margin, size.height - margin - len),
        paint);
  }

  @override
  bool shouldRepaint(_CornerPainter _) => false;
}

// ─── Top HUD ──────────────────────────────────────────────────────────────────

class _TopHUD extends StatelessWidget {
  final DateTime utcTime;
  final Position? position;
  final double gpsAccuracy;
  final Animation<double> hudPulse;

  const _TopHUD({
    required this.utcTime,
    required this.position,
    required this.gpsAccuracy,
    required this.hudPulse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            children: [
              AnimatedBuilder(
                animation: hudPulse,
                builder: (_, __) => Opacity(
                  opacity: hudPulse.value,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10D98A),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'VERIPIC SECURE CAPTURE',
                style: GoogleFonts.sourceCodePro(
                  fontSize: 9,
                  letterSpacing: 2.5,
                  color: const Color(0xFF00D4FF),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10D98A).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFF10D98A).withOpacity(0.4)),
                ),
                child: Text(
                  'HMAC-SHA256',
                  style: GoogleFonts.sourceCodePro(
                    fontSize: 8,
                    color: const Color(0xFF10D98A),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // UTC Clock
          Row(
            children: [
              const Icon(Icons.access_time_rounded,
                  color: Color(0xFF94A3B8), size: 13),
              const SizedBox(width: 6),
              Text(
                'UTC ${DateFormat('yyyy-MM-dd  HH:mm:ss').format(utcTime)}',
                style: GoogleFonts.sourceCodePro(
                  fontSize: 13,
                  color: const Color(0xFFF1F5F9),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // GPS Row
          if (position != null) ...[
            Row(
              children: [
                const Icon(Icons.location_on_rounded,
                    color: Color(0xFF00D4FF), size: 13),
                const SizedBox(width: 6),
                Text(
                  '${position!.latitude.toStringAsFixed(6)}°  '
                  '${position!.longitude.toStringAsFixed(6)}°',
                  style: GoogleFonts.sourceCodePro(
                    fontSize: 13,
                    color: const Color(0xFFF1F5F9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '±${gpsAccuracy.toStringAsFixed(0)}m',
                  style: GoogleFonts.sourceCodePro(
                    fontSize: 11,
                    color: gpsAccuracy < 20
                        ? const Color(0xFF10D98A)
                        : const Color(0xFFFBBF24),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.height_rounded,
                    color: Color(0xFF94A3B8), size: 13),
                const SizedBox(width: 6),
                Text(
                  'Alt: ${position!.altitude.toStringAsFixed(1)} m',
                  style: GoogleFonts.sourceCodePro(
                      fontSize: 11, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    color: Color(0xFF00D4FF),
                    strokeWidth: 1.5,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Acquiring GPS signal…',
                  style: GoogleFonts.sourceCodePro(
                      fontSize: 11, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Bottom Controls ──────────────────────────────────────────────────────────

class _BottomControls extends StatelessWidget {
  final VoidCallback onCapture;
  final bool isCapturing;
  final Animation<double> shutterAnim;
  final Position? position;

  const _BottomControls({
    required this.onCapture,
    required this.isCapturing,
    required this.shutterAnim,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.8), Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // GPS lock indicator
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'GPS LOCK',
                  style: GoogleFonts.sourceCodePro(
                      fontSize: 9,
                      color: const Color(0xFF475569),
                      letterSpacing: 2),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  ...List.generate(
                    5,
                    (i) => Container(
                      width: 4,
                      height: 8 + (i * 3.0),
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        color: position != null && i < 4
                            ? const Color(0xFF00D4FF)
                            : const Color(0xFF1E2D45),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),

          // Shutter button
          AnimatedBuilder(
            animation: shutterAnim,
            builder: (_, child) => Transform.scale(
              scale: shutterAnim.value,
              child: child,
            ),
            child: GestureDetector(
              onTap: isCapturing ? null : onCapture,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: const Color(0xFF00D4FF), width: 3),
                  color: Colors.white.withOpacity(isCapturing ? 0.6 : 0.95),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D4FF).withOpacity(0.4),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: isCapturing
                    ? const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: Color(0xFF00D4FF),
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : const Icon(Icons.camera_alt_rounded,
                        color: Color(0xFF07090F), size: 32),
              ),
            ),
          ),

          // Crypto badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CRYPTO',
                  style: GoogleFonts.sourceCodePro(
                      fontSize: 9,
                      color: const Color(0xFF475569),
                      letterSpacing: 2),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10D98A).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFF10D98A).withOpacity(0.4)),
                  ),
                  child: Text(
                    'ACTIVE',
                    style: GoogleFonts.sourceCodePro(
                        fontSize: 9,
                        color: const Color(0xFF10D98A),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Signing Overlay ──────────────────────────────────────────────────────────

class _SigningOverlay extends StatelessWidget {
  final String step;
  const _SigningOverlay({required this.step});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(40),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00D4FF).withOpacity(0.1),
                blurRadius: 40,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00D4FF).withOpacity(0.1),
                  border: Border.all(
                      color: const Color(0xFF00D4FF).withOpacity(0.4)),
                ),
                child: const Icon(Icons.lock_rounded,
                    color: Color(0xFF00D4FF), size: 30),
              ),
              const SizedBox(height: 20),
              Text(
                'SIGNING IMAGE',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFF1F5F9),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                step,
                textAlign: TextAlign.center,
                style: GoogleFonts.sourceCodePro(
                    fontSize: 12, color: const Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 24),
              const LinearProgressIndicator(
                backgroundColor: Color(0xFF1E2D45),
                valueColor: AlwaysStoppedAnimation(Color(0xFF00D4FF)),
              ),
              const SizedBox(height: 16),
              Text(
                'Embedding cryptographic watermark into pixel data…',
                textAlign: TextAlign.center,
                style: GoogleFonts.sourceCodePro(
                    fontSize: 10,
                    color: const Color(0xFF475569),
                    letterSpacing: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Capture Success Dialog ───────────────────────────────────────────────────

class _CaptureSuccessDialog extends StatelessWidget {
  final CapturedFrame frame;
  final String savedPath;

  const _CaptureSuccessDialog({
    required this.frame,
    required this.savedPath,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Success icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10D98A).withOpacity(0.1),
                border: Border.all(
                    color: const Color(0xFF10D98A).withOpacity(0.4), width: 2),
              ),
              child: const Icon(Icons.verified_rounded,
                  color: Color(0xFF10D98A), size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              'Photo Signed & Secured',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: const Color(0xFFF1F5F9),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cryptographic watermark embedded successfully.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 20),

            // Metadata summary
            _InfoRow('Latitude',
                '${frame.gpsPosition.latitude.toStringAsFixed(6)}°'),
            _InfoRow('Longitude',
                '${frame.gpsPosition.longitude.toStringAsFixed(6)}°'),
            _InfoRow('Altitude',
                '${frame.gpsPosition.altitude.toStringAsFixed(1)} m'),
            _InfoRow('GPS Accuracy',
                '±${frame.gpsPosition.accuracy.toStringAsFixed(0)} m'),
            _InfoRow(
                'Timestamp', DateFormat('yyyy-MM-dd HH:mm:ss').format(frame.capturedAt) + ' UTC'),
            _InfoRow('Signature', 'HMAC-SHA256'),
            _InfoRow('Watermark', 'LSB Steganography'),

            const SizedBox(height: 20),

            // Badges
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _Badge('✓ GPS Embedded', const Color(0xFF00D4FF)),
                _Badge('✓ Signed', const Color(0xFF10D98A)),
                _Badge('✓ Watermarked', const Color(0xFFA78BFA)),
              ],
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10D98A),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'Done',
                  style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
            Text(
              value,
              style: GoogleFonts.sourceCodePro(
                  fontSize: 12,
                  color: const Color(0xFFF1F5F9),
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w700)),
      );
}
