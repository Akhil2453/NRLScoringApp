import 'package:flutter/material.dart';

class ScoringPage extends StatelessWidget {
  const ScoringPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Extract arguments from route
    final Map<String, dynamic> args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    final int matchId = args['matchId'] ?? -1;
    final String alliance = args['alliance'] ?? 'unknown';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Match Scoring'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildMatchInfo(matchId, alliance),
            const SizedBox(height: 20),

            // TODO: Add actual scoring widgets below
            const Text("Scoring Interface Coming Soon..."),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchInfo(int matchId, String alliance) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _infoTile("Match ID", matchId.toString()),
        _infoTile("Alliance", alliance.toUpperCase()),
      ],
    );
  }

  Widget _infoTile(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black26),
      ),
      child: Column(
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 18, color: Colors.deepPurple)),
        ],
      ),
    );
  }
}
