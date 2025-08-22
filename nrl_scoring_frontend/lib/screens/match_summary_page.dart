import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MatchSummaryPage extends StatefulWidget {
  final int matchId;
  const MatchSummaryPage({Key? key, required this.matchId}) : super(key: key);

  @override
  State<MatchSummaryPage> createState() => _MatchSummaryPageState();
}

class _MatchSummaryPageState extends State<MatchSummaryPage> {
  final String baseUrl = 'http://localhost:5000';
  bool _loading = true;
  Map<String, dynamic>? summary; // whole JSON

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/match/${widget.matchId}/summary'));
      if (res.statusCode == 200) {
        setState(() {
          summary = jsonDecode(res.body) as Map<String, dynamic>;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        _snack('Failed to load summary (${res.statusCode}).');
      }
    } catch (e) {
      setState(() => _loading = false);
      _snack('Network error.');
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---- Golden points fallback (if backend didn’t include golden_points) ----
  int _computeGoldenPointsFallback(dynamic stackRaw) {
    try {
      if (stackRaw == null) return 0;
      final grid = (stackRaw is String) ? jsonDecode(stackRaw) : stackRaw;
      if (grid is! List || grid.isEmpty) return 0;
      final rows = grid.length;
      final cols = (grid[0] as List).length;

      int colHeight(int c) {
        int h = 0;
        for (int r = rows - 1; r >= 0; r--) {
          final row = grid[r] as List;
          final cell = (c < row.length) ? (row[c] == true) : false;
          if (cell) {
            h++;
          } else {
            break;
          }
        }
        return h;
      }

      int total = 0;
      for (int c = 0; c < cols; c++) {
        final h = colHeight(c);
        total += 10 * h + 5 * (h * (h - 1) ~/ 2);
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  // ---- Helpers to get breakdown & points per category ----
  Map<String, dynamic> _bd(String side) {
    final s = summary;
    if (s == null) return {};
    return ((s['score']?[side] ?? {})['score_breakdown'] ?? {}) as Map<String, dynamic>;
  }

  int _total(String side) {
    final s = summary;
    if (s == null) return 0;
    return (s['score']?[side]?['total_score'] ?? 0) as int;
  }

  int _goldenPoints(String side) {
    final bd = _bd(side);
    return (bd['golden_points'] ??
        _computeGoldenPointsFallback(bd['golden_charge_stack'])) as int;
  }

  int _capturePoints(String side) => ((_bd(side)['captured_charge'] ?? 0) as int) * 10;
  int _chargePoints(String side) => ((_bd(side)['alliance_charge'] ?? 0) as int) * 5; // base-only preview
  int _chargeStationPoints(String side) {
    final bd = _bd(side);
    final dock = (bd['docked'] ?? 0) as int;
    final engage = (bd['engaged'] ?? 0) as int;
    final fp = (bd['full_parking'] ?? 0) as int;
    final pp = (bd['partial_parking'] ?? 0) as int;
    return dock * 15 + engage * 10 + fp * 10 + pp * 5;
  }

  int _penaltyPoints(String side) {
    final bd = _bd(side);
    final minor = (bd['minor_penalties'] ?? 0) as int;
    final major = (bd['major_penalties'] ?? 0) as int;
    return -(minor * 5 + major * 15);
  }

  // ---- Quick Ranking Points (RP) rules — tweak as needed ----
  // WIN RP: winner 2, loser 0, tie 1 each
  // SC RP: +1 if captured_charge >= 3
  // ChSt RP: +1 if docked + engaged >= 2
  Map<String, int> _rp(String side) {
    final redTotal = _total('red');
    final blueTotal = _total('blue');
    final bd = _bd(side);
    final other = side == 'red' ? 'blue' : 'red';
    final myTotal = side == 'red' ? redTotal : blueTotal;
    final othTotal = side == 'red' ? blueTotal : redTotal;

    int winRP = 0;
    if (myTotal > othTotal) winRP = 2;
    else if (myTotal == othTotal) winRP = 1;

    final captured = (bd['captured_charge'] ?? 0) as int;
    final docked = (bd['docked'] ?? 0) as int;
    final engaged = (bd['engaged'] ?? 0) as int;

    final scRP = captured >= 3 ? 1 : 0;                 // threshold tweakable
    final chstRP = (docked + engaged) >= 2 ? 1 : 0;     // threshold tweakable
    return {'win': winRP, 'sc': scRP, 'chst': chstRP};
  }

  // ---- Head Ref verification (finalise) ----
  Future<void> _verifyHeadRef() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Head Referee Verification'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Head Referee ID',
            hintText: 'Enter numeric user id',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Verify')),
        ],
      ),
    );

    if (ok != true) return;
    final idText = controller.text.trim();
    if (idText.isEmpty) {
      _snack('Please enter Head Referee ID');
      return;
    }

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/finalise_score'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'match_id': widget.matchId, 'confirmed_by': int.tryParse(idText)}),
      );
      if (res.statusCode == 200) {
        _snack('Scores finalised.');
        _load(); // refresh to show finalised flag if needed
      } else {
        _snack('Finalise failed (${res.statusCode})');
      }
    } catch (e) {
      _snack('Network error.');
    }
  }

  // ---- End match: return to home (adjust to your nav flow) ----
  void _endMatch() {
    Navigator.popUntil(context, (route) => route.isFirst);
    // Or: Navigator.pushReplacementNamed(context, '/home', arguments: {...});
  }

  // ---- UI building blocks ----
  Widget _scorePillar({required String label, required int score, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              )),
          const SizedBox(height: 6),
          Text('$score',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 34,
              )),
        ],
      ),
    );
  }

  Widget _rpSide(String side, Color baseColor) {
    final rp = _rp(side);
    final teams = (summary?['teams']?[side] as List?)?.cast<dynamic>().map((e) => '$e').toList() ?? [];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: baseColor.withOpacity(0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _rpTag('WIN RP', rp['win'] ?? 0, baseColor),
              const SizedBox(width: 8),
              _rpTag('SC RP', rp['sc'] ?? 0, baseColor),
              const SizedBox(width: 8),
              _rpTag('ChSt RP', rp['chst'] ?? 0, baseColor),
            ],
          ),
          const SizedBox(height: 12),
          _teamRankRow('Team Number', 'Rank', baseColor),
          const SizedBox(height: 6),
          for (final t in teams.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _teamRankRow(t, '—', baseColor, filled: true),
            ),
        ],
      ),
    );
  }

  Widget _rpTag(String label, int value, Color color) {
    return Expanded(
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        alignment: Alignment.center,
        child: Text('$label\n${value.toString().padLeft(2, '0')}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color.darken(),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            )),
      ),
    );
  }

  Widget _teamRankRow(String team, String rank, Color color, {bool filled = false}) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 38,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: filled ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withOpacity(0.35)),
            ),
            child: Text(team, style: TextStyle(fontWeight: FontWeight.w600, color: color.darken())),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 54,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Text(rank, style: TextStyle(fontWeight: FontWeight.w700, color: color.darken())),
        ),
      ],
    );
  }

  Widget _centerBreakdown() {
    // Build five rows: CAPTURE, CHARGE, GOLDEN CHARGE, CHARGE STATION, PENALTIES
    Widget row(String title, int redVal, int blueVal) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: Text(redVal.toString().padLeft(2, '0'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
            ),
            SizedBox(
              width: 42,
              child: Text(blueVal.toString().padLeft(2, '0'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }

    final captureR = _capturePoints('red');
    final captureB = _capturePoints('blue');
    final chargeR = _chargePoints('red');
    final chargeB = _chargePoints('blue');
    final goldenR = _goldenPoints('red');
    final goldenB = _goldenPoints('blue');
    final stationR = _chargeStationPoints('red');
    final stationB = _chargeStationPoints('blue');
    final penaltyR = _penaltyPoints('red');
    final penaltyB = _penaltyPoints('blue');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          row('CAPTURE', captureR, captureB),
          row('CHARGE', chargeR, chargeB),
          row('GOLDEN CHARGE', goldenR, goldenB),
          row('CHARGE STATION', stationR, stationB),
          row('PENALTIES', penaltyR, penaltyB),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = summary;

    return Scaffold(
      appBar: AppBar(
        title: Text(data == null
            ? 'Match Summary Page'
            : 'Match Summary Page'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : data == null
              ? const Center(child: Text('No data'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header line: Match Number | Arena | Alliance
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: const [
                                Text('Match Number', style: TextStyle(fontWeight: FontWeight.w700)),
                                Text('Arena', style: TextStyle(fontWeight: FontWeight.w700)),
                                Text('Alliance', style: TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Top big RED | BLUE score bars
                          LayoutBuilder(
                            builder: (context, c) {
                              return Row(
                                children: [
                                  Expanded(
                                    child: _scorePillar(
                                      label: 'RED',
                                      score: _total('red'),
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _scorePillar(
                                      label: 'BLUE',
                                      score: _total('blue'),
                                      color: Colors.lightBlue.shade400,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),

                          const SizedBox(height: 12),

                          // Lower tri-panel: RED RP stats | center breakdown | BLUE RP stats
                          LayoutBuilder(
                            builder: (context, c) {
                              final wide = c.maxWidth >= 860;
                              final redPanel = _rpSide('red', Colors.red.shade700);
                              final bluePanel = _rpSide('blue', Colors.lightBlue.shade400);
                              final centerPanel = _centerBreakdown();

                              return wide
                                  ? Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: redPanel),
                                        const SizedBox(width: 12),
                                        Expanded(child: centerPanel),
                                        const SizedBox(width: 12),
                                        Expanded(child: bluePanel),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        redPanel,
                                        const SizedBox(height: 12),
                                        centerPanel,
                                        const SizedBox(height: 12),
                                        bluePanel,
                                      ],
                                    );
                            },
                          ),

                          const SizedBox(height: 18),

                          // Head Ref verification and End Match
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: _verifyHeadRef,
                                child: const Text(
                                  'Verification from Head Referee',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: 240,
                                child: ElevatedButton(
                                  onPressed: _endMatch,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Text('End Match', style: TextStyle(fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}

// ---- Small extension for slightly darker text on tinted panels ----
extension _ColorShade on Color {
  Color darken([double amount = .22]) {
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}
