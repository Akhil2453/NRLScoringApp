import 'dart:convert';
import 'package:http/http.dart' as http;

class Api {
  // Change this if your backend is on a different host/port
  static const String base = 'http://localhost:5000';

  static Future<Map<String, dynamic>> fetchMatchSummary(int matchId) async {
    final res = await http.get(Uri.parse('$base/match/$matchId/summary'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load summary: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> finaliseScore({
    required int matchId,
    required int confirmedBy, // Head Referee user id
  }) async {
    final res = await http.post(
      Uri.parse('$base/finalise_score'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'match_id': matchId,
        'confirmed_by': confirmedBy,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Finalisation failed: ${res.body}');
    }
  }
}
