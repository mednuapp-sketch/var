import 'package:dio/dio.dart';

class AiTipsService {
  // Injected via --dart-define=GEMINI_API_KEY=... at build time.
  // Restrict this key in Google Cloud Console to package com.mednu.mednu + release SHA-1.
  static const String _apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: 'AIzaSyAUK46gRgthH-vxhZkFP8SM4UqSmpRbJsE',
  );
  static const String _apiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  // Per-category cache: category → (tip text, fetched at)
  static final Map<String, (String, DateTime)> _cache = {};
  static const _cacheTtl = Duration(hours: 1);

  // Fallback tips shown when API is unavailable
  static const Map<String, String> _fallbackTips = {
    'All':
        'Stay hydrated by drinking at least 8 glasses of water daily. Combine this with a 30-minute walk and 7–8 hours of sleep for noticeable improvements in energy and mood. Always consult a doctor for personalised medical advice.',
    'Nutrition':
        'Include a rainbow of fruits and vegetables in every meal to cover a wide range of vitamins and minerals. Choose whole grains over refined carbs, and limit added sugars and ultra-processed foods. Small, consistent changes to your diet have the biggest long-term impact.',
    'Mental Health':
        'Practise 10 minutes of mindfulness or deep breathing daily to lower stress hormones. Staying socially connected and getting regular exercise are among the most evidence-backed ways to support mental well-being. Reach out to a professional if feelings of anxiety or low mood persist.',
    'Heart':
        'A heart-healthy lifestyle includes at least 150 minutes of moderate exercise per week, a diet low in saturated fats and sodium, and not smoking. Regular blood-pressure and cholesterol checks can catch problems early. Even losing 5–10 % of body weight can significantly reduce cardiovascular risk.',
    'Diabetes':
        'Eat at regular intervals and choose low-glycaemic foods like vegetables, legumes, and whole grains to keep blood sugar stable. Aim for 30 minutes of physical activity most days — even a brisk walk helps improve insulin sensitivity. Monitor your levels as advised by your doctor and never skip medications.',
    'Women':
        'Annual gynaecological check-ups are key for early detection of conditions like PCOS, cervical cancer, and osteoporosis. Adequate calcium (1 000 mg/day) and vitamin D support bone health, especially after 30. Track your cycle and discuss any irregular symptoms with your doctor promptly.',
    'Child Care':
        'Follow the national immunisation schedule to protect your child against serious preventable diseases. Encourage at least 60 minutes of active play daily and limit screen time, especially for children under five. Regular paediatric visits help monitor growth milestones and catch developmental concerns early.',
  };

  static const String _systemPrompt =
      'You are a helpful health education assistant for MedNU, an Indian healthcare app. '
      'Provide accurate, easy-to-understand health information in 2-4 sentences. '
      'Be warm, encouraging, and practical. '
      'Always remind users to consult a doctor for personal medical advice. '
      'Do not diagnose conditions or prescribe treatments.';

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  Future<String> getDailyTip(String category) async {
    final cached = _cache[category];
    if (cached != null && DateTime.now().difference(cached.$2) < _cacheTtl) {
      return cached.$1;
    }

    final prompt = category == 'All'
        ? 'Give me one practical, actionable health tip for today. Be specific, concise (2-3 sentences), and easy to follow for a general audience.'
        : 'Give me one practical, actionable health tip about $category. Be specific, concise (2-3 sentences), and easy to follow.';

    try {
      final result = await _callApi(prompt);
      _cache[category] = (result, DateTime.now());
      return result;
    } catch (_) {
      return _fallbackTips[category] ?? _fallbackTips['All']!;
    }
  }

  Future<String> askQuestion(String question) async {
    try {
      return await _callApi(question);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 429) {
        return 'Our health assistant is busy right now. Please wait a moment and try again.';
      }
      if (status == 403 || status == 400) {
        return 'Health assistant is temporarily unavailable. Please try again later.';
      }
      return 'Unable to connect right now. Please check your internet connection and try again.';
    } catch (_) {
      return 'Something went wrong. Please try again.';
    }
  }

  Future<String> _callApi(String userMessage) async {
    final response = await _dio.post(
      '$_apiUrl?key=$_apiKey',
      data: {
        'system_instruction': {
          'parts': [
            {'text': _systemPrompt}
          ]
        },
        'contents': [
          {
            'parts': [
              {'text': userMessage}
            ]
          }
        ],
        'generationConfig': {
          'maxOutputTokens': 350,
        },
      },
    );
    final data = response.data;
    if (data is! Map) throw Exception('Unexpected API response format');
    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      // Gemini may return a promptFeedback block with BLOCK_REASON instead of candidates.
      final reason = (data['promptFeedback'] as Map?)?['blockReason'] as String?;
      throw Exception(reason != null
          ? 'Content blocked: $reason'
          : 'No candidates in API response');
    }
    final first = candidates.first;
    if (first is! Map) throw Exception('Malformed candidate');
    final content = first['content'];
    if (content is! Map) throw Exception('Malformed content');
    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) throw Exception('Empty parts in response');
    final text = (parts.first as Map?)?['text'];
    if (text is! String) throw Exception('No text in response');
    return text;
  }

  static String fallbackFor(String category) =>
      _fallbackTips[category] ?? _fallbackTips['All']!;
}
