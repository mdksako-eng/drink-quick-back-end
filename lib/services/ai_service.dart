// services/ai_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class AIService {
  final String apiKey;
  final String baseUrl = 'https://api.openai.com/v1/chat/completions';

  AIService({required this.apiKey});

  Future<String> getChatResponse(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        throw Exception('Failed to get AI response');
      }
    } catch (e) {
      throw Exception('AI Service error: $e');
    }
  }

  Future<int> calculateBAC({
    required int weight,
    required String gender,
    required List<Map<String, dynamic>> drinks,
    required int hours,
  }) async {
    // Fix the type conversion error
    double totalAlcohol = 0;

    for (var drink in drinks) {
      final volume = drink['volume'] as int;
      final abv = drink['abv'] as double;
      totalAlcohol += (volume * abv / 100) * 0.789;
    }

    double r = gender.toLowerCase() == 'male' ? 0.68 : 0.55;
    int bacResult =
        ((totalAlcohol * 100) / (weight * r) - (0.015 * hours)).round();

    return bacResult < 0 ? 0 : bacResult;
  }
}
