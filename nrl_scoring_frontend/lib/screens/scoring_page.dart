import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// ScoringPage
/// Expects to be navigated with:
/// Navigator.pushNamed(context, '/score', arguments: {
///   'matchId': <int>,
///   'alliance': 'red' | 'blue',
/// });
class ScoringPage extends StatefulWidget {
  final int matchId;
  final String alliance;

  const ScoringPage({
    Key? key,
    required this.matchId,
    required this.alliance,
  }) : super(key: key);

  @override
  State<ScoringPage> createState() => _ScoringPageState();
}

class _ScoringPageState extends State<ScoringPage> {
  // --- API base ---
  final String baseUrl = 'http://localhost:5000';

  // --- Match/Alliance info pulled from backend ---
  int? matchNumber;
  List<String> redTeams = [];
  List<String> blueTeams = [];

  // --- Scoring state ---
  int allianceCharge = 0;
  int capturedCharge = 0;
  int minorPenalties = 0;
  int majorPenalties = 0;
  int docked = 0;
  int engaged = 0;
  bool fullParking = false;
  bool partialParking = false;

  // Golden charge 4x4 grid (false = empty, true = placed)
  final int goldRows = 4;
  final int goldCols = 4;
  late List<List<bool>> goldenGrid;

  // --- Supercharge (15 seconds) ---
  bool superchargeActive = false;
  int superchargeSecondsLeft = 0;
  Timer? superchargeTimer;

  // --- End-of-match captured negative adjustments allowed ---
  bool matchEnded = false;

  // --- UI helpers ---
  bool _loadingDetails = true;
  bool _submitting = false;

  // --- Golden constants ---
static const int kGoldenBase = 10;        // 10 per block
static const int kGoldenStackBonus = 5;   // +5 per level above bottom

/// Returns contiguous height from the bottom for a column c.
/// Our grid indexes 0..goldRows-1 top->bottom. Bottom row = goldRows-1.
int _columnHeight(int c) {
  int h = 0;
  for (int r = goldRows - 1; r >= 0; r--) {
    if (goldenGrid[r][c]) {
      h++;
    } else {
      break; // stop at first empty seen from bottom
    }
  }
  return h;
}

/// The next placeable row index in column c (the lowest empty).
int _nextPlaceableRow(int c) {
  int h = _columnHeight(c);
  return (goldRows - 1) - h;
}

/// Can place a block at (r,c)? Only if it's exactly the next placeable cell.
bool _canPlaceAt(int r, int c) {
  return !goldenGrid[r][c] && r == _nextPlaceableRow(c);
}

/// Can remove a block at (r,c)? Only the topmost filled cell can be removed.
bool _canRemoveAt(int r, int c) {
  final h = _columnHeight(c);
  // topmost filled row index = (goldRows - h)
  return goldenGrid[r][c] && r == (goldRows - h);
}

/// Total golden points using the stacking rule:
/// For a column height h: sum_{k=0}^{h-1} (10 + 5*k) = 10h + 5*h*(h-1)/2
int _goldenPoints() {
  int pts = 0;
  for (int c = 0; c < goldCols; c++) {
    final h = _columnHeight(c);
    pts += kGoldenBase * h + kGoldenStackBonus * ((h * (h - 1)) ~/ 2);
  }
  return pts;
}


  @override
  void initState() {
    super.initState();
    // init golden grid
    goldenGrid = List.generate(
      goldRows,
      (_) => List.generate(goldCols, (_) => false),
    );
    _loadMatchDetails();
  }

  @override
  void dispose() {
    superchargeTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMatchDetails() async {
    setState(() => _loadingDetails = true);
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/match/${widget.matchId}/details'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          matchNumber = data['match_number'];
          redTeams = (data['red_teams'] as List<dynamic>).cast<String>();
          blueTeams = (data['blue_teams'] as List<dynamic>).cast<String>();
          _loadingDetails = false;
        });
      } else {
        setState(() => _loadingDetails = false);
        _showSnack('Could not load match details (${res.statusCode}).');
      }
    } catch (e) {
      setState(() => _loadingDetails = false);
      _showSnack('Network error loading match details.');
    }
  }

  // --- Points model (keep in sync with backend) ---
  static const int kAllianceChargeBase = 5;
  static const int kCapturedCharge = 10;
  static const int kDock = 15;
  static const int kEngage = 10;
  static const int kFullParking = 10;
  static const int kPartialParking = 5;
  static const int kMinorPenalty = -5;
  static const int kMajorPenalty = -15;

  int _goldenCount() {
    int c = 0;
    for (final row in goldenGrid) {
      for (final v in row) {
        if (v) c++;
      }
    }
    return c;
  }

  int _allianceChargePerPress() {
    // while supercharge is active, alliance charge +1 bonus
    return superchargeActive ? (kAllianceChargeBase + 1) : kAllianceChargeBase;
  }

  int _previewTotal() {
    final parkingPoints =
        (fullParking ? kFullParking : 0) + (partialParking ? kPartialParking : 0);

    final goldenPoints = _goldenPoints();

    final total = (allianceCharge * _allianceChargePerPress()) +
        (capturedCharge * kCapturedCharge) +
        (docked * kDock) +
        (engaged * kEngage) +
        parkingPoints +
        goldenPoints +
        (minorPenalties * kMinorPenalty) +
        (majorPenalties * kMajorPenalty);

    return total;
  }


  // --- Supercharge behaviour ---
  void _toggleSupercharge() {
    if (superchargeActive) return; // ignore if already active
    setState(() {
      superchargeActive = true;
      superchargeSecondsLeft = 15;
    });

    superchargeTimer?.cancel();
    superchargeTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (superchargeSecondsLeft <= 1) {
        t.cancel();
        setState(() {
          superchargeActive = false; // disable bonus + captured inputs
          superchargeSecondsLeft = 0;
        });
      } else {
        setState(() => superchargeSecondsLeft--);
      }
    });
  }

  // --- Reset with confirmation ---
  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset match inputs?'),
        content: const Text('This will clear all counters on this screen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );

    if (ok == true) {
      superchargeTimer?.cancel();
      setState(() {
        allianceCharge = 0;
        capturedCharge = 0;
        minorPenalties = 0;
        majorPenalties = 0;
        docked = 0;
        engaged = 0;
        fullParking = false;
        partialParking = false;
        superchargeActive = false;
        superchargeSecondsLeft = 0;
        matchEnded = false;
        goldenGrid =
            List.generate(goldRows, (_) => List.generate(goldCols, (_) => false));
      });
    }
  }

  // --- Submit score to backend ---
Future<void> _submitScore() async {
  setState(() => _submitting = true);
  try {
    final body = {
      'alliance_charge': allianceCharge,
      'captured_charge': capturedCharge,
      'golden_charge_stack': jsonEncode(goldenGrid),
      'minor_penalties': minorPenalties,
      'major_penalties': majorPenalties,
      'full_parking': fullParking ? 1 : 0,
      'partial_parking': partialParking ? 1 : 0,
      'docked': docked,
      'engaged': engaged,
      'supercharge_mode': superchargeActive,
      'supercharge_end_time':
          superchargeActive ? DateTime.now().toIso8601String() : '',
      'submitted_by': null, // wire real user id if available
    };

    final url =
        Uri.parse('$baseUrl/score/${widget.matchId}/${widget.alliance}');
    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (res.statusCode == 200) {
      // Allow end-of-match negative captured adjustment if you return
      setState(() => matchEnded = true);

      // Go straight to Match Summary
      _goToSummary();
    } else {
      _showSnack('Submit failed (${res.statusCode}).');
    }
  } catch (e) {
    _showSnack('Network error while submitting score.');
  } finally {
    setState(() => _submitting = false);
  }
}


  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- Small builders ---
  Widget _countRow({
    required String label,
    required int value,
    required VoidCallback onInc,
    required VoidCallback onDec,
    bool decEnabled = true,
    String? trailingText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          IconButton(onPressed: onInc, icon: const Icon(Icons.add_circle)),
          IconButton(
            onPressed: decEnabled ? onDec : null,
            icon: const Icon(Icons.remove_circle),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade400),
            ),
            child: Text('$value'),
          ),
          if (trailingText != null) ...[
            const SizedBox(width: 10),
            Text(trailingText, style: TextStyle(color: Colors.grey.shade700)),
          ]
        ],
      ),
    );
  }

  Widget _parkingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Charge Station Parking', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                FilterChip(
                  selected: fullParking,
                  label: const Text('Full'),
                  onSelected: (v) => setState(() {
                    fullParking = v;
                    if (v) partialParking = false;
                  }),
                ),
                FilterChip(
                  selected: partialParking,
                  label: const Text('Partial'),
                  onSelected: (v) => setState(() {
                    partialParking = v;
                    if (v) fullParking = false;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Points: ${(fullParking ? kFullParking : 0) + (partialParking ? kPartialParking : 0)}'),
          ],
        ),
      ),
    );
  }

  Widget _goldenGridCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Golden Charge (4×4)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Column(
              children: List.generate(goldRows, (r) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(goldCols, (c) {
                    final selected = goldenGrid[r][c];
                    return Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            if (_canPlaceAt(r, c)) {
                              // place the next block
                              goldenGrid[r][c] = true;
                            } else if (_canRemoveAt(r, c)) {
                              // remove only the topmost filled
                              goldenGrid[r][c] = false;
                            } else {
                              _showSnack('Place from bottom up • Remove from top down in each column.');
                            }
                          });
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: goldenGrid[r][c]
                                ? Colors.amber
                                : (_canPlaceAt(r, c) ? Colors.amber.shade100 : Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade500),
                          ),
                        ),
                      )
                    );
                  }),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text('Blocks: ${_goldenCount()}  •  Golden Points: ${_goldenPoints()}'),
          ],
        ),
      ),
    );
  }

  Widget _superchargeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Supercharge Mode', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: superchargeActive ? null : _toggleSupercharge,
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Activate (15s)'),
                ),
                const SizedBox(width: 12),
                Text(
                  superchargeActive
                      ? 'ACTIVE: ${superchargeSecondsLeft}s left (Alliance Charge +1; Captured enabled)'
                      : 'Inactive',
                  style: TextStyle(
                    color: superchargeActive ? Colors.green.shade700 : Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Alliance Charge per press: ${_allianceChargePerPress()} pts'),
          ],
        ),
      ),
    );
  }

  void _goToSummary() {
  Navigator.pushNamed(
    context,
    '/summary',
    arguments: {
      'matchId': widget.matchId,
      'arena': null,                 // pass real arena if you have it
      'alliance': widget.alliance,   // 'red' or 'blue' (optional context)
    },
  );
}


  @override
  Widget build(BuildContext context) {
    final isRed = widget.alliance.toLowerCase() == 'red';
    final allianceTeams = isRed ? redTeams : blueTeams;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _loadingDetails
              ? 'Scoring'
              : 'Match ${matchNumber ?? widget.matchId} • ${isRed ? "RED" : "BLUE"}',
        ),
        actions: [
          IconButton(
            onPressed: _confirmReset,
            tooltip: 'Reset',
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: _loadingDetails
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Teams bar
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Text('Teams:', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              if (allianceTeams.isEmpty)
                                const Text('—')
                              else
                                Wrap(
                                  spacing: 8,
                                  children: allianceTeams
                                      .map((t) => Chip(
                                            backgroundColor:
                                                isRed ? Colors.red.shade100 : Colors.blue.shade100,
                                            label: Text(t),
                                          ))
                                      .toList(),
                                ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isRed ? Colors.red.shade50 : Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isRed ? 'RED' : 'BLUE',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isRed ? Colors.red.shade700 : Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),
                      // Left & right columns
                      LayoutBuilder(builder: (context, c) {
                        final twoCols = c.maxWidth >= 760;
                        final left = Column(
                          children: [
                            _countRow(
                              label: 'Alliance Charge',
                              value: allianceCharge,
                              onInc: () => setState(() => allianceCharge++),
                              onDec: () => setState(() {
                                if (allianceCharge > 0) allianceCharge--;
                              }),
                              trailingText:
                                  'per press: ${_allianceChargePerPress()} pts',
                            ),
                            _countRow(
                              label: 'Minor Penalty',
                              value: minorPenalties,
                              onInc: () => setState(() => minorPenalties++),
                              onDec: () => setState(() {
                                if (minorPenalties > 0) minorPenalties--;
                              }),
                              trailingText: '$kMinorPenalty each',
                            ),
                            _countRow(
                              label: 'Major Penalty',
                              value: majorPenalties,
                              onInc: () => setState(() => majorPenalties++),
                              onDec: () => setState(() {
                                if (majorPenalties > 0) majorPenalties--;
                              }),
                              trailingText: '$kMajorPenalty each',
                            ),
                            _goldenGridCard(),
                          ],
                        );

                        final right = Column(
                          children: [
                            _parkingCard(),
                            _countRow(
                              label: 'Dock on Charge Station',
                              value: docked,
                              onInc: () => setState(() => docked++),
                              onDec: () => setState(() {
                                if (docked > 0) docked--;
                              }),
                              trailingText: '$kDock each',
                            ),
                            _countRow(
                              label: 'Engage with Station',
                              value: engaged,
                              onInc: () => setState(() => engaged++),
                              onDec: () => setState(() {
                                if (engaged > 0) engaged--;
                              }),
                              trailingText: '$kEngage each',
                            ),
                            _superchargeCard(),
                            // Captured Charge section
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Captured Charge',
                                        style: TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    _countRow(
                                      label: 'Count',
                                      value: capturedCharge,
                                      onInc: superchargeActive
                                          ? () => setState(() => capturedCharge++)
                                          : () {},
                                      onDec: () {
                                        if (!matchEnded && !superchargeActive) return;
                                        setState(() {
                                          if (capturedCharge > 0) capturedCharge--;
                                        });
                                      },
                                      decEnabled: superchargeActive || matchEnded,
                                      trailingText:
                                          superchargeActive ? 'Enabled (+$kCapturedCharge each)' :
                                          (matchEnded
                                              ? 'Negative allowed (post‑match)'
                                              : 'Disabled until Supercharge or end'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );

                        return twoCols
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: left),
                                  const SizedBox(width: 12),
                                  Expanded(child: right),
                                ],
                              )
                            : Column(
                                children: [
                                  left,
                                  const SizedBox(height: 12),
                                  right,
                                ],
                              );
                      }),

                      const SizedBox(height: 12),

                      // Total + actions
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Text(
                                'Preview Total: ${_previewTotal()}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const Spacer(),
                              FilledButton(
                                onPressed: _submitting ? null : _submitScore,
                                child: _submitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Submit Score'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
