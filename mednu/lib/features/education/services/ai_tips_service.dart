import 'package:dio/dio.dart';

class AiTipsService {
  // Get a free key at: https://aistudio.google.com/app/apikey
  static const String _apiKey = 'AIzaSyAUK46gRgthH-vxhZkFP8SM4UqSmpRbJsE';
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
      // Extract Gemini's error message for easier debugging
      final geminiError = e.response?.data?['error']?['message'] as String? ?? e.message ?? 'unknown';
      if (status == 429) {
        return "Rate limit hit (429): $geminiError\n\nPlease wait a minute and try again.";
      }
      if (status == 400) {
        return "Bad request (400): $geminiError";
      }
      if (status == 403) {
        return "API key error (403): $geminiError";
      }
      return "Network error ($status): $geminiError";
    } catch (e) {
      return "Unexpected error: $e";
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
    final candidates = response.data['candidates'] as List<dynamic>;
    final content = (candidates.first as Map<String, dynamic>)['content'];
    final parts = (content as Map<String, dynamic>)['parts'] as List<dynamic>;
    return (parts.first as Map<String, dynamic>)['text'] as String;
  }

  static String fallbackFor(String category) =>
      _fallbackTips[category] ?? _fallbackTips['All']!;
}
