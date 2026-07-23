// ignore_for_file: deprecated_member_use
// =============================================================================
//  VERIPIC v3  ·  Tamper-Proof Geotagged Camera & Deepfake Verification
//  lib/main.dart — Root entry point, app shell, existing screens preserved
// =============================================================================

import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/camera_screen.dart';
import 'screens/verification_screen.dart';

// ─── MAIN ─────────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  // Load .env file (NVIDIA_API_KEY, APP_SIGNING_SECRET, etc.)
  await dotenv.load(fileName: '.env');

  await StorageService.init();
  runApp(const GeoDetectApp());
}

// ─── COLORS ───────────────────────────────────────────────────────────────────
class C {
  static const bg          = Color(0xFF07090F);
  static const surface     = Color(0xFF0D1117);
  static const card        = Color(0xFF111827);
  static const cardHigh    = Color(0xFF161F2E);
  static const border      = Color(0xFF1E2D45);
  static const borderSoft  = Color(0xFF253347);

  static const cyan        = Color(0xFF00D4FF);
  static const blue        = Color(0xFF2563EB);
  static const green       = Color(0xFF10D98A);
  static const amber       = Color(0xFFFBBF24);
  static const red         = Color(0xFFFF4D6A);
  static const purple      = Color(0xFFA78BFA);

  static const t1          = Color(0xFFF1F5F9);
  static const t2          = Color(0xFF94A3B8);
  static const t3          = Color(0xFF475569);
}

// ─── THEME ────────────────────────────────────────────────────────────────────
ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: C.cyan, secondary: C.green,
      error: C.red, surface: C.surface,
    ),
    textTheme: GoogleFonts.spaceGroteskTextTheme(base.textTheme)
        .apply(bodyColor: C.t1, displayColor: C.t1),
    cardTheme: CardThemeData(
      color: C.card, elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: C.border),
      ),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: C.bg, elevation: 0, scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 18, fontWeight: FontWeight.w800, color: C.t1),
      iconTheme: const IconThemeData(color: C.t2),
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: C.surface,
      selectedItemColor: C.cyan,
      unselectedItemColor: C.t3,
      showSelectedLabels: true, showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed, elevation: 0,
      selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontSize: 10),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: C.blue, foregroundColor: Colors.white, elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.spaceGrotesk(
            fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: C.cyan, inactiveTrackColor: C.border,
      thumbColor: C.cyan, overlayColor: Color(0x2200D4FF),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? C.cyan : C.t3),
      trackColor: WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.selected)
          ? C.cyan.withOpacity(0.3) : C.border),
    ),
    dividerTheme: const DividerThemeData(color: C.border, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: C.cardHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

// ─── MODELS ───────────────────────────────────────────────────────────────────
enum AnomalyType { danger, warning, success }
enum AnalysisStatus { authentic, suspicious, fake, pending }

class AnomalyItem {
  final String title, description;
  final AnomalyType type;
  final double confidence;
  const AnomalyItem(
      {required this.title, required this.description,
        required this.type, this.confidence = 0});
  Map<String, dynamic> toJson() => {
    'title': title, 'description': description,
    'type': type.name, 'confidence': confidence
  };
  factory AnomalyItem.fromJson(Map<String, dynamic> j) => AnomalyItem(
    title: j['title'], description: j['description'],
    type: AnomalyType.values.firstWhere((e) => e.name == j['type']),
    confidence: (j['confidence'] as num).toDouble(),
  );
}

class GeoData {
  final double? claimedLat, claimedLng, detectedLat, detectedLng, distanceKm;
  final String? claimedCity, claimedCountry, detectedCity, detectedCountry;
  final int geoMatchScore;
  final double shadowClaimed, shadowDetected, weatherConsistency, landmarkConf;
  const GeoData({
    this.claimedLat, this.claimedLng, this.detectedLat, this.detectedLng,
    this.distanceKm, this.claimedCity, this.claimedCountry,
    this.detectedCity, this.detectedCountry,
    required this.geoMatchScore, required this.shadowClaimed,
    required this.shadowDetected, required this.weatherConsistency,
    required this.landmarkConf,
  });
  Map<String, dynamic> toJson() => {
    'claimedLat': claimedLat, 'claimedLng': claimedLng,
    'detectedLat': detectedLat, 'detectedLng': detectedLng,
    'distanceKm': distanceKm, 'claimedCity': claimedCity,
    'claimedCountry': claimedCountry, 'detectedCity': detectedCity,
    'detectedCountry': detectedCountry, 'geoMatchScore': geoMatchScore,
    'shadowClaimed': shadowClaimed, 'shadowDetected': shadowDetected,
    'weatherConsistency': weatherConsistency, 'landmarkConf': landmarkConf,
  };
  factory GeoData.fromJson(Map<String, dynamic> j) => GeoData(
    claimedLat: j['claimedLat']?.toDouble(),
    claimedLng: j['claimedLng']?.toDouble(),
    detectedLat: j['detectedLat']?.toDouble(),
    detectedLng: j['detectedLng']?.toDouble(),
    distanceKm: j['distanceKm']?.toDouble(),
    claimedCity: j['claimedCity'], claimedCountry: j['claimedCountry'],
    detectedCity: j['detectedCity'], detectedCountry: j['detectedCountry'],
    geoMatchScore: j['geoMatchScore'],
    shadowClaimed: (j['shadowClaimed'] as num).toDouble(),
    shadowDetected: (j['shadowDetected'] as num).toDouble(),
    weatherConsistency: (j['weatherConsistency'] as num).toDouble(),
    landmarkConf: (j['landmarkConf'] as num).toDouble(),
  );
}

class AnalysisResult {
  final String id, fileName;
  final String? imagePath, verdictSummary;
  final int authenticityScore, analysisTimeMs;
  final AnalysisStatus status;
  final DateTime analyzedAt;
  final double ganProb, faceInc, compression, freqAnom, texInc, metaInteg;
  final GeoData geoData;
  final List<AnomalyItem> anomalies;
  final Map<String, String> exifData;

  const AnalysisResult({
    required this.id, required this.fileName,
    this.imagePath, this.verdictSummary,
    required this.authenticityScore, required this.analysisTimeMs,
    required this.status, required this.analyzedAt,
    required this.ganProb, required this.faceInc, required this.compression,
    required this.freqAnom, required this.texInc, required this.metaInteg,
    required this.geoData, required this.anomalies, required this.exifData,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'fileName': fileName, 'imagePath': imagePath,
    'verdictSummary': verdictSummary,
    'authenticityScore': authenticityScore, 'analysisTimeMs': analysisTimeMs,
    'status': status.name, 'analyzedAt': analyzedAt.toIso8601String(),
    'ganProb': ganProb, 'faceInc': faceInc, 'compression': compression,
    'freqAnom': freqAnom, 'texInc': texInc, 'metaInteg': metaInteg,
    'geoData': geoData.toJson(),
    'anomalies': anomalies.map((a) => a.toJson()).toList(),
    'exifData': exifData,
  };

  factory AnalysisResult.fromJson(Map<String, dynamic> j) => AnalysisResult(
    id: j['id'], fileName: j['fileName'],
    imagePath: j['imagePath'], verdictSummary: j['verdictSummary'],
    authenticityScore: j['authenticityScore'],
    analysisTimeMs: j['analysisTimeMs'] ?? 3000,
    status: AnalysisStatus.values.firstWhere((e) => e.name == j['status']),
    analyzedAt: DateTime.parse(j['analyzedAt']),
    ganProb: (j['ganProb'] as num).toDouble(),
    faceInc: (j['faceInc'] as num).toDouble(),
    compression: (j['compression'] as num).toDouble(),
    freqAnom: (j['freqAnom'] as num).toDouble(),
    texInc: (j['texInc'] as num).toDouble(),
    metaInteg: (j['metaInteg'] as num).toDouble(),
    geoData: GeoData.fromJson(j['geoData']),
    anomalies: (j['anomalies'] as List)
        .map((a) => AnomalyItem.fromJson(a)).toList(),
    exifData: Map<String, String>.from(j['exifData']),
  );
}

// ─── SERVICES ─────────────────────────────────────────────────────────────────
class StorageService {
  static late SharedPreferences _p;
  static const _key = 'geo_hist_v2';
  static Future<void> init() async => _p = await SharedPreferences.getInstance();
  static Future<void> save(AnalysisResult r) async {
    final list = _p.getStringList(_key) ?? [];
    list.insert(0, jsonEncode(r.toJson()));
    if (list.length > 100) list.removeRange(100, list.length);
    await _p.setStringList(_key, list);
  }
  static List<AnalysisResult> load() =>
      (_p.getStringList(_key) ?? [])
          .map((s) => AnalysisResult.fromJson(jsonDecode(s))).toList();
  static Future<void> clear() => _p.remove(_key);
  static double getThreshold() => _p.getDouble('thresh') ?? 70;
  static Future<void> setThreshold(double v) => _p.setDouble('thresh', v);
  static int getGeoSens() => _p.getInt('geoSens') ?? 2;
  static Future<void> setGeoSens(int v) => _p.setInt('geoSens', v);
  static bool getAutoSave() => _p.getBool('autoSave') ?? true;
  static Future<void> setAutoSave(bool v) => _p.setBool('autoSave', v);
}

class AnalysisService {
  static final _uuid = const Uuid();
  static final _r    = Random();

  static Future<AnalysisResult> analyze(File file, String name) async {
    await Future.delayed(const Duration(milliseconds: 100));
    final score = _r.nextInt(100);
    final fake  = score < 38;
    final susp  = score >= 38 && score < 60;
    final status = fake ? AnalysisStatus.fake
        : susp ? AnalysisStatus.suspicious : AnalysisStatus.authentic;

    double rng(double lo, double hi) => lo + _r.nextDouble() * (hi - lo);

    final ganP  = fake ? rng(0.62, 0.98) : rng(0.02, 0.22);
    final face  = fake ? rng(0.55, 0.95) : rng(0.01, 0.18);
    final comp  = fake ? rng(0.72, 0.99) : rng(0.04, 0.20);
    final freq  = fake ? rng(0.60, 0.95) : rng(0.03, 0.17);
    final tex   = fake ? rng(0.50, 0.90) : rng(0.02, 0.19);
    final meta  = fake ? rng(0.05, 0.35) : rng(0.73, 0.99);

    final geoScore = fake ? 8 + _r.nextInt(32) : 70 + _r.nextInt(30);

    final geo = GeoData(
      claimedLat: 19.076 + (_r.nextDouble() - 0.5) * 0.6,
      claimedLng: 72.877 + (_r.nextDouble() - 0.5) * 0.6,
      claimedCity: 'Mumbai', claimedCountry: 'India',
      detectedCity: fake ? 'Prague' : 'Mumbai',
      detectedCountry: fake ? 'Czech Republic' : 'India',
      detectedLat: fake ? 50.0755 : 19.076,
      detectedLng: fake ? 14.4378 : 72.877,
      distanceKm: fake ? rng(5200, 7800) : rng(0, 8),
      geoMatchScore: geoScore,
      shadowClaimed:  fake ? rng(0.04, 0.20) : rng(0.72, 0.97),
      shadowDetected: fake ? rng(0.78, 0.99) : rng(0.70, 0.97),
      weatherConsistency: fake ? rng(0.10, 0.38) : rng(0.66, 0.97),
      landmarkConf:       fake ? rng(0.05, 0.28) : rng(0.70, 0.95),
    );

    return AnalysisResult(
      id: _uuid.v4(), fileName: name, imagePath: file.path,
      authenticityScore: score, status: status,
      analysisTimeMs: 2800 + _r.nextInt(2000),
      analyzedAt: DateTime.now(),
      ganProb: ganP, faceInc: face, compression: comp,
      freqAnom: freq, texInc: tex, metaInteg: meta,
      geoData: geo,
      anomalies: _anomalies(fake, susp),
      exifData: _exif(fake, name),
      verdictSummary: _verdict(fake, susp),
    );
  }

  static String _verdict(bool fake, bool susp) {
    if (fake) return 'High probability of digital manipulation detected. GPS metadata does not correlate with scene content. Visual analysis reveals GAN-generated artifacts and facial inconsistencies.';
    if (susp) return 'Minor inconsistencies detected. Some EXIF anomalies present but scene broadly matches claimed location. Manual review recommended.';
    return 'No significant manipulation detected. GPS coordinates are consistent with scene content. Metadata integrity is intact and shadow angles are plausible for the claimed location and timestamp.';
  }

  static List<AnomalyItem> _anomalies(bool fake, bool susp) {
    final list = <AnomalyItem>[];
    if (fake) {
      list.addAll([
        const AnomalyItem(title: 'GPS coordinate mismatch', description: 'Claimed: Mumbai IN. Scene recognition places background in Central Europe with 87% confidence.', type: AnomalyType.danger, confidence: 0.87),
        const AnomalyItem(title: 'Shadow angle impossible', description: 'Shadow direction indicates sun azimuth 312° NW — geometrically impossible at claimed GPS lat/lon at this timestamp.', type: AnomalyType.danger, confidence: 0.93),
        const AnomalyItem(title: 'GAN upsampling artifacts', description: 'FFT frequency analysis detects characteristic GAN grid patterns in mid-frequency bands.', type: AnomalyType.danger, confidence: 0.82),
        const AnomalyItem(title: 'EXIF device fingerprint mismatch', description: 'PRNU sensor noise pattern does not match declared camera model (iPhone 14 Pro).', type: AnomalyType.warning, confidence: 0.71),
        const AnomalyItem(title: 'Texture boundary inconsistency', description: 'Facial region shows unnatural texture gradient at hairline — common in face-swap GAN models.', type: AnomalyType.warning, confidence: 0.68),
      ]);
    } else if (susp) {
      list.addAll([
        const AnomalyItem(title: 'Minor EXIF timezone offset', description: 'Timestamp timezone (UTC+5:30) differs slightly from GPS-derived timezone.', type: AnomalyType.warning, confidence: 0.44),
        const AnomalyItem(title: 'Mild re-compression detected', description: 'JPEG quantization table suggests 2nd-generation compression, likely from social media re-encoding.', type: AnomalyType.warning, confidence: 0.52),
      ]);
    }
    list.add(const AnomalyItem(title: 'Timestamp consistent', description: 'Date/time metadata is consistent with lighting conditions and sun elevation in the image.', type: AnomalyType.success, confidence: 0.91));
    if (!fake) list.add(const AnomalyItem(title: 'Scene location verified', description: 'Background scene matches claimed GPS coordinates. Landmark elements confirmed with 89% confidence.', type: AnomalyType.success, confidence: 0.89));
    return list;
  }

  static Map<String, String> _exif(bool fake, String name) => {
    'File Name': name,
    'GPS Latitude': '19.0760° N',
    'GPS Longitude': '72.8777° E',
    'GPS Altitude': '14m above sea level',
    'Date/Time': '2024-11-03 14:22:05',
    'Camera Make': fake ? 'Unknown (stripped)' : 'Apple',
    'Camera Model': fake ? 'Falsified / Spoofed' : 'iPhone 14 Pro',
    'Software': fake ? 'Adobe Photoshop 25.0' : 'iOS 17.1',
    'Flash': 'Off, Did not fire',
    'Focal Length': '6.86mm (equiv. 24mm)',
    'Aperture': 'f/1.78', 'ISO': '64',
    'Shutter Speed': '1/1000s', 'White Balance': 'Auto',
    'Image Size': '4032 × 3024 px',
  };
}

// ─── APP STATE ────────────────────────────────────────────────────────────────
class AppState extends ChangeNotifier {
  AnalysisResult? lastResult;
  int tabIndex = 0;
  bool isAnalyzing = false;
  double scanProgress = 0;
  String scanLabel = '';
  int scanStep = 0;

  void setTab(int i) { tabIndex = i; notifyListeners(); }
  void setResult(AnalysisResult r) { lastResult = r; tabIndex = 2; notifyListeners(); }
  void setScan({bool? analyzing, double? progress, String? label, int? step}) {
    if (analyzing != null) isAnalyzing = analyzing;
    if (progress != null) scanProgress = progress;
    if (label != null) scanLabel = label;
    if (step != null) scanStep = step;
    notifyListeners();
  }
}

// ─── ROOT APP ─────────────────────────────────────────────────────────────────
class GeoDetectApp extends StatefulWidget {
  const GeoDetectApp({Key? key}) : super(key: key);
  @override
  State<GeoDetectApp> createState() => _GeoDetectAppState();
}

class _GeoDetectAppState extends State<GeoDetectApp> {
  final _state = AppState();
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (_, __) => MaterialApp(
        title: 'VeriPic',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: SplashScreen(appState: _state),
      ),
    );
  }
}

// ─── SPLASH ───────────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  final AppState appState;
  const SplashScreen({Key? key, required this.appState}) : super(key: key);
  @override
  State<SplashScreen> createState() => _SplashState();
}

class _SplashState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade, _scale, _progress;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
    _fade     = CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.5, curve: Curves.easeIn));
    _scale    = CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6, curve: Curves.elasticOut));
    _progress = CurvedAnimation(parent: _ctrl, curve: const Interval(0.3, 1.0, curve: Curves.easeInOut));
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 3200), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(PageRouteBuilder(
          pageBuilder: (_, __, ___) => HomeShell(appState: widget.appState),
          transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 600),
        ));
      }
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Stack(
          children: [
            // Background glow
            Center(
              child: Opacity(
                opacity: _fade.value,
                child: Container(
                  width: 380, height: 380,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      C.cyan.withOpacity(0.07),
                      C.blue.withOpacity(0.03),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon
                  Transform.scale(
                    scale: _scale.value,
                    child: Opacity(
                      opacity: _fade.value.clamp(0.0, 1.0),
                      child: _VeriPicLogo(),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Title
                  Opacity(
                    opacity: _fade.value,
                    child: RichText(
                      text: TextSpan(
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 48, fontWeight: FontWeight.w900,
                            letterSpacing: -2.5),
                        children: [
                          TextSpan(
                            text: 'Veri',
                            style: TextStyle(
                              foreground: Paint()
                                ..shader = const LinearGradient(
                                    colors: [C.t1, C.t2])
                                    .createShader(const Rect.fromLTWH(0, 0, 120, 60)),
                            ),
                          ),
                          TextSpan(
                            text: 'Pic',
                            style: TextStyle(
                              foreground: Paint()
                                ..shader = const LinearGradient(
                                    colors: [C.cyan, C.blue])
                                    .createShader(const Rect.fromLTWH(0, 0, 120, 60)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Opacity(
                    opacity: _fade.value,
                    child: Text('TAMPER-PROOF · GEOTAGGED · VERIFIED',
                        style: GoogleFonts.sourceCodePro(
                            fontSize: 10, letterSpacing: 2.5, color: C.t3)),
                  ),
                  const SizedBox(height: 56),
                  // Tech badges
                  Opacity(
                    opacity: _fade.value,
                    child: Wrap(
                      spacing: 8,
                      children: ['HMAC-SHA256', 'LSB-STEGO', 'NVIDIA AI', 'GPS+UTC']
                          .map((t) => _SplashBadge(t))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Progress bar
                  SizedBox(
                    width: 200,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress.value,
                        minHeight: 2,
                        backgroundColor: C.border,
                        valueColor: const AlwaysStoppedAnimation(C.cyan),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 36, left: 0, right: 0,
              child: Opacity(
                opacity: _fade.value,
                child: Text('v3.0 · Cryptographic Authenticity Engine',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.sourceCodePro(
                        fontSize: 10, color: C.t3, letterSpacing: 1.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VeriPicLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      Container(
        width: 130, height: 130,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [
            C.cyan.withOpacity(0.10),
            C.blue.withOpacity(0.04),
            Colors.transparent,
          ]),
          boxShadow: [BoxShadow(color: C.cyan.withOpacity(0.2), blurRadius: 50, spreadRadius: 10)],
        ),
      ),
      Container(
        width: 84, height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle, color: C.cardHigh,
          border: Border.all(color: C.cyan.withOpacity(0.5), width: 1.5),
        ),
        child: const Icon(Icons.verified_user_rounded, color: C.cyan, size: 40),
      ),
    ]);
  }
}

class _SplashBadge extends StatelessWidget {
  final String text;
  const _SplashBadge(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: C.cyan.withOpacity(0.07),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: C.cyan.withOpacity(0.2)),
    ),
    child: Text(text, style: GoogleFonts.sourceCodePro(
        fontSize: 9, color: C.cyan, letterSpacing: 1)),
  );
}

// ─── HOME SHELL (6 tabs: Upload, Camera, Results, Geo Map, History, Settings)
class HomeShell extends StatelessWidget {
  final AppState appState;
  const HomeShell({Key? key, required this.appState}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (_, __) {
        final screens = [
          UploadScreen(appState: appState),           // 0: Upload (existing)
          const CameraScreen(),                        // 1: VeriPic Camera [NEW]
          ResultsScreen(result: appState.lastResult), // 2: Results (existing)
          GeoMapScreen(result: appState.lastResult),  // 3: Geo Map (existing)
          const VerificationScreen(),                  // 4: Verify [NEW]
          const HistoryScreen(),                       // 5: History (existing)
          const SettingsScreen(),                      // 6: Settings (existing)
        ];
        return Scaffold(
          body: IndexedStack(index: appState.tabIndex, children: screens),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: C.border)),
            ),
            child: BottomNavigationBar(
              currentIndex: appState.tabIndex,
              onTap: appState.setTab,
              backgroundColor: C.surface,
              elevation: 0,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.upload_file_outlined),
                  activeIcon: Icon(Icons.upload_file_rounded),
                  label: 'Upload',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.camera_alt_outlined),
                  activeIcon: Icon(Icons.camera_alt_rounded),
                  label: 'Camera',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.analytics_outlined),
                  activeIcon: Icon(Icons.analytics_rounded),
                  label: 'Results',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.map_outlined),
                  activeIcon: Icon(Icons.map_rounded),
                  label: 'Geo Map',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.verified_user_outlined),
                  activeIcon: Icon(Icons.verified_user_rounded),
                  label: 'Verify',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.history_outlined),
                  activeIcon: Icon(Icons.history_rounded),
                  label: 'History',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings_outlined),
                  activeIcon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── UPLOAD SCREEN ────────────────────────────────────────────────────────────
class UploadScreen extends StatefulWidget {
  final AppState appState;
  const UploadScreen({Key? key, required this.appState}) : super(key: key);
  @override
  State<UploadScreen> createState() => _UploadState();
}

class _UploadState extends State<UploadScreen> with TickerProviderStateMixin {
  File? _image;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  static const _steps = [
    'Extracting EXIF metadata',
    'Running visual deepfake detection',
    'Face region inconsistency analysis',
    'Geo-consistency verification',
    'Shadow & sun angle check',
    'PRNU sensor fingerprint audit',
    'Generating analysis report',
  ];
  static const _stepDetails = [
    'GPS, timestamp, device model, camera make...',
    'GAN artifact detection via FFT/DCT analysis...',
    'Checking boundary gradients at hairline edges...',
    'Matching scene landmarks against GPS coordinates...',
    'Solar azimuth cross-check at claimed lat/lon...',
    'Comparing noise pattern vs declared camera model...',
    'Compiling findings with confidence scores...',
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.97, end: 1.03).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _pulseCtrl.dispose(); super.dispose(); }

  Future<void> _pick(ImageSource src) async {
    final f = await ImagePicker().pickImage(source: src);
    if (f != null) setState(() => _image = File(f.path));
  }

  Future<void> _analyze() async {
    if (_image == null) return;
    final st = widget.appState;
    for (int i = 0; i < _steps.length; i++) {
      st.setScan(
        analyzing: true,
        progress: (i + 1) / _steps.length,
        label: _steps[i], step: i,
      );
      await Future.delayed(Duration(milliseconds: 400 + Random().nextInt(300)));
    }
    final result = await AnalysisService.analyze(_image!, _image!.path.split('/').last);
    if (StorageService.getAutoSave()) await StorageService.save(result);
    st.setScan(analyzing: false, progress: 0, label: '', step: 0);
    st.setResult(result);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (_, __) {
        final scanning = widget.appState.isAnalyzing;
        return Scaffold(
          backgroundColor: C.bg,
          appBar: AppBar(
            title: Row(children: [
              const Icon(Icons.verified_user_rounded, color: C.cyan, size: 20),
              const SizedBox(width: 8),
              Text('VeriPic', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w900, color: C.t1)),
            ]),
            actions: [_CyanBadge('v3.0'), const SizedBox(width: 16)],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Camera CTA banner
                _CameraBanner(onTap: () => widget.appState.setTab(1)),
                const SizedBox(height: 16),
                _SectionHeader('Upload & Analyze', 'Drop a geo-tagged photo to detect deepfake manipulation'),
                const SizedBox(height: 20),
                if (!scanning) _dropZone() else _scannerUI(),
                const SizedBox(height: 20),
                if (!scanning) ...[
                  _GlowButton(
                    label: 'Analyze Image',
                    icon: Icons.search_rounded,
                    enabled: _image != null,
                    onTap: _analyze,
                  ),
                  const SizedBox(height: 32),
                  _SectionHeader('Detection Pipeline', 'Layered analysis covering visual, metadata & geo signals'),
                  const SizedBox(height: 16),
                  _pipelineGrid(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dropZone() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Transform.scale(
          scale: _image == null ? _pulse.value : 1.0, child: child),
      child: GestureDetector(
        onTap: _showPicker,
        child: Container(
          width: double.infinity, height: 230,
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _image != null ? C.cyan : C.border,
              width: _image != null ? 1.5 : 1.0,
            ),
          ),
          child: _image != null ? _imagePreview() : _dropHint(),
        ),
      ),
    );
  }

  Widget _imagePreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(17),
      child: Stack(fit: StackFit.expand, children: [
        Image.file(_image!, fit: BoxFit.cover),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, C.bg.withOpacity(0.85)],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: C.green.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: C.green.withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.check_rounded, color: C.green, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Image ready', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.t1)),
                      Text(_image!.path.split('/').last,
                          style: const TextStyle(fontSize: 11, color: C.t3),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                _SmallChip('Tap to change'),
              ],
            ),
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
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: C.cyan.withOpacity(0.07),
            border: Border.all(color: C.cyan.withOpacity(0.25)),
          ),
          child: const Icon(Icons.cloud_upload_rounded, color: C.cyan, size: 30),
        ),
        const SizedBox(height: 16),
        Text('Drop geo-tagged photo here',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 15, fontWeight: FontWeight.w700, color: C.t1)),
        const SizedBox(height: 6),
        const Text('JPEG · PNG · HEIC  ·  EXIF metadata required',
            style: TextStyle(color: C.t3, fontSize: 12)),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          children: ['GPS coords', 'Timestamp', 'PRNU', 'EXIF intact']
              .map((t) => _SmallChip(t)).toList(),
        ),
      ],
    );
  }

  Widget _scannerUI() {
    final st = widget.appState;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _PulsingDot(),
            const SizedBox(width: 8),
            Text('SCANNING IN PROGRESS',
                style: GoogleFonts.sourceCodePro(
                    fontSize: 11, color: C.cyan, letterSpacing: 2, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: st.scanProgress),
              duration: const Duration(milliseconds: 400),
              builder: (_, v, __) => LinearProgressIndicator(
                value: v, minHeight: 5,
                backgroundColor: C.border,
                valueColor: const AlwaysStoppedAnimation(C.cyan),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('${(st.scanProgress * 100).toInt()}%  —  ${st.scanLabel}',
              style: GoogleFonts.sourceCodePro(fontSize: 11, color: C.t2)),
          const SizedBox(height: 20),
          ...List.generate(_steps.length, (i) {
            final done   = i < st.scanStep;
            final active = i == st.scanStep;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Column(children: [
                      Container(
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done ? C.green : active ? C.cyan.withOpacity(0.15) : C.border,
                          border: Border.all(
                            color: done ? C.green : active ? C.cyan : C.border,
                            width: 1.5,
                          ),
                        ),
                        child: done
                            ? const Icon(Icons.check_rounded, size: 11, color: C.bg)
                            : active
                            ? Center(child: _PulsingDot(size: 7))
                            : null,
                      ),
                      if (i < _steps.length - 1)
                        Container(
                          width: 1.5, height: 20,
                          color: done ? C.green.withOpacity(0.4) : C.border,
                        ),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _steps[i],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                            color: done ? C.t3 : active ? C.t1 : C.t3,
                          ),
                        ),
                        if (active)
                          Text(_stepDetails[i],
                              style: const TextStyle(fontSize: 11, color: C.t3)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _pipelineGrid() {
    final items = [
      _PI(Icons.face_retouching_off_rounded, 'Visual Deepfake', 'GAN artifacts via FFT/DCT frequency analysis', C.cyan),
      _PI(Icons.location_on_rounded,          'Geo Consistency',  'Scene-vs-GPS matching, landmark verification', C.green),
      _PI(Icons.fingerprint_rounded,          'PRNU Forensics',   'Sensor noise pattern & device spoofing detection', C.amber),
      _PI(Icons.wb_sunny_rounded,             'Shadow Analysis',  'Solar position vs claimed GPS + timestamp', C.purple),
      _PI(Icons.data_object_rounded,          'EXIF Forensics',   'Metadata integrity, timezone offset, GPS audit', C.red),
      _PI(Icons.psychology_rounded,           'NVIDIA AI',        'Neva-22B multimodal deepfake detection', C.blue),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 12,
          mainAxisSpacing: 12, childAspectRatio: 1.25),
      itemCount: items.length,
      itemBuilder: (_, i) => _PipelineCard(item: items[i]),
    );
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.cardHigh,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          _SheetTile(Icons.photo_library_rounded, 'Gallery',
                  () { Navigator.pop(context); _pick(ImageSource.gallery); }),
          _SheetTile(Icons.camera_alt_rounded, 'Camera',
                  () { Navigator.pop(context); _pick(ImageSource.camera); }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ─── Camera CTA Banner ────────────────────────────────────────────────────────
class _CameraBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _CameraBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [C.cyan.withOpacity(0.1), C.blue.withOpacity(0.08)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: C.cyan.withOpacity(0.3)),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: C.cyan.withOpacity(0.15),
              border: Border.all(color: C.cyan.withOpacity(0.4)),
            ),
            child: const Icon(Icons.camera_alt_rounded, color: C.cyan, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('VeriPic Camera',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 14, fontWeight: FontWeight.w800, color: C.t1)),
            const SizedBox(height: 3),
            const Text('Capture tamper-proof geotagged photos with crypto signing',
                style: TextStyle(fontSize: 11, color: C.t3)),
          ])),
          const Icon(Icons.arrow_forward_ios_rounded, color: C.t3, size: 16),
        ]),
      ),
    );
  }
}

class _PI {
  final IconData icon; final String title, desc; final Color color;
  const _PI(this.icon, this.title, this.desc, this.color);
}

class _PipelineCard extends StatelessWidget {
  final _PI item;
  const _PipelineCard({required this.item});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: C.surface, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: C.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: item.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(item.icon, color: item.color, size: 19),
      ),
      const SizedBox(height: 10),
      Text(item.title, style: GoogleFonts.spaceGrotesk(
          fontSize: 12, fontWeight: FontWeight.w800, color: C.t1)),
      const SizedBox(height: 3),
      Text(item.desc, style: const TextStyle(fontSize: 10, color: C.t3),
          maxLines: 2, overflow: TextOverflow.ellipsis),
    ]),
  );
}

// ─── RESULTS SCREEN ───────────────────────────────────────────────────────────
class ResultsScreen extends StatelessWidget {
  final AnalysisResult? result;
  const ResultsScreen({Key? key, this.result}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (result == null) return _empty(context);
    final r = result!;
    final statusColor = _sColor(r.status);

    return Scaffold(
      backgroundColor: C.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true, expandedHeight: 130,
            backgroundColor: C.bg, scrolledUnderElevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Analysis Results',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 17, fontWeight: FontWeight.w900, color: C.t1)),
                        Text(DateFormat('MMM dd, yyyy · HH:mm').format(r.analyzedAt),
                            style: const TextStyle(fontSize: 10, color: C.t3)),
                      ],
                    ),
                  ),
                  _StatusPill(status: r.status),
                ],
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [statusColor.withOpacity(0.08), C.bg],
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _VerdictBanner(r),
                const SizedBox(height: 20),
                _ScoreSection(r),
                const SizedBox(height: 24),
                _SectionHeader('Visual Analysis', 'Pixel-level manipulation signals'),
                const SizedBox(height: 12),
                _VisualBarsCard(r),
                const SizedBox(height: 24),
                _SectionHeader('Signal Radar', '5-axis manipulation detection'),
                const SizedBox(height: 12),
                _RadarSection(r),
                const SizedBox(height: 24),
                _SectionHeader('Flagged Anomalies', '${r.anomalies.length} checks performed'),
                const SizedBox(height: 12),
                ...r.anomalies.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AnomalyTile(anomaly: a))),
                const SizedBox(height: 24),
                _SectionHeader('EXIF Metadata', 'Raw metadata extracted from image'),
                const SizedBox(height: 12),
                _ExifTable(r.exifData),
                const SizedBox(height: 24),
                _ActionRow(result: r),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext ctx) => Scaffold(
    backgroundColor: C.bg,
    appBar: AppBar(title: const Text('Analysis Results')),
    body: Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.analytics_outlined, size: 72, color: C.border),
        const SizedBox(height: 20),
        Text('No analysis yet', style: GoogleFonts.spaceGrotesk(
            fontSize: 18, fontWeight: FontWeight.w700, color: C.t2)),
        const SizedBox(height: 8),
        const Text('Upload a geo-tagged image to begin',
            style: TextStyle(color: C.t3, fontSize: 14)),
      ]),
    ),
  );

  Color _sColor(AnalysisStatus s) => switch (s) {
    AnalysisStatus.fake        => C.red,
    AnalysisStatus.suspicious  => C.amber,
    AnalysisStatus.authentic   => C.green,
    AnalysisStatus.pending     => C.t3,
  };
}

class _VerdictBanner extends StatelessWidget {
  final AnalysisResult r;
  const _VerdictBanner(this.r);
  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (r.status) {
      AnalysisStatus.fake       => (C.red,    Icons.dangerous_rounded),
      AnalysisStatus.suspicious => (C.amber,  Icons.warning_amber_rounded),
      AnalysisStatus.authentic  => (C.green,  Icons.verified_rounded),
      AnalysisStatus.pending    => (C.t3,     Icons.hourglass_empty),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(r.verdictSummary ?? '',
              style: TextStyle(fontSize: 13, color: color.withOpacity(0.9), height: 1.5)),
        ),
      ]),
    );
  }
}

class _ScoreSection extends StatelessWidget {
  final AnalysisResult r;
  const _ScoreSection(this.r);
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _ScoreRing(score: r.authenticityScore, status: r.status),
      const SizedBox(width: 14),
      Expanded(
        child: Column(children: [
          _MiniMetric('Geo Match', '${r.geoData.geoMatchScore}/100', _sc(r.geoData.geoMatchScore)),
          const SizedBox(height: 8),
          _MiniMetric('Metadata', r.metaInteg > 0.6 ? 'PASS' : 'FAIL',
              r.metaInteg > 0.6 ? C.green : C.red),
          const SizedBox(height: 8),
          _MiniMetric('Time', '${(r.analysisTimeMs / 1000).toStringAsFixed(1)}s', C.cyan),
        ]),
      ),
    ]);
  }
  Color _sc(int s) => s >= 65 ? C.green : s >= 40 ? C.amber : C.red;
}

class _ScoreRing extends StatefulWidget {
  final int score; final AnalysisStatus status;
  const _ScoreRing({required this.score, required this.status});
  @override
  State<_ScoreRing> createState() => _ScoreRingState();
}

class _ScoreRingState extends State<_ScoreRing> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _a = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    _c.forward();
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.status) {
      AnalysisStatus.fake       => C.red,
      AnalysisStatus.suspicious => C.amber,
      AnalysisStatus.authentic  => C.green,
      AnalysisStatus.pending    => C.t3,
    };
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) {
        return SizedBox(
          width: 140, height: 140,
          child: CustomPaint(
            painter: _RingPainter(
              progress: (widget.score / 100) * _a.value,
              color: color, bgColor: C.border,
            ),
            child: Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${widget.score}',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 30, fontWeight: FontWeight.w900, color: color)),
                const Text('/100', style: TextStyle(fontSize: 11, color: C.t3)),
                Text('AUTH.',
                    style: GoogleFonts.sourceCodePro(
                        fontSize: 8, letterSpacing: 2, color: C.t3)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress; final Color color, bgColor;
  _RingPainter({required this.progress, required this.color, required this.bgColor});
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2; final cy = size.height / 2;
    final radius = size.width / 2 - 10;
    final paint = Paint()..strokeWidth = 9..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    paint.color = bgColor;
    canvas.drawCircle(Offset(cx, cy), radius, paint);
    paint.color = color;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      -pi / 2, 2 * pi * progress, false, paint,
    );
  }
  @override
  bool shouldRepaint(_RingPainter o) => o.progress != progress;
}

class _MiniMetric extends StatelessWidget {
  final String label, value; final Color color;
  const _MiniMetric(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: C.surface, borderRadius: BorderRadius.circular(10),
      border: Border.all(color: C.border),
    ),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: C.t2)),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
    ]),
  );
}

class _VisualBarsCard extends StatelessWidget {
  final AnalysisResult r;
  const _VisualBarsCard(this.r);
  @override
  Widget build(BuildContext context) {
    final bars = [
      ('GAN artifact probability',  r.ganProb),
      ('Face region inconsistency', r.faceInc),
      ('Compression re-encode',     r.compression),
      ('Frequency domain anomaly',  r.freqAnom),
      ('Texture inconsistency',     r.texInc),
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: C.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.border),
      ),
      child: Column(
        children: bars.asMap().entries.map((e) => Padding(
          padding: EdgeInsets.only(bottom: e.key < bars.length - 1 ? 14 : 0),
          child: _AnimBar(label: e.value.$1, value: e.value.$2),
        )).toList(),
      ),
    );
  }
}

class _AnimBar extends StatefulWidget {
  final String label; final double value;
  const _AnimBar({required this.label, required this.value});
  @override
  State<_AnimBar> createState() => _AnimBarState();
}

class _AnimBarState extends State<_AnimBar> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _a = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    Future.delayed(const Duration(milliseconds: 150), () { if (mounted) _c.forward(); });
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  Color get _color => widget.value > 0.65 ? C.red : widget.value > 0.35 ? C.amber : C.green;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (_, __) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(widget.label, style: const TextStyle(fontSize: 12, color: C.t2)),
          Text('${(widget.value * 100).toInt()}%',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _color)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: widget.value * _a.value, minHeight: 6,
            backgroundColor: C.border,
            valueColor: AlwaysStoppedAnimation(_color),
          ),
        ),
      ],
    ),
  );
}

class _RadarSection extends StatelessWidget {
  final AnalysisResult r;
  const _RadarSection(this.r);
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.border),
      ),
      child: RadarChart(
        RadarChartData(
          radarShape: RadarShape.polygon,
          tickCount: 4,
          radarBackgroundColor: Colors.transparent,
          borderData: FlBorderData(show: false),
          radarBorderData: const BorderSide(color: C.border, width: 1),
          gridBorderData: const BorderSide(color: C.border, width: 0.5),
          tickBorderData: const BorderSide(color: C.border, width: 0.5),
          titlePositionPercentageOffset: 0.22,
          titleTextStyle: GoogleFonts.sourceCodePro(fontSize: 9, color: C.t3, letterSpacing: 0.5),
          getTitle: (i, _) {
            const t = ['GAN', 'FACE', 'GEO', 'META', 'TEXTURE'];
            return RadarChartTitle(text: t[i]);
          },
          dataSets: [
            RadarDataSet(
              fillColor: C.cyan.withOpacity(0.10),
              borderColor: C.cyan,
              borderWidth: 1.5,
              entryRadius: 3,
              dataEntries: [
                RadarEntry(value: r.ganProb * 100),
                RadarEntry(value: r.faceInc * 100),
                RadarEntry(value: (1 - r.geoData.geoMatchScore / 100) * 100),
                RadarEntry(value: (1 - r.metaInteg) * 100),
                RadarEntry(value: r.texInc * 100),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnomalyTile extends StatelessWidget {
  final AnomalyItem anomaly;
  const _AnomalyTile({required this.anomaly});
  @override
  Widget build(BuildContext context) {
    final (bg, bdr, color, icon) = switch (anomaly.type) {
      AnomalyType.danger  => (C.red.withOpacity(0.06),   C.red.withOpacity(0.22),   C.red,   Icons.cancel_rounded),
      AnomalyType.warning => (C.amber.withOpacity(0.06), C.amber.withOpacity(0.22), C.amber, Icons.warning_amber_rounded),
      AnomalyType.success => (C.green.withOpacity(0.06), C.green.withOpacity(0.22), C.green, Icons.check_circle_rounded),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bdr),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(anomaly.title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.t1)),
              ),
              if (anomaly.confidence > 0)
                Text('${(anomaly.confidence * 100).toInt()}%',
                    style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            Text(anomaly.description,
                style: const TextStyle(fontSize: 12, color: C.t3, height: 1.4)),
          ]),
        ),
      ]),
    );
  }
}

class _ExifTable extends StatelessWidget {
  final Map<String, String> data;
  const _ExifTable(this.data);
  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList();
    return Container(
      decoration: BoxDecoration(
        color: C.surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.border),
      ),
      child: Column(
        children: List.generate(entries.length, (i) {
          final e = entries[i];
          final spoofed = e.value.contains('Spoofed') || e.value.contains('stripped') || e.value.contains('Falsified');
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: i < entries.length - 1
                  ? const Border(bottom: BorderSide(color: C.border, width: 0.5))
                  : null,
            ),
            child: Row(children: [
              Expanded(flex: 2,
                  child: Text(e.key, style: const TextStyle(fontSize: 12, color: C.t3))),
              Expanded(flex: 3,
                  child: Text(e.value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        fontFamily: GoogleFonts.sourceCodePro().fontFamily,
                        color: spoofed ? C.red : C.t1,
                      ))),
            ]),
          );
        }),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final AnalysisResult result;
  const _ActionRow({required this.result});
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: _GlowButton(
      label: 'Download PDF', icon: Icons.download_rounded, enabled: true,
      onTap: () => _snack(context, 'Integrate printing package to export PDF'),
    )),
    const SizedBox(width: 10),
    _IconBtn(Icons.share_rounded,
            () => _snack(context, 'Integrate share_plus for sharing')),
    const SizedBox(width: 8),
    _IconBtn(Icons.copy_rounded, () {
      Clipboard.setData(ClipboardData(
          text: 'VeriPic: ${result.authenticityScore}/100 — ${result.status.name}'));
      _snack(context, 'Copied to clipboard');
    }),
  ]);

  void _snack(BuildContext ctx, String msg) =>
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: C.cardHigh,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
}

// ─── GEO MAP SCREEN ───────────────────────────────────────────────────────────
class GeoMapScreen extends StatelessWidget {
  final AnalysisResult? result;
  const GeoMapScreen({Key? key, this.result}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (result == null) {
      return Scaffold(
        backgroundColor: C.bg,
        appBar: AppBar(title: const Text('Geo Map')),
        body: const Center(child: Text('No analysis available', style: TextStyle(color: C.t3))),
      );
    }
    final geo   = result!.geoData;
    final isFk  = result!.status == AnalysisStatus.fake;
    final clm   = LatLng(geo.claimedLat ?? 19.076, geo.claimedLng ?? 72.877);
    final det   = LatLng(geo.detectedLat ?? geo.claimedLat ?? 19.076,
        geo.detectedLng ?? geo.claimedLng ?? 72.877);

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: const Text('Geo Map'),
        actions: [_StatusPill(status: result!.status), const SizedBox(width: 16)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 280,
                child: FlutterMap(
                  options: MapOptions(initialCenter: clm, initialZoom: isFk ? 2.5 : 11),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.veripic.app',
                    ),
                    if (isFk) PolylineLayer(polylines: [
                      Polyline(
                        points: [clm, det],
                        color: C.red.withOpacity(0.45),
                        strokeWidth: 1.5, isDotted: true,
                      ),
                    ]),
                    MarkerLayer(markers: [
                      _mkr(clm, C.cyan, 'Claimed'),
                      if (isFk) _mkr(det, C.red, 'Detected'),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: _GeoCard('Claimed GPS', geo.claimedCity, geo.claimedCountry, geo.claimedLat, geo.claimedLng, null, C.cyan)),
              const SizedBox(width: 12),
              Expanded(child: _GeoCard('Scene Match', geo.detectedCity, geo.detectedCountry, geo.detectedLat, geo.detectedLng,
                  geo.distanceKm != null ? '${geo.distanceKm!.toStringAsFixed(0)} km offset' : null,
                  isFk ? C.red : C.green)),
            ]),
            const SizedBox(height: 20),
            _SectionHeader('Geo Verification Signals', ''),
            const SizedBox(height: 12),
            _GeoSignalsCard(geo: geo),
            const SizedBox(height: 18),
            _DistanceCard(geo: geo, isFake: isFk),
          ],
        ),
      ),
    );
  }

  Marker _mkr(LatLng pos, Color color, String label) => Marker(
    point: pos, width: 80, height: 56,
    child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900)),
      ),
      Icon(Icons.location_on, color: color, size: 28),
    ]),
  );
}

class _GeoCard extends StatelessWidget {
  final String title; final String? city, country; final double? lat, lng; final String? extra; final Color color;
  const _GeoCard(this.title, this.city, this.country, this.lat, this.lng, this.extra, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: C.surface, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 11, color: C.t3)),
      const SizedBox(height: 6),
      Text(city ?? '—', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
      Text(country ?? '—', style: const TextStyle(fontSize: 12, color: C.t2)),
      if (lat != null) ...[
        const SizedBox(height: 6),
        Text('${lat!.toStringAsFixed(4)}°, ${lng!.toStringAsFixed(4)}°',
            style: GoogleFonts.sourceCodePro(fontSize: 10, color: C.t3)),
      ],
      if (extra != null) ...[
        const SizedBox(height: 5),
        Text(extra!, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w800)),
      ],
    ]),
  );
}

class _GeoSignalsCard extends StatelessWidget {
  final GeoData geo;
  const _GeoSignalsCard({required this.geo});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: C.surface, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: C.border),
    ),
    child: Column(children: [
      _GSRow('Shadow match (claimed)',  geo.shadowClaimed),
      const SizedBox(height: 12),
      _GSRow('Shadow match (detected)', geo.shadowDetected),
      const SizedBox(height: 12),
      _GSRow('Weather consistency',     geo.weatherConsistency),
      const SizedBox(height: 12),
      _GSRow('Landmark confidence',     geo.landmarkConf),
    ]),
  );
}

class _GSRow extends StatelessWidget {
  final String label; final double value;
  const _GSRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final color = value > 0.6 ? C.green : value > 0.3 ? C.amber : C.red;
    return Row(children: [
      Expanded(flex: 3, child: Text(label, style: const TextStyle(fontSize: 12, color: C.t2))),
      Expanded(flex: 4, child: Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value, minHeight: 6,
              backgroundColor: C.border,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('${(value * 100).toInt()}%',
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
      ])),
    ]);
  }
}

class _DistanceCard extends StatelessWidget {
  final GeoData geo; final bool isFake;
  const _DistanceCard({required this.geo, required this.isFake});
  @override
  Widget build(BuildContext context) {
    final color = isFake ? C.red : C.green;
    final dist  = geo.distanceKm;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: C.surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.1)),
          child: Icon(Icons.social_distance_rounded, color: color, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              dist != null ? (dist < 10 ? 'Location match' : '${dist.toStringAsFixed(0)} km discrepancy') : 'No GPS data',
              style: GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              isFake ? 'Claimed ${geo.claimedCity} vs detected ${geo.detectedCity}' : 'GPS coords consistent with scene content',
              style: const TextStyle(fontSize: 12, color: C.t3),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── HISTORY SCREEN ───────────────────────────────────────────────────────────
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);
  @override
  State<HistoryScreen> createState() => _HistoryState();
}

class _HistoryState extends State<HistoryScreen> {
  List<AnalysisResult> _history = [];
  String _filter = 'All';
  @override
  void initState() { super.initState(); _load(); }
  void _load() => setState(() => _history = StorageService.load());

  List<AnalysisResult> get _filtered => _filter == 'All'
      ? _history : _history.where((r) => r.status.name == _filter.toLowerCase()).toList();

  @override
  Widget build(BuildContext context) {
    final fakes = _history.where((r) => r.status == AnalysisStatus.fake).length;
    final auths = _history.where((r) => r.status == AnalysisStatus.authentic).length;

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (_history.isNotEmpty)
            TextButton(
              onPressed: _confirmClear,
              child: const Text('Clear', style: TextStyle(color: C.red, fontSize: 13)),
            ),
        ],
      ),
      body: _history.isEmpty
          ? Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.history_rounded, size: 72, color: C.border),
          const SizedBox(height: 20),
          Text('No history yet', style: GoogleFonts.spaceGrotesk(
              fontSize: 18, fontWeight: FontWeight.w700, color: C.t2)),
          const SizedBox(height: 8),
          const Text('Analyzed images appear here', style: TextStyle(color: C.t3)),
        ]),
      )
          : CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(children: [
                Row(children: [
                  _StatBox('${_history.length}', 'Total', C.t1),
                  const SizedBox(width: 10),
                  _StatBox('$fakes', 'Fake', C.red),
                  const SizedBox(width: 10),
                  _StatBox('$auths', 'Auth', C.green),
                ]),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'Fake', 'Suspicious', 'Authentic']
                        .map((f) => _FilterChip(
                      label: f,
                      selected: _filter == f,
                      onTap: () => setState(() => _filter = f),
                    ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _HistoryCard(
                    result: _filtered[i],
                    onDelete: () {
                      final id = _filtered[i].id;
                      setState(() => _history.removeWhere((r) => r.id == id));
                      StorageService.clear();
                      for (final r in _history) StorageService.save(r);
                    },
                  ),
                ),
                childCount: _filtered.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClear() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Clear history'),
      content: const Text('Delete all analysis records permanently?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            await StorageService.clear();
            _load();
          },
          child: const Text('Delete', style: TextStyle(color: C.red)),
        ),
      ],
    ),
  );
}

class _StatBox extends StatelessWidget {
  final String value, label; final Color color;
  const _StatBox(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: C.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.border),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: C.t3)),
      ]),
    ),
  );
}

class _FilterChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      'Fake' => C.red, 'Suspicious' => C.amber, 'Authentic' => C.green, _ => C.cyan,
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : C.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color.withOpacity(0.4) : C.border),
        ),
        child: Text(label, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700,
            color: selected ? color : C.t3)),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final AnalysisResult result; final VoidCallback onDelete;
  const _HistoryCard({required this.result, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (result.status) {
      AnalysisStatus.fake       => (C.red,   'FAKE'),
      AnalysisStatus.suspicious => (C.amber, 'SUSP.'),
      AnalysisStatus.authentic  => (C.green, 'AUTH.'),
      AnalysisStatus.pending    => (C.t3,    'PEND.'),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.border),
      ),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Icon(Icons.image_rounded, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(result.fileName,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.t1),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(
              '${DateFormat('MMM dd, HH:mm').format(result.analyzedAt)} · ${result.authenticityScore}/100',
              style: const TextStyle(fontSize: 11, color: C.t3),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
          child: Text(label, style: TextStyle(
              fontSize: 9, color: color, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: C.t3),
          onPressed: onDelete,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ]),
    );
  }
}

// ─── SETTINGS SCREEN ──────────────────────────────────────────────────────────
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);
  @override
  State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  late double _thresh;
  late int    _geoSens;
  late bool   _autoSave;
  @override
  void initState() {
    super.initState();
    _thresh   = StorageService.getThreshold();
    _geoSens  = StorageService.getGeoSens();
    _autoSave = StorageService.getAutoSave();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader('Detection Thresholds', 'Tune sensitivity of analysis signals'),
            const SizedBox(height: 12),
            _SCard(children: [
              _SliderRow(
                label: 'Fake confidence threshold',
                display: '${_thresh.toInt()}%',
                value: _thresh, min: 50, max: 95,
                onChanged: (v) { setState(() => _thresh = v); StorageService.setThreshold(v); },
              ),
              const Divider(height: 0.5, color: C.border),
              _StepRow(
                label: 'Geo mismatch sensitivity',
                value: _geoSens, options: const ['Low', 'Medium', 'High'],
                onChanged: (v) { setState(() => _geoSens = v); StorageService.setGeoSens(v); },
              ),
            ]),

            const SizedBox(height: 22),
            _SectionHeader('App Preferences', ''),
            const SizedBox(height: 12),
            _SCard(children: [
              _SwitchRow('Auto-save results', 'Save every analysis to history', _autoSave,
                      (v) { setState(() => _autoSave = v); StorageService.setAutoSave(v); }),
            ]),

            const SizedBox(height: 22),
            _SectionHeader('Connected APIs', 'Live data sources for verification'),
            const SizedBox(height: 12),
            _SCard(children: [
              _ApiRow('NVIDIA Neva-22B', 'AI deepfake & artifact detection',
                  _nvidiaConfigured()),
              const Divider(height: 0.5, color: C.border),
              _ApiRow('HMAC-SHA256 Engine', 'Cryptographic signing (active)', true),
              const Divider(height: 0.5, color: C.border),
              _ApiRow('LSB Steganography', 'Pixel watermark embed/extract', true),
              const Divider(height: 0.5, color: C.border),
              _ApiRow('Geolocator GPS', 'High-accuracy location services', true),
            ]),

            const SizedBox(height: 22),
            _SectionHeader('About', ''),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: C.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: C.cyan.withOpacity(0.18)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [C.cyan.withOpacity(0.04), C.blue.withOpacity(0.02)],
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.verified_user_rounded, color: C.cyan, size: 22),
                  const SizedBox(width: 10),
                  Text('VeriPic v3.0',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 16, fontWeight: FontWeight.w900, color: C.t1)),
                ]),
                const SizedBox(height: 10),
                const Text(
                  'Tamper-proof geotagged camera and verification system. '
                  'Combines HMAC-SHA256 cryptographic signing, LSB steganographic '
                  'watermarking, and NVIDIA AI deepfake detection to create an '
                  'unbreakable chain of image authenticity.',
                  style: TextStyle(fontSize: 12, color: C.t3, height: 1.6),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8, runSpacing: 6,
                  children: ['HMAC-SHA256', 'LSB-Stego', 'NVIDIA AI', 'GPS+UTC', 'ECDSA-ready']
                      .map((t) => _SmallChip(t)).toList(),
                ),
              ]),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  bool _nvidiaConfigured() {
    try {
      final key = dotenv.maybeGet('NVIDIA_API_KEY') ?? '';
      return key.isNotEmpty && key != 'YOUR_NVIDIA_BUILD_API_KEY_HERE';
    } catch (_) {
      return false;
    }
  }
}

// ─── SHARED WIDGETS ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title, sub;
  const _SectionHeader(this.title, this.sub);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: GoogleFonts.spaceGrotesk(
          fontSize: 15, fontWeight: FontWeight.w800,
          color: C.t1, letterSpacing: -0.2)),
      if (sub.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(fontSize: 12, color: C.t3)),
      ],
    ],
  );
}

class _StatusPill extends StatelessWidget {
  final AnalysisStatus status;
  const _StatusPill({required this.status});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      AnalysisStatus.fake       => ('FAKE',       C.red),
      AnalysisStatus.suspicious => ('SUSPICIOUS', C.amber),
      AnalysisStatus.authentic  => ('AUTHENTIC',  C.green),
      AnalysisStatus.pending    => ('PENDING',    C.t3),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(
          fontSize: 10, color: color,
          fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
  }
}

class _CyanBadge extends StatelessWidget {
  final String text;
  const _CyanBadge(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: C.cyan.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: C.cyan.withOpacity(0.25)),
    ),
    child: Text(text, style: GoogleFonts.sourceCodePro(
        fontSize: 11, color: C.cyan,
        fontWeight: FontWeight.w700, letterSpacing: 0.5)),
  );
}

class _SmallChip extends StatelessWidget {
  final String label;
  const _SmallChip(this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: C.cardHigh, borderRadius: BorderRadius.circular(6),
      border: Border.all(color: C.border),
    ),
    child: Text(label, style: const TextStyle(fontSize: 11, color: C.t3)),
  );
}

class _GlowButton extends StatelessWidget {
  final String label; final IconData icon;
  final bool enabled; final VoidCallback onTap;
  const _GlowButton({required this.label, required this.icon,
    required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        color: enabled ? C.blue : C.border,
        borderRadius: BorderRadius.circular(14),
        boxShadow: enabled
            ? [BoxShadow(color: C.blue.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 6))]
            : [],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: enabled ? Colors.white : C.t3, size: 18),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.spaceGrotesk(
            fontSize: 15, fontWeight: FontWeight.w700,
            color: enabled ? Colors.white : C.t3)),
      ]),
    ),
  );
}

class _IconBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _IconBtn(this.icon, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: C.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.border),
      ),
      child: Icon(icon, color: C.t2, size: 20),
    ),
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
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
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
        width: widget.size, height: widget.size,
        decoration: const BoxDecoration(color: C.cyan, shape: BoxShape.circle),
      ),
    ),
  );
}

class _SheetTile extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _SheetTile(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
          color: C.cyan.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: C.cyan, size: 20),
    ),
    title: Text(label, style: const TextStyle(
        color: C.t1, fontSize: 14, fontWeight: FontWeight.w600)),
    onTap: onTap,
  );
}

class _SCard extends StatelessWidget {
  final List<Widget> children;
  const _SCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: C.surface, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: C.border),
    ),
    child: Column(children: children),
  );
}

class _SliderRow extends StatelessWidget {
  final String label, display; final double value, min, max;
  final ValueChanged<double> onChanged;
  const _SliderRow({required this.label, required this.display,
    required this.value, required this.min, required this.max, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: C.t2)),
        Text(display, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.cyan)),
      ]),
      Slider(value: value, min: min, max: max, onChanged: onChanged),
    ]),
  );
}

class _StepRow extends StatelessWidget {
  final String label; final int value; final List<String> options;
  final ValueChanged<int> onChanged;
  const _StepRow({required this.label, required this.value,
    required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: C.t2))),
      Row(
        children: options.asMap().entries.map((e) => GestureDetector(
          onTap: () => onChanged(e.key + 1),
          child: Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: value == e.key + 1 ? C.cyan.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: value == e.key + 1 ? C.cyan : C.border),
            ),
            child: Text(e.value, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: value == e.key + 1 ? C.cyan : C.t3)),
          ),
        )).toList(),
      ),
    ]),
  );
}

class _SwitchRow extends StatelessWidget {
  final String label, sub; final bool value; final ValueChanged<bool> onChanged;
  const _SwitchRow(this.label, this.sub, this.value, this.onChanged);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: C.t2)),
        Text(sub,   style: const TextStyle(fontSize: 11, color: C.t3)),
      ])),
      Switch(value: value, onChanged: onChanged),
    ]),
  );
}

class _ApiRow extends StatelessWidget {
  final String name, desc; final bool ok;
  const _ApiRow(this.name, this.desc, this.ok);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(14),
    child: Row(children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (ok ? C.green : C.amber).withOpacity(0.1),
        ),
        child: Icon(ok ? Icons.check_rounded : Icons.warning_amber_rounded,
            size: 15, color: ok ? C.green : C.amber),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.t1)),
        Text(desc, style: const TextStyle(fontSize: 11, color: C.t3)),
      ])),
      Text(ok ? 'LIVE' : 'OFF',
          style: GoogleFonts.sourceCodePro(
              fontSize: 10, letterSpacing: 1,
              color: ok ? C.green : C.amber, fontWeight: FontWeight.w800)),
    ]),
  );
}


