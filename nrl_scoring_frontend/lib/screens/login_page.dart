import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';

    Future<void> login() async {
    setState(() {
        _isLoading = true;
        _errorMessage = '';
    });

    final response = await http.post(
        Uri.parse('http://localhost:5000/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
        'username': _usernameController.text,
        'password': _passwordController.text,
        }),
    );

    setState(() {
        _isLoading = false;
    });

    if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String username = _usernameController.text;
        final String role = data['role'];

        Navigator.pushReplacementNamed(
        context,
        "/home",
        arguments: {
            'username': username,
            'role': role
        },
        );
    } else {
        setState(() {
        _errorMessage = 'Invalid credentials. Please try again.';
        });
    }
    }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SizedBox(
          width: 350,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'NRL Scoring App Login',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : login,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Login'),
              ),
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
