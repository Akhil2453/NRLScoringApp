import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/login_page.dart';
import 'screens/home_page.dart';

void main() {
  runApp(NRLApp());
}

class NRLApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NRL Scoring App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: AuthCheck(),
    );
  }
}

// Widget that checks if user is already logged in
class AuthCheck extends StatefulWidget {
  @override
  _AuthCheckState createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
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
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NRL Scoring',
      home: _loggedIn
          ? HomePage(username: _username, role: _role)
          : LoginPage(),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return _loggedIn
    ? HomePage(username: _username ?? '', role: _role ?? '')
    : LoginPage();
  }
}
