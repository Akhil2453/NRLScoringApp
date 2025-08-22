import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/login_page.dart';
import 'screens/referee_home_page.dart';
import 'screens/scoring_page.dart';
import 'screens/match_summary_page.dart';

void main() {
  runApp(NRLScoringApp());
}

class NRLScoringApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NRL Scoring App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: AuthCheck(),

      // Important: return Route objects, not Widgets directly
      onGenerateRoute: (settings) {
        if (settings.name == '/home') {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            builder: (_) => RefereeHomePage(
              username: args['username'] as String? ?? '',
              // role: args['role'], // if needed
            ),
          );
        }

        if (settings.name == '/score') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) => ScoringPage(
              matchId: args['matchId'] as int,
              alliance: (args['alliance'] as String).toLowerCase(), // 'red'|'blue'
            ),
          );
        }

        // NEW: Match summary route
        if (settings.name == '/summary') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) => MatchSummaryPage(
              matchId: args['matchId'] as int,
            ),
          );
        }

        // Fallback
        return MaterialPageRoute(builder: (_) => LoginPage());
      },
    );
  }
}

class AuthCheck extends StatefulWidget {
  @override
  _AuthCheckState createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  bool _isLoading = true;
  bool _loggedIn = false;
  late String _username;
  late String _role;

  @override
  void initState() {
    super.initState();
    checkLoginStatus();
  }

  Future<void> checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    _username = prefs.getString('username') ?? '';
    _role = prefs.getString('role') ?? '';

    setState(() {
      _loggedIn = token != null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return _loggedIn
        ? RefereeHomePage(username: _username)
        : LoginPage();
  }
}
