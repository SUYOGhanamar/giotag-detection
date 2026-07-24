// lib/screens/verification_screen.dart
// Task C (UI): Multi-tier verification screen with verdict badge display

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../services/verification_service.dart';
import '../services/nvidia_vision_service.dart';
import '../services/security_service.dart';


// ─── Colors (same palette as main.dart) ──────────────────────────────────────
class _C {
  static const bg       = Color(0xFF07090F);
  static const surface  = Color(0xFF0D1117);
  static const card     = Color(0xFF111827);
  static const cardHigh = Color(0xFF161F2E);
  static const border   = Color(0xFF1E2D45);
  static const cyan     = Color(0xFF00D4FF);
  static const blue     = Color(0xFF2563EB);
  static const green    = Color(0xFF10D98A);
  static const amber    = Color(0xFFFBBF24);
  static const red      = Color(0xFFFF4D6A);
  static const purple   = Color(0xFFA78BFA);
  static const t1       = Color(0xFFF1F5F9);
  static const t2       = Color(0xFF94A3B8);
  static const t3       = Color(0xFF475569);
}

// ─── Verification Screen ──────────────────────────────────────────────────────

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen>
    with TickerProviderStateMixin {
  File? _selectedImage;
  Uint8List? _imageBytes; // web-safe image data
  bool _isVerifying = false;
  VerificationReport? _report;
  String _scanStep = '';
  double _scanProgress = 0.0;
  int _currentStep = 0;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  late AnimationController _verdictCtrl;
  late Animation<double> _verdictFade, _verdictScale;

  static const _scanSteps = [
    'Loading image into memory',
    'Detecting VeriPic watermark',
    'Extracting cryptographic payload',
    'Verifying HMAC-SHA256 signature',
    'Checking steganographic integrity',
    'Comparing GPS & timestamp fields',
    'Sending to NVIDIA AI for analysis',
    'Parsing deepfake detection score',
    'Computing final verdict',
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.97, end: 1.03).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _verdictCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _verdictFade =
        CurvedAnimation(parent: _verdictCtrl, curve: Curves.easeIn);
    _verdictScale = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _verdictCtrl, curve: Curves.elasticOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _verdictCtrl.dispose();
    super.dispose();
  }

  // ─── Image Picker ───────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source);
    if (file != null && mounted) {
      final bytes = await file.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        if (!kIsWeb) _selectedImage = File(file.path);
        _report = null;
        _verdictCtrl.reset();
      });
    }
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _C.cardHigh,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: _C.border,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          _SheetTile(Icons.photo_library_rounded, 'Gallery', () {
            Navigator.pop(context);
            _pickImage(ImageSource.gallery);
          }),
          _SheetTile(Icons.camera_alt_rounded, 'Camera', () {
            Navigator.pop(context);
            _pickImage(ImageSource.camera);
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ─── Verification Pipeline ──────────────────────────────────────────────────

  Future<void> _runVerification() async {
    if (_imageBytes == null || _isVerifying) return;
    setState(() {
      _isVerifying = true;
      _report = null;
      _verdictCtrl.reset();
      _currentStep = 0;
      _scanProgress = 0;
    });

    // Animate through scan steps
    for (int i = 0; i < _scanSteps.length; i++) {
      if (!mounted) return;
      setState(() {
        _scanStep = _scanSteps[i];
        _currentStep = i;
        _scanProgress = (i + 1) / _scanSteps.length;
      });
      await Future.delayed(Duration(milliseconds: 300 + Random().nextInt(250)));
    }

    // Run actual verification (bytes already read during pick — works on web & mobile)
    try {
      final bytes = _imageBytes!;
      final report = await VerificationService.verify(bytes);
      if (!mounted) return;
      setState(() {
        _report = report;
        _isVerifying = false;
        _scanProgress = 1.0;
      });
      _verdictCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVerifying = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Verification error: $e'),
        backgroundColor: _C.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.bg,
        elevation: 0,
        title: Row(children: [
          const Icon(Icons.verified_user_rounded,
              color: _C.cyan, size: 20),
          const SizedBox(width: 8),
          Text('Verify',
              style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.w900, color: _C.t1)),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _C.cyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _C.cyan.withOpacity(0.25)),
            ),
            child: Text('3-TIER',
                style: GoogleFonts.sourceCodePro(
                    fontSize: 10,
                    color: _C.cyan,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader('Upload & Verify',
                'Run 3-tier cryptographic + AI deepfake detection'),
            const SizedBox(height: 20),

            // Image drop zone
            if (!_isVerifying) _dropZone() else _scannerUI(),
            const SizedBox(height: 16),

            // Verify button
            if (!_isVerifying && _report == null)
              _GlowButton(
                label: 'Verify Image',
                icon: Icons.security_rounded,
                enabled: _selectedImage != null,
                onTap: _runVerification,
              ),

            // Verdict
            if (_report != null) ...[
              const SizedBox(height: 24),
              _buildVerdict(_report!),
              const SizedBox(height: 20),
              _buildTierCards(_report!),
              const SizedBox(height: 20),
              if (_report!.embeddedPayload != null)
                _buildEmbeddedMetadata(_report!.embeddedPayload!),
              const SizedBox(height: 20),
              _buildNvidiaCard(_report!.nvidiaResult),
              const SizedBox(height: 20),
              // Re-verify button
              _GlowButton(
                label: 'Verify Another Image',
                icon: Icons.refresh_rounded,
                enabled: true,
                onTap: () {
                  setState(() {
                    _selectedImage = null;
                    _report = null;
                    _verdictCtrl.reset();
                  });
                  _showPicker();
                },
              ),
              const SizedBox(height: 32),
            ],

            // Pipeline info (when idle)
            if (!_isVerifying && _report == null) ...[
              const SizedBox(height: 28),
              _SectionHeader('Verification Pipeline',
                  'Three independent layers of analysis'),
              const SizedBox(height: 16),
              _buildPipelineInfo(),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Drop Zone ──────────────────────────────────────────────────────────────

  Widget _dropZone() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Transform.scale(
          scale: _imageBytes == null ? _pulse.value : 1.0, child: child),
      child: GestureDetector(
        onTap: _showPicker,
        child: Container(
          width: double.infinity,
          height: 220,
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _imageBytes != null ? _C.cyan : _C.border,
              width: _imageBytes != null ? 1.5 : 1.0,
            ),
          ),
          child: _imageBytes != null
              ? _imagePreview()
              : _dropHint(),
        ),
      ),
    );
  }

  Widget _imagePreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(17),
      child: Stack(fit: StackFit.expand, children: [
        kIsWeb
            ? Image.memory(_imageBytes!, fit: BoxFit.cover)
            : Image.file(_selectedImage!, fit: BoxFit.cover),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, _C.bg.withOpacity(0.85)],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: _C.cyan.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: _C.cyan.withOpacity(0.4))),
                child: const Icon(Icons.image_rounded,
                    color: _C.cyan, size: 14),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _selectedImage?.path.split('/').last.split('\\').last
                      ?? 'Selected image',
                  style: const TextStyle(
                      fontSize: 12,
                      color: _C.t1,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _SmallChip('Tap to change'),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _dropHint() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _C.cyan.withOpacity(0.07),
            border: Border.all(color: _C.cyan.withOpacity(0.25)),
          ),
          child: const Icon(Icons.cloud_upload_rounded,
              color: _C.cyan, size: 28),
        ),
        const SizedBox(height: 14),
        Text('Drop a photo to verify',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _C.t1)),
        const SizedBox(height: 6),
        const Text('JPEG · PNG · VeriPic Watermarked Images',
            style: TextStyle(color: _C.t3, fontSize: 12)),
      ],
    );
  }

  // ─── Scanner UI ─────────────────────────────────────────────────────────────

  Widget _scannerUI() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _C.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _PulsingDot(),
          const SizedBox(width: 8),
          Text('VERIFYING IN PROGRESS',
              style: GoogleFonts.sourceCodePro(
                  fontSize: 11,
                  color: _C.cyan,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _scanProgress),
          duration: const Duration(milliseconds: 400),
          builder: (_, v, __) => ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 5,
              backgroundColor: _C.border,
              valueColor: const AlwaysStoppedAnimation(_C.cyan),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(_scanProgress * 100).toInt()}% — $_scanStep',
          style:
              GoogleFonts.sourceCodePro(fontSize: 11, color: _C.t2),
        ),
        const SizedBox(height: 20),
        ...List.generate(_scanSteps.length, (i) {
          final done = i < _currentStep;
          final active = i == _currentStep;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 24,
                child: Column(children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? _C.green
                          : active
                              ? _C.cyan.withOpacity(0.15)
                              : _C.border,
                      border: Border.all(
                          color: done
                              ? _C.green
                              : active
                                  ? _C.cyan
                                  : _C.border,
                          width: 1.5),
                    ),
                    child: done
                        ? const Icon(Icons.check_rounded,
                            size: 11, color: Color(0xFF07090F))
                        : active
                            ? Center(child: _PulsingDot(size: 7))
                            : null,
                  ),
                  if (i < _scanSteps.length - 1)
                    Container(
                        width: 1.5,
                        height: 20,
                        color: done
                            ? _C.green.withOpacity(0.4)
                            : _C.border),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _scanSteps[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        active ? FontWeight.w700 : FontWeight.w500,
                    color: done ? _C.t3 : active ? _C.t1 : _C.t3,
                  ),
                ),
              ),
            ]),
          );
        }),
      ]),
    );
  }

  // ─── Verdict Banner ─────────────────────────────────────────────────────────

  Widget _buildVerdict(VerificationReport report) {
    final (color, icon, bgColor) = _verdictStyle(report.verdict);

    return FadeTransition(
      opacity: _verdictFade,
      child: ScaleTransition(
        scale: _verdictScale,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.15),
                  blurRadius: 30,
                  spreadRadius: 4)
            ],
          ),
          child: Column(children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.15),
                border: Border.all(color: color.withOpacity(0.5), width: 2),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              report.verdictLabel,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              report.verdictDescription,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: color.withOpacity(0.85),
                  height: 1.5),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _ScorePill('Score', '${report.authenticityScore}/100', color),
              const SizedBox(width: 10),
              _ScorePill(
                  'Time',
                  '${(report.analysisTimeMs / 1000).toStringAsFixed(1)}s',
                  _C.cyan),
            ]),
          ]),
        ),
      ),
    );
  }

  (Color, IconData, Color) _verdictStyle(VerificationVerdict v) =>
      switch (v) {
        VerificationVerdict.authenticVerified => (
          _C.green,
          Icons.verified_rounded,
          _C.green.withOpacity(0.06)
        ),
        VerificationVerdict.suspicious => (
          _C.amber,
          Icons.warning_amber_rounded,
          _C.amber.withOpacity(0.06)
        ),
        VerificationVerdict.pixelTampered => (
          _C.red,
          Icons.broken_image_rounded,
          _C.red.withOpacity(0.06)
        ),
        VerificationVerdict.metadataTampered => (
          _C.red,
          Icons.dangerous_rounded,
          _C.red.withOpacity(0.06)
        ),
        VerificationVerdict.deepfakeDetected => (
          _C.purple,
          Icons.smart_toy_rounded,
          _C.purple.withOpacity(0.06)
        ),
        VerificationVerdict.noWatermark => (
          _C.t2,
          Icons.no_photography_rounded,
          _C.surface
        ),
      };

  // ─── Tier Cards ─────────────────────────────────────────────────────────────

  Widget _buildTierCards(VerificationReport report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
            'Verification Tiers', 'Independent layer-by-layer analysis'),
        const SizedBox(height: 12),
        _TierCard(
          number: '1',
          title: 'Cryptographic Signature',
          icon: Icons.lock_rounded,
          tierColor: _C.cyan,
          result: report.tier1Crypto,
        ),
        const SizedBox(height: 10),
        _TierCard(
          number: '2',
          title: 'Steganographic Integrity',
          icon: Icons.layers_rounded,
          tierColor: _C.purple,
          result: report.tier2Stego,
        ),
        const SizedBox(height: 10),
        _TierCard(
          number: '3',
          title: 'NVIDIA AI Analysis',
          icon: Icons.psychology_rounded,
          tierColor: _C.green,
          result: report.tier3Nvidia,
        ),
      ],
    );
  }

  // ─── Embedded Metadata ───────────────────────────────────────────────────────

  Widget _buildEmbeddedMetadata(WatermarkPayload payload) {
    final captureTime =
        DateTime.fromMillisecondsSinceEpoch(payload.timestampEpoch);
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              const Icon(Icons.data_object_rounded,
                  color: _C.cyan, size: 16),
              const SizedBox(width: 8),
              Text('Embedded Payload',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _C.t1)),
            ]),
          ),
          const Divider(height: 20, color: _C.border),
          _MetaRow('GPS Latitude',
              '${payload.latitude.toStringAsFixed(6)}°'),
          _MetaRow('GPS Longitude',
              '${payload.longitude.toStringAsFixed(6)}°'),
          _MetaRow('Altitude',
              '${payload.altitude.toStringAsFixed(1)} m'),
          _MetaRow('Timestamp',
              DateFormat('yyyy-MM-dd HH:mm:ss').format(captureTime) + ' UTC'),
          _MetaRow('Device ID', payload.deviceId.substring(0, 16) + '…'),
          _MetaRow('Image Hash', '${payload.imageHash.substring(0, 20)}…'),
          _MetaRow('Signature',
              '${payload.signature.substring(0, 20)}…'),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ─── NVIDIA Card ─────────────────────────────────────────────────────────────

  Widget _buildNvidiaCard(NvidiaAnalysisResult nvidia) {
    final available = nvidia.status != NvidiaAnalysisStatus.unavailable;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: available ? _C.green.withOpacity(0.3) : _C.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _C.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.psychology_rounded,
                color: _C.green, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NVIDIA AI Analysis',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _C.t1)),
                  Text(
                    available ? 'Neva-22B Multimodal' : 'API not configured',
                    style: const TextStyle(fontSize: 11, color: _C.t3),
                  ),
                ]),
          ),
          if (available)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _C.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _C.green.withOpacity(0.3)),
              ),
              child: Text('LIVE',
                  style: GoogleFonts.sourceCodePro(
                      fontSize: 9,
                      color: _C.green,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5)),
            )
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _C.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _C.amber.withOpacity(0.3)),
              ),
              child: Text('OFF',
                  style: GoogleFonts.sourceCodePro(
                      fontSize: 9,
                      color: _C.amber,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5)),
            ),
        ]),
        if (available) ...[
          const SizedBox(height: 16),
          // Synthetic score bar
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Synthetic Score',
                    style: TextStyle(fontSize: 12, color: _C.t2)),
                Text(
                    '${(nvidia.syntheticScore * 100).toInt()}%',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _syntheticColor(nvidia.syntheticScore))),
              ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: nvidia.syntheticScore),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOut,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: _C.border,
                valueColor: AlwaysStoppedAnimation(
                    _syntheticColor(nvidia.syntheticScore)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(nvidia.explanation,
              style: const TextStyle(
                  fontSize: 12, color: _C.t3, height: 1.5)),
        ] else ...[
          const SizedBox(height: 12),
          Text(nvidia.explanation,
              style: const TextStyle(
                  fontSize: 12, color: _C.t3, height: 1.5)),
          const SizedBox(height: 8),
          Text('→ Add your key to .env: NVIDIA_API_KEY=…',
              style: GoogleFonts.sourceCodePro(
                  fontSize: 11, color: _C.cyan)),
        ],
      ]),
    );
  }

  Color _syntheticColor(double score) => score > 0.65
      ? _C.red
      : score > 0.35
          ? _C.amber
          : _C.green;

  // ─── Pipeline Info ───────────────────────────────────────────────────────────

  Widget _buildPipelineInfo() {
    final items = [
      (
        Icons.lock_rounded,
        _C.cyan,
        'Tier 1: Crypto',
        'HMAC-SHA256 signature + SHA-256 pixel hash verification'
      ),
      (
        Icons.layers_rounded,
        _C.purple,
        'Tier 2: Steganography',
        'LSB watermark extraction + GPS/timestamp integrity check'
      ),
      (
        Icons.psychology_rounded,
        _C.green,
        'Tier 3: NVIDIA AI',
        'Neva-22B multimodal deepfake artifact analysis'
      ),
    ];
    return Column(
      children: items
          .map((e) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _C.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _C.border),
                ),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: e.$2.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(e.$1, color: e.$2, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(e.$3,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _C.t1)),
                        const SizedBox(height: 2),
                        Text(e.$4,
                            style: const TextStyle(
                                fontSize: 11, color: _C.t3)),
                      ])),
                ]),
              ))
          .toList(),
    );
  }
}

// ─── Reusable Widgets ─────────────────────────────────────────────────────────

class _TierCard extends StatelessWidget {
  final String number, title;
  final IconData icon;
  final Color tierColor;
  final TierResult result;

  const _TierCard({
    required this.number,
    required this.title,
    required this.icon,
    required this.tierColor,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusIcon, statusLabel) = _statusStyle(result.status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tierColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: tierColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Tier $number: $title',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _C.t1)),
            ]),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withOpacity(0.35)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(statusIcon, color: statusColor, size: 12),
              const SizedBox(width: 4),
              Text(statusLabel,
                  style: TextStyle(
                      fontSize: 10,
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Text(result.title,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: statusColor.withOpacity(0.9))),
        const SizedBox(height: 4),
        Text(result.detail,
            style: const TextStyle(
                fontSize: 12, color: _C.t3, height: 1.4)),
        if (result.confidence > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Text('Confidence: ',
                style: TextStyle(fontSize: 11, color: _C.t3)),
            Text('${(result.confidence * 100).toInt()}%',
                style: TextStyle(
                    fontSize: 11,
                    color: statusColor,
                    fontWeight: FontWeight.w800)),
          ]),
        ],
      ]),
    );
  }

  (Color, IconData, String) _statusStyle(TierStatus s) => switch (s) {
        TierStatus.pass       => (_C.green,  Icons.check_circle_rounded, 'PASS'),
        TierStatus.fail       => (_C.red,    Icons.cancel_rounded,       'FAIL'),
        TierStatus.warning    => (_C.amber,  Icons.warning_rounded,      'WARN'),
        TierStatus.unavailable => (_C.t3,   Icons.circle_outlined,      'N/A'),
        TierStatus.pending    => (_C.cyan,   Icons.hourglass_empty_rounded, 'WAIT'),
      };
}

class _MetaRow extends StatelessWidget {
  final String label, value;
  const _MetaRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: _C.t3)),
            Text(value,
                style: GoogleFonts.sourceCodePro(
                    fontSize: 12,
                    color: _C.t1,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _ScorePill extends StatelessWidget {
  final String label, value;
  final Color color;
  const _ScorePill(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label: ',
              style: const TextStyle(fontSize: 12, color: _C.t3)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w800)),
        ]),
      );
}

class _SectionHeader extends StatelessWidget {
  final String title, sub;
  const _SectionHeader(this.title, this.sub);
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _C.t1,
                  letterSpacing: -0.2)),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(sub,
                style: const TextStyle(fontSize: 12, color: _C.t3)),
          ],
        ],
      );
}

class _GlowButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _GlowButton(
      {required this.label,
      required this.icon,
      required this.enabled,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: enabled ? _C.blue : _C.border,
            borderRadius: BorderRadius.circular(14),
            boxShadow: enabled
                ? [
                    BoxShadow(
                        color: _C.blue.withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 6))
                  ]
                : [],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: enabled ? Colors.white : _C.t3, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: enabled ? Colors.white : _C.t3)),
          ]),
        ),
      );
}

class _SmallChip extends StatelessWidget {
  final String label;
  const _SmallChip(this.label);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: _C.cardHigh,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _C.border)),
        child: Text(label,
            style: const TextStyle(fontSize: 11, color: _C.t3)),
      );
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SheetTile(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: _C.cyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: _C.cyan, size: 20),
        ),
        title: Text(label,
            style: const TextStyle(
                color: _C.t1, fontSize: 14, fontWeight: FontWeight.w600)),
        onTap: onTap,
      );
}

class _PulsingDot extends StatefulWidget {
  final double size;
  const _PulsingDot({this.size = 9});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _a = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (_, __) => Opacity(
          opacity: _a.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: const BoxDecoration(
                color: _C.cyan, shape: BoxShape.circle),
          ),
        ),
      );
}
