import 'package:flutter/material.dart';
import 'match_list_page.dart'; // To be created
import 'inspection_page.dart'; // For admin
import 'scoreboard_live_page.dart'; // For everyone
import 'match_list_page.dart';
import 'inspection_page.dart';
import 'scoreboard_live_page.dart';


class HomePage extends StatelessWidget {
  final String username;
  final String role;

  const HomePage({required this.username, required this.role, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('NRL Scoring App - Welcome $username'),
      ),
      body: ListView(
        padding: EdgeInsets.all(16.0),
        children: [
          if (role == 'referee' || role == 'head_referee') ...[
            ElevatedButton(
              child: Text('📋 View Scheduled Matches'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => MatchListPage()),
                );
              },
            ),
          ],
          if (role == 'head_referee') ...[
            ElevatedButton(
              child: Text('✔️ Finalise Scores'),
              onPressed: () {
                // Placeholder for future implementation
              },
            ),
          ],
          if (role == 'admin') ...[
            ElevatedButton(
              child: Text('🛠️ Update Inspection Status'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => InspectionPage()),
                );
              },
            ),
            ElevatedButton(
              child: Text('📂 Upload Match Schedule'),
              onPressed: () {
                // Placeholder for upload CSV logic
              },
            ),
          ],
          ElevatedButton(
            child: Text('📊 View Live Scoreboard'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ScoreboardLivePage()),
              );
            },
          ),
          SizedBox(height: 20),
          ElevatedButton(
            child: Text('🔒 Logout'),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}