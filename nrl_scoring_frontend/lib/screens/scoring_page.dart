import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:socket_io_client/socket_io_client.dart' as IO;

/// ScoringPage
/// Navigator.pushNamed(context, '/score', arguments: {
///   'matchId': <int>,
///   'alliance': 'red'|'blue',
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
  // ===== Base URL helpers (works for Web, Desktop, Emulators) =====
  String getBaseUrl() {
    if (kIsWeb) return 'http://localhost:5000';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:5000'; // Android emulator loopback
      return 'http://localhost:5000';
    } catch (_) {
      return 'http://localhost:5000';
    }
  }

  late final String baseUrl = getBaseUrl();

  // ===== Socket.IO =====
  IO.Socket? _socket;
  bool _finalised = false;

  // Live mirrors of BOTH alliances (don’t overwrite your input fields)
  Map<String, dynamic>? liveRed;   // last score_update payload for red
  Map<String, dynamic>? liveBlue;  // last score_update payload for blue
  int? liveRedTotal;
  int? liveBlueTotal;

  // NEW: debounce to limit live emits
  Timer? _liveDebounce; // NEW

  // ===== Match/Alliance info from backend =====
  int? matchNumber;
  List<String> redTeams = [];
  List<String> blueTeams = [];

  // ===== Scoring state (your alliance’s inputs) =====
  int allianceCharge = 0;
  int capturedCharge = 0;
  int minorPenalties = 0;
  int majorPenalties = 0;
  int docked = 0;
  int engaged = 0;
  bool fullParking = false;
  bool partialParking = false;

  // Golden charge 4x4
  final int goldRows = 4;
  final int goldCols = 4;
  late List<List<bool>> goldenGrid;

  // Supercharge (15s)
  bool superchargeActive = false;
  int superchargeSecondsLeft = 0;
  Timer? superchargeTimer;

  // End-of-match
  bool matchEnded = false;

  // UI helpers
  bool _loadingDetails = true;
  bool _submitting = false;

  // ===== Golden constants & helpers =====
  static const int kGoldenBase = 10;      // 10 per block
  static const int kGoldenStackBonus = 5; // +5 per level above bottom

  int _columnHeight(int c) {
    int h = 0;
    for (int r = goldRows - 1; r >= 0; r--) {
      if (goldenGrid[r][c]) {
        h++;
      } else {
        break;
      }
    }
    return h;
  }

  int _nextPlaceableRow(int c) {
    int h = _columnHeight(c);
    return (goldRows - 1) - h;
  }

  bool _canPlaceAt(int r, int c) => !goldenGrid[r][c] && r == _nextPlaceableRow(c);

  bool _canRemoveAt(int r, int c) {
    final h = _columnHeight(c);
    return goldenGrid[r][c] && r == (goldRows - h);
  }

  int _goldenPoints() {
    int pts = 0;
    for (int c = 0; c < goldCols; c++) {
      final h = _columnHeight(c);
      pts += kGoldenBase * h + kGoldenStackBonus * ((h * (h - 1)) ~/ 2);
    }
    return pts;
  }

  // ===== Lifecycle =====
  @override
  void initState() {
    super.initState();
    goldenGrid = List.generate(goldRows, (_) => List.generate(goldCols, (_) => false));
    _loadMatchDetails();
    _connectSocket(); // <--- live sync
  }

  @override
  void dispose() {
    superchargeTimer?.cancel();
    // NEW: leave match room and cleanup debounce
    try {
      _socket?.emit('leave_match', {'match_id': widget.matchId}); // NEW
    } catch (_) {}
    _liveDebounce?.cancel(); // NEW
    _socket?.dispose();
    super.dispose();
  }

  // ===== Socket.IO connection =====
  void _connectSocket() {
    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('Socket connected');
      // NEW: Join this match room so we only receive events for the same match
      _socket!.emit('join_match', {'match_id': widget.matchId}); // NEW
    });

    _socket!.onDisconnect((_) => debugPrint('Socket disconnected'));

    // Someone submitted or updated a score
    _socket!.on('score_update', (data) {
      try {
        if (data == null) return;
        if (data['match_id'] != widget.matchId) return; // ignore other matches

        final alliance = (data['alliance'] ?? '').toString();
        final total = data['total_score'] as int?;
        // final sb = data['score_breakdown'] as Map?; // not used here, but available

        setState(() {
          if (alliance == 'red') {
            liveRed = data;
            liveRedTotal = total;
          } else if (alliance == 'blue') {
            liveBlue = data;
            liveBlueTotal = total;
          }
          if (data['finalised'] == true) _finalised = true;
        });
      } catch (_) {}
    });

    // Head Referee finalised the match
    _socket!.on('match_finalised', (data) {
      try {
        if (data == null) return;
        if (data['match_id'] != widget.matchId) return;
        setState(() {
          _finalised = true;
        });
        _showSnack('Match finalised by Head Referee');
      } catch (_) {}
    });

    _socket!.connect();
  }

  // NEW: Build live payload for socket emit
  Map<String, dynamic> _buildLivePayload() { // NEW
    return {
      'alliance_charge': allianceCharge,
      'captured_charge': capturedCharge,
      'golden_charge_stack': goldenGrid,
      'minor_penalties': minorPenalties,
      'major_penalties': majorPenalties,
      'full_parking': fullParking ? 1 : 0,
      'partial_parking': partialParking ? 1 : 0,
      'docked': docked,
      'engaged': engaged,
      'supercharge_mode': superchargeActive,
    };
  }

  // NEW: Emit live update immediately
  void _broadcastLive() { // NEW
    if (_socket?.connected != true) return;
    _socket!.emit('live_score_update', {
      'match_id': widget.matchId,
      'alliance': widget.alliance.toLowerCase(),
      'score_breakdown': _buildLivePayload(),
    });
  }

  // NEW: Debounce broadcasts to avoid spamming while tapping fast
  void _scheduleLiveBroadcast() { // NEW
    _liveDebounce?.cancel();
    _liveDebounce = Timer(const Duration(milliseconds: 200), _broadcastLive);
  }

  // ===== REST: load match details =====
  Future<void> _loadMatchDetails() async {
    setState(() => _loadingDetails = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/match/${widget.matchId}/details'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          matchNumber = data['match_number'];
          redTeams = (data['red_teams'] as List<dynamic>).cast<String>();
          blueTeams = (data['blue_teams'] as List<dynamic>).cast<String>();

          final red = data['red_score'] as Map?;
          final blue = data['blue_score'] as Map?;
          if (red != null) {
            liveRedTotal = _safeTotalFromDetails(red);
          }
          if (blue != null) {
            liveBlueTotal = _safeTotalFromDetails(blue);
          }

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

  int? _safeTotalFromDetails(Map details) {
    try {
      // Keep null to avoid double-compute; live totals will arrive from socket when someone edits
      return null;
    } catch (_) {
      return null;
    }
  }

  // ===== Points model (keep in sync with backend) =====
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

  int _allianceChargePerPress() => superchargeActive ? (kAllianceChargeBase + 1) : kAllianceChargeBase;

  int _previewTotal() {
    final parkingPoints = (fullParking ? kFullParking : 0) + (partialParking ? kPartialParking : 0);
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

  // ===== Supercharge =====
  void _toggleSupercharge() {
    if (superchargeActive || _finalised) return;
    setState(() {
      superchargeActive = true;
      superchargeSecondsLeft = 15;
    });
    _scheduleLiveBroadcast(); // NEW

    superchargeTimer?.cancel();
    superchargeTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (superchargeSecondsLeft <= 1) {
        t.cancel();
        setState(() {
          superchargeActive = false;
          superchargeSecondsLeft = 0;
        });
        _scheduleLiveBroadcast(); // NEW
      } else {
        setState(() => superchargeSecondsLeft--);
        _scheduleLiveBroadcast(); // NEW
      }
    });
  }

  // ===== Reset =====
  Future<void> _confirmReset() async {
    if (_finalised) return;
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
        goldenGrid = List.generate(goldRows, (_) => List.generate(goldCols, (_) => false));
      });
      _scheduleLiveBroadcast(); // NEW
    }
  }

  // ===== Submit to backend =====
  Future<void> _submitScore() async {
    if (_finalised) return;
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
        'submitted_by': null,
      };

      final url = Uri.parse('$baseUrl/score/${widget.matchId}/${widget.alliance}');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (res.statusCode == 200) {
        setState(() => matchEnded = true);
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

  void _goToSummary() {
    Navigator.pushNamed(context, '/summary', arguments: {
      'matchId': widget.matchId,
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ===== Small builders =====
  Widget _liveScoreBar() {
    final redTotal = liveRedTotal?.toString() ?? '—';
    final blueTotal = liveBlueTotal?.toString() ?? '—';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text('RED', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(redTotal, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text('BLUE', style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(blueTotal, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
          IconButton(onPressed: _finalised ? null : onInc, icon: const Icon(Icons.add_circle)),
          IconButton(
            onPressed: _finalised ? null : (decEnabled ? onDec : null),
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
                  onSelected: _finalised ? null : (v) => setState(() {
                    fullParking = v;
                    if (v) partialParking = false;
                    _scheduleLiveBroadcast(); // NEW
                  }),
                  label: const Text('Full'),
                ),
                FilterChip(
                  selected: partialParking,
                  onSelected: _finalised ? null : (v) => setState(() {
                    partialParking = v;
                    if (v) fullParking = false;
                    _scheduleLiveBroadcast(); // NEW
                  }),
                  label: const Text('Partial'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Points: ${(fullParking ? 10 : 0) + (partialParking ? 5 : 0)}'),
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
                        onTap: _finalised ? null : () {
                          setState(() {
                            if (_canPlaceAt(r, c)) {
                              goldenGrid[r][c] = true;
                              _scheduleLiveBroadcast(); // NEW
                            } else if (_canRemoveAt(r, c)) {
                              goldenGrid[r][c] = false;
                              _scheduleLiveBroadcast(); // NEW
                            } else {
                              _showSnack('Place from bottom up • Remove from top down in each column.');
                            }
                          });
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.amber
                                : (_canPlaceAt(r, c) ? Colors.amber.shade100 : Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade500),
                          ),
                        ),
                      ),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 460;
            final statusText = superchargeActive
                ? 'ACTIVE: ${superchargeSecondsLeft}s left (Alliance Charge +1; Captured enabled)'
                : 'Inactive';
            final statusStyle = TextStyle(
              color: superchargeActive ? Colors.green.shade700 : Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Supercharge Mode', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (!compact)
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: superchargeActive || _finalised ? null : () { _toggleSupercharge(); _scheduleLiveBroadcast(); }, // NEW
                        icon: const Icon(Icons.flash_on),
                        label: const Text('Activate (15s)'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(statusText, style: statusStyle, softWrap: true, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ElevatedButton.icon(
                        onPressed: superchargeActive || _finalised ? null : () { _toggleSupercharge(); _scheduleLiveBroadcast(); }, // NEW
                        icon: const Icon(Icons.flash_on),
                        label: const Text('Activate (15s)'),
                      ),
                      const SizedBox(height: 8),
                      Text(statusText, style: statusStyle, softWrap: true, maxLines: 3),
                    ],
                  ),
                const SizedBox(height: 8),
                Text('Alliance Charge per press: ${_allianceChargePerPress()} pts'),
              ],
            );
          },
        ),
      ),
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
            onPressed: _finalised ? null : _confirmReset,
            tooltip: 'Reset',
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            onPressed: _goToSummary,
            tooltip: 'Summary',
            icon: const Icon(Icons.summarize),
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
                      // ===== Live score bar (both alliances) =====
                      _liveScoreBar(),

                      // Teams bar
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Text('Teams:', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              if (allianceTeams.isEmpty)
                                const Text('—')
                              else
                                Wrap(
                                  spacing: 8,
                                  children: allianceTeams
                                      .map((t) => Chip(
                                            backgroundColor: isRed ? Colors.red.shade100 : Colors.blue.shade100,
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

                      // Two columns
                      LayoutBuilder(builder: (context, c) {
                        final twoCols = c.maxWidth >= 760;

                        final left = Column(
                          children: [
                            _countRow(
                              label: 'Alliance Charge',
                              value: allianceCharge,
                              onInc: () => setState(() { allianceCharge++; _scheduleLiveBroadcast(); }), // NEW
                              onDec: () => setState(() {
                                if (allianceCharge > 0) allianceCharge--;
                                _scheduleLiveBroadcast(); // NEW
                              }),
                              trailingText: 'per press: ${_allianceChargePerPress()} pts',
                            ),
                            _countRow(
                              label: 'Minor Penalty',
                              value: minorPenalties,
                              onInc: () => setState(() { minorPenalties++; _scheduleLiveBroadcast(); }), // NEW
                              onDec: () => setState(() {
                                if (minorPenalties > 0) minorPenalties--;
                                _scheduleLiveBroadcast(); // NEW
                              }),
                              trailingText: '$kMinorPenalty each',
                            ),
                            _countRow(
                              label: 'Major Penalty',
                              value: majorPenalties,
                              onInc: () => setState(() { majorPenalties++; _scheduleLiveBroadcast(); }), // NEW
                              onDec: () => setState(() {
                                if (majorPenalties > 0) majorPenalties--;
                                _scheduleLiveBroadcast(); // NEW
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
                              onInc: () => setState(() { docked++; _scheduleLiveBroadcast(); }), // NEW
                              onDec: () => setState(() {
                                if (docked > 0) docked--;
                                _scheduleLiveBroadcast(); // NEW
                              }),
                              trailingText: '$kDock each',
                            ),
                            _countRow(
                              label: 'Engage with Station',
                              value: engaged,
                              onInc: () => setState(() { engaged++; _scheduleLiveBroadcast(); }), // NEW
                              onDec: () => setState(() {
                                if (engaged > 0) engaged--;
                                _scheduleLiveBroadcast(); // NEW
                              }),
                              trailingText: '$kEngage each',
                            ),
                            _superchargeCard(),
                            // Captured Charge
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Captured Charge', style: TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    _countRow(
                                      label: 'Count',
                                      value: capturedCharge,
                                      onInc: superchargeActive && !_finalised
                                          ? () => setState(() { capturedCharge++; _scheduleLiveBroadcast(); }) // NEW
                                          : () {},
                                      onDec: () {
                                        if (_finalised) return;
                                        if (!matchEnded && !superchargeActive) return;
                                        setState(() {
                                          if (capturedCharge > 0) capturedCharge--;
                                          _scheduleLiveBroadcast(); // NEW
                                        });
                                      },
                                      decEnabled: (superchargeActive || matchEnded) && !_finalised,
                                      trailingText: superchargeActive
                                          ? 'Enabled (+$kCapturedCharge each)'
                                          : (matchEnded ? 'Negative allowed (post-match)'
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
                                'Preview Total (your side): ${_previewTotal()}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                              const Spacer(),
                              FilledButton(
                                onPressed: (_submitting || _finalised) ? null : _submitScore,
                                child: _submitting
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
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
