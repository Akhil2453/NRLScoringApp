import 'package:flutter/material.dart';

class ScoringPage extends StatefulWidget {
  final int matchId;
  final String alliance; // 'red' or 'blue'
  const ScoringPage({required this.matchId, required this.alliance, Key? key}) : super(key: key);

  @override
  State<ScoringPage> createState() => _ScoringPageState();
}

class _ScoringPageState extends State<ScoringPage> {
  int totalScore = 0;
  int chargeScore = 0;
  int capturedCharge = 0;

  void incrementScore(int points) {
    setState(() {
      totalScore += points;
    });
  }

  void decrementScore(int points) {
    setState(() {
      if (totalScore >= points) totalScore -= points;
    });
  }

  void toggleCapturedCharge() {
    setState(() {
      capturedCharge = capturedCharge == 0 ? 1 : 0;
    });
  }

  void submitScore() {
    // TODO: Call Flask API to submit final score
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Score submitted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scoring - Match ${widget.matchId} (${widget.alliance.toUpperCase()})'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Total Score: $totalScore", style: TextStyle(fontSize: 24)),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: () => incrementScore(5),
              child: const Text('Add 5 Points'),
            ),
            ElevatedButton(
              onPressed: () => decrementScore(5),
              child: const Text('Subtract 5 Points'),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Captured Charge:'),
                Switch(
                  value: capturedCharge == 1,
                  onChanged: (value) => toggleCapturedCharge(),
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: submitScore,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Submit Score'),
            ),
          ],
        ),
      ),
    );
  }
}
