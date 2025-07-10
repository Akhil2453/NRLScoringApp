import 'package:flutter/material.dart';

class RefereeHomePage extends StatefulWidget {
  final String username;

  const RefereeHomePage({required this.username, Key? key}) : super(key: key);

  @override
  _RefereeHomePageState createState() => _RefereeHomePageState();
}

class _RefereeHomePageState extends State<RefereeHomePage> {
  String? selectedArena;
  String? selectedAlliance;
  int? selectedMatchId;
  final TextEditingController _matchNumberController = TextEditingController();

  void _startMatch() {
    if (selectedArena == null || selectedAlliance == null || _matchNumberController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all fields')),
      );
      return;
    }

    // Navigate to the score entry page
    // Navigator.pushNamed(context, '/score_entry', arguments: {
    //   'referee': widget.username,
    //   'arena': selectedArena,
    //   'match_number': int.parse(_matchNumberController.text),
    //   'alliance': selectedAlliance
    // });
    Navigator.pushNamed(
        context,
        '/score',
        arguments: {
            'matchId': selectedMatchId,
            'alliance': selectedAlliance,
        },
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NRL Scoring App'),
        centerTitle: true,
      ),
      body: Center(
        child: SizedBox(
          width: 400,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLabelField('Referee Name'),
                _buildReadOnlyBox(widget.username),
                const SizedBox(height: 20),
                _buildLabelField('Arena Selection'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['Alpha', 'Bravo'].map((arena) {
                    return ElevatedButton(
                      onPressed: () {
                        if (selectedMatchId != null && selectedAlliance != null) {
                        Navigator.pushNamed(
                            context,
                            '/score',
                            arguments: {
                            'matchId': selectedMatchId,
                            'alliance': selectedAlliance,
                            },
                        );
                        }
                    },
                    child: Text(arena),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                _buildLabelField('Match Number'),
                DropdownButtonFormField<int>(
                value: selectedMatchId,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Select Match Number',
                ),
                items: [1, 2, 3, 4, 5, 6].map((int matchId) {
                    return DropdownMenuItem<int>(
                    value: matchId,
                    child: Text('Match $matchId'),
                    );
                }).toList(),
                onChanged: (int? newValue) {
                    setState(() {
                    selectedMatchId = newValue;
                    });
                },
                ),

                const SizedBox(height: 20),
                _buildLabelField('Alliance'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['Red', 'Blue'].map((alliance) {
                    return ElevatedButton(
                      onPressed: () => setState(() => selectedAlliance = alliance.toLowerCase()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: alliance == 'Red'
                            ? (selectedAlliance == 'red' ? Colors.red : Colors.red.shade200)
                            : (selectedAlliance == 'blue' ? Colors.blue : Colors.blue.shade200),
                        foregroundColor: Colors.white,
                      ),
                      child: Text(alliance),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: _startMatch,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  child: const Text('Start Match'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabelField(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }

  Widget _buildReadOnlyBox(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 10),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text, style: const TextStyle(fontSize: 16)),
    );
  }
}
