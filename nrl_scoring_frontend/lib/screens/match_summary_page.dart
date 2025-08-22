import 'package:flutter/material.dart';
import '../services/api.dart';

class MatchSummaryPage extends StatefulWidget {
  final int matchId;
  final String? arena; // optional in case you pass along
  final String? alliance; // optional context

  const MatchSummaryPage({
    Key? key,
    required this.matchId,
    this.arena,
    this.alliance,
  }) : super(key: key);

  @override
  State<MatchSummaryPage> createState() => _MatchSummaryPageState();
}

class _MatchSummaryPageState extends State<MatchSummaryPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Api.fetchMatchSummary(widget.matchId);
      setState(() {
        summary = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int _total(String side) {
    final s = summary?['score']?[side];
    if (s == null) return 0;
    return (s['total_score'] ?? 0) as int;
  }

  String _listTeams(String side) {
    final teams = summary?['teams']?[side] as List<dynamic>? ?? [];
    return teams.join('  ');
  }

  Widget _scoreRow(String label, int left, int right) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(.1)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              left.toString().padLeft(2, '0'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              textAlign: TextAlign.left,
            ),
          ),
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              right.toString().padLeft(2, '0'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Map<String, int> _breakdown(String side) {
    final b = (summary?['score']?[side]?['score_breakdown'] ?? {}) as Map<String, dynamic>;
    int getI(String k) => (b[k] ?? 0) is int ? b[k] as int : 0;
    return {
      'CAPTURE': getI('captured_charge'),
      'CHARGE': getI('alliance_charge'),
      'GOLDEN CHARGE': (b['golden_charge_stack'] ?? '').toString().isEmpty ? 0 : 0, // placeholder if you later compute
      'CHARGE STATION': getI('docked') + getI('engaged') + getI('full_parking') + getI('partial_parking'),
      'PENALTIES': -(getI('minor_penalties') * 5 + getI('major_penalties') * 15),
    };
  }

  Future<void> _confirmAndFinalise() async {
    // You likely have the Head Referee user id from login; for now ask.
    int? headRefId;
    await showDialog(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Verification from Head Referee'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Enter Head Referee User ID'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                headRefId = int.tryParse(controller.text.trim());
                Navigator.pop(ctx);
              },
              child: const Text('Verify'),
            ),
          ],
        );
      },
    );
    if (headRefId == null) return;

    try {
      await Api.finaliseScore(matchId: widget.matchId, confirmedBy: headRefId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Match finalised.')),
      );
      // Refresh to show finalised flag
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Finalisation failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInfo = summary == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Match ${summary!['match_number']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 20),
                Text('Arena ${summary!['arena']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Match Summary'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      topInfo,
                      // Totals header
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              color: Colors.red.shade400,
                              child: Column(
                                children: [
                                  const Text('RED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                                  Text(
                                    _total('red').toString(),
                                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              color: Colors.lightBlue.shade400,
                              child: Column(
                                children: [
                                  const Text('BLUE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                                  Text(
                                    _total('blue').toString(),
                                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Breakdown center strip like your mock
                      Expanded(
                        child: Container(
                          color: Colors.black87,
                          child: Column(
                            children: [
                              const SizedBox(height: 6),
                              _scoreRow('CAPTURE', _breakdown('red')['CAPTURE']!, _breakdown('blue')['CAPTURE']!),
                              _scoreRow('CHARGE', _breakdown('red')['CHARGE']!, _breakdown('blue')['CHARGE']!),
                              _scoreRow('GOLDEN CHARGE', _breakdown('red')['GOLDEN CHARGE']!, _breakdown('blue')['GOLDEN CHARGE']!),
                              _scoreRow('CHARGE STATION', _breakdown('red')['CHARGE STATION']!, _breakdown('blue')['CHARGE STATION']!),
                              _scoreRow('PENALTIES', _breakdown('red')['PENALTIES']!, _breakdown('blue')['PENALTIES']!),
                              const Spacer(),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Red Alliance Teams', style: TextStyle(color: Colors.white70)),
                                          Text(_listTeams('red'),
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          const Text('Blue Alliance Teams', style: TextStyle(color: Colors.white70)),
                                          Text(_listTeams('blue'),
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Verification + End buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton(
                            onPressed: _confirmAndFinalise,
                            child: const Text('Verification from Head Referee'),
                          ),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                            child: const Text('End Match'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }
}
