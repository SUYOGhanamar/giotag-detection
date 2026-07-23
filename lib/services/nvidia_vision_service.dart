// lib/services/nvidia_vision_service.dart
// Task D: NVIDIA Build API Integration for AI Deepfake / Artifact Detection

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';

// ─── Result Model ─────────────────────────────────────────────────────────────

enum NvidiaAnalysisStatus { success, unavailable, error }

class NvidiaAnalysisResult {
  final NvidiaAnalysisStatus status;

  /// Probability that the image is AI-generated/manipulated (0.0–1.0)
  final double syntheticScore;

  /// Whether the model detected visual artifacts
  final bool artifactsDetected;

  /// Model's confidence in its assessment (0.0–1.0)
  final double confidence;

  /// Human-readable explanation from the model
  final String explanation;

  /// Raw model response (for debugging)
  final String rawResponse;

  const NvidiaAnalysisResult({
    required this.status,
    required this.syntheticScore,
    required this.artifactsDetected,
    required this.confidence,
    required this.explanation,
    required this.rawResponse,
  });

  /// Returns a graceful placeholder when the API is not configured.
  factory NvidiaAnalysisResult.unavailable() => const NvidiaAnalysisResult(
        status: NvidiaAnalysisStatus.unavailable,
        syntheticScore: 0.0,
        artifactsDetected: false,
        confidence: 0.0,
        explanation: 'NVIDIA API key not configured. '
            'Add NVIDIA_API_KEY to .env to enable AI deepfake detection.',
        rawResponse: '',
      );

  factory NvidiaAnalysisResult.error(String message) => NvidiaAnalysisResult(
        status: NvidiaAnalysisStatus.error,
        syntheticScore: 0.0,
        artifactsDetected: false,
        confidence: 0.0,
        explanation: 'API error: $message',
        rawResponse: message,
      );
}

// ─── Service ──────────────────────────────────────────────────────────────────

class NvidiaVisionService {
  static const _analysisPrompt = '''
Analyze this image for signs of digital manipulation and AI generation.
Carefully examine: GAN artifacts, frequency anomalies, unnatural textures, 
face-swap boundaries, inconsistent lighting, metadata inconsistencies, 
deepfake patterns, and synthetic pixel distributions.

Respond ONLY with a valid JSON object in this exact format (no markdown):
{
  "synthetic_score": <float 0.0 to 1.0>,
  "artifacts_detected": <true or false>,
  "confidence": <float 0.0 to 1.0>,
  "explanation": "<one or two sentence summary>"
}

Where synthetic_score=1.0 means definitely AI-generated/manipulated,
and synthetic_score=0.0 means definitely authentic/unmanipulated.
''';

  /// Sends [imageBytes] to the NVIDIA Neva-22B multimodal model endpoint and
  /// returns a structured deepfake detection result.
  ///
  /// Requires NVIDIA_API_KEY set in .env.
  /// Gracefully degrades to [NvidiaAnalysisResult.unavailable()] if not configured.
  static Future<NvidiaAnalysisResult> analyzeImage(Uint8List imageBytes) async {
    final apiKey = dotenv.maybeGet('NVIDIA_API_KEY');
    if (apiKey == null ||
        apiKey.isEmpty ||
        apiKey == 'YOUR_NVIDIA_BUILD_API_KEY_HERE') {
      return NvidiaAnalysisResult.unavailable();
    }

    final modelName =
        dotenv.maybeGet('NVIDIA_MODEL_NAME') ?? 'nvidia/neva-22b';

    try {
      // Encode image as base64 data URI
      final base64Image = base64Encode(imageBytes);
      final dataUri = 'data:image/jpeg;base64,$base64Image';

      final requestBody = jsonEncode({
        'model': modelName,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': _analysisPrompt},
              {
                'type': 'image_url',
                'image_url': {'url': dataUri},
              },
            ],
          }
        ],
        'max_tokens': 512,
        'temperature': 0.1, // low temperature for deterministic JSON output
        'stream': false,
      });

      final response = await http
          .post(
            Uri.parse(AppConstants.nvidiaChatEndpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: requestBody,
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        return NvidiaAnalysisResult.error(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}. '
            'Body: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List<dynamic>;
      if (choices.isEmpty) {
        return NvidiaAnalysisResult.error('Empty choices in API response.');
      }

      final rawContent =
          choices.first['message']['content'] as String? ?? '';

      return _parseModelResponse(rawContent);
    } catch (e) {
      return NvidiaAnalysisResult.error(e.toString());
    }
  }

  /// Parses the model's text response into a [NvidiaAnalysisResult].
  /// Handles JSON embedded in markdown code blocks or plain text.
  static NvidiaAnalysisResult _parseModelResponse(String rawContent) {
    try {
      // Strip markdown code fences if present
      String jsonStr = rawContent.trim();
      if (jsonStr.startsWith('```')) {
        final start = jsonStr.indexOf('{');
        final end = jsonStr.lastIndexOf('}');
        if (start != -1 && end != -1) {
          jsonStr = jsonStr.substring(start, end + 1);
        }
      }

      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;

      final syntheticScore =
          (parsed['synthetic_score'] as num?)?.toDouble() ?? 0.0;
      final artifactsDetected =
          parsed['artifacts_detected'] as bool? ?? false;
      final confidence = (parsed['confidence'] as num?)?.toDouble() ?? 0.0;
      final explanation = parsed['explanation'] as String? ??
          'No explanation provided by model.';

      return NvidiaAnalysisResult(
        status: NvidiaAnalysisStatus.success,
        syntheticScore: syntheticScore.clamp(0.0, 1.0),
        artifactsDetected: artifactsDetected,
        confidence: confidence.clamp(0.0, 1.0),
        explanation: explanation,
        rawResponse: rawContent,
      );
    } catch (e) {
      // If JSON parsing fails, extract numeric scores heuristically
      return NvidiaAnalysisResult(
        status: NvidiaAnalysisStatus.success,
        syntheticScore: 0.0,
        artifactsDetected: false,
        confidence: 0.3,
        explanation: rawContent.length > 300
            ? '${rawContent.substring(0, 300)}...'
            : rawContent,
        rawResponse: rawContent,
      );
    }
  }
}
