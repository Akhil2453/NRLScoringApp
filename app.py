from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS
from flask_socketio import SocketIO
import hashlib
import csv
from io import StringIO
import json

# -----------------------------
# Flask & extensions
# -----------------------------
app = Flask(__name__)
CORS(app)

# SQLite DB
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///nrl_scoring.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# SocketIO for live updates
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')

# ORM
db = SQLAlchemy(app)

# -----------------------------
# Helpers
# -----------------------------
def hash_password(password: str) -> str:
    """Simple SHA-256 password hasher (for demo only)."""
    return hashlib.sha256(password.encode()).hexdigest()

def get_by_id(model, pk):
    """SQLAlchemy 2.x style Session.get wrapper."""
    return db.session.get(model, pk)

# -----------------------------
# Models
# -----------------------------
class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(128), nullable=False)
    role = db.Column(db.String(50), nullable=False)  # referee, head_referee, admin

class Team(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    # Using team number as 'name' (string) as per your schedule upload
    name = db.Column(db.String(100), nullable=False)
    inspection_status = db.Column(db.String(50), default="pending")  # passed, failed, pending
    red_cards = db.Column(db.Integer, default=0)
    yellow_cards = db.Column(db.Integer, default=0)

class Match(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    match_number = db.Column(db.Integer, unique=True, nullable=False)
    arena = db.Column(db.String(50), nullable=False)  # Alpha / Bravo
    red_teams = db.Column(db.String(100))             # comma-separated team numbers
    blue_teams = db.Column(db.String(100))
    status = db.Column(db.String(50), default="pending")  # pending / live / completed

class ScoreEntry(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    match_id = db.Column(db.Integer, db.ForeignKey('match.id'), nullable=False)
    alliance = db.Column(db.String(10), nullable=False)  # 'red' or 'blue'

    # Scoring fields
    alliance_charge = db.Column(db.Integer, default=0)
    captured_charge = db.Column(db.Integer, default=0)
    golden_charge_stack = db.Column(db.Text, default='')  # your grid encoding (string)
    minor_penalties = db.Column(db.Integer, default=0)
    major_penalties = db.Column(db.Integer, default=0)
    full_parking = db.Column(db.Integer, default=0)
    partial_parking = db.Column(db.Integer, default=0)
    docked = db.Column(db.Integer, default=0)
    engaged = db.Column(db.Integer, default=0)
    supercharge_mode = db.Column(db.Boolean, default=False)
    supercharge_end_time = db.Column(db.String, default='')

    submitted_by = db.Column(db.Integer)                # referee user id
    finalised = db.Column(db.Boolean, default=False)    # final lock by head referee
    confirmed_by = db.Column(db.Integer)                # head referee user id

# -----------------------------
# Auth
# -----------------------------
@app.route('/register', methods=['POST'])
def register():
    data = request.json or {}
    try:
        new_user = User(
            username=data['username'],
            email=data['email'],
            password_hash=hash_password(data['password']),
            role=data['role']
        )
        db.session.add(new_user)
        db.session.commit()
        return jsonify({'message': 'User registered successfully'}), 201
    except KeyError as e:
        return jsonify({'error': f'Missing field: {e.args[0]}'}), 400
    except Exception as e:
        db.session.rollback()
        return jsonify({'error': str(e)}), 500

@app.route('/login', methods=['POST'])
def login():
    data = request.json or {}
    user = User.query.filter_by(username=data.get('username', '')).first()
    if user and user.password_hash == hash_password(data.get('password', '')):
        return jsonify({
            'message': 'Login successful',
            'user_id': user.id,
            'role': user.role,
            'username': user.username
        }), 200
    return jsonify({'message': 'Invalid credentials'}), 401

# -----------------------------
# Schedule upload & retrieval
# -----------------------------
@app.route('/upload_schedule', methods=['POST'])
def upload_schedule():
    """
    CSV format (with header):
    Match No.,Red Team 1,Red Team 2,Blue Team 1,Blue Team 2
    1,112,245,398,530
    ...
    """
    file = request.files.get('file')
    if not file or not file.filename.endswith('.csv'):
        return jsonify({"error": "Invalid file format. Upload a CSV."}), 400

    stream = StringIO(file.stream.read().decode("UTF8"), newline=None)
    csv_input = csv.reader(stream)

    # Skip header
    try:
        headers = next(csv_input)
    except StopIteration:
        return jsonify({"error": "CSV is empty"}), 400

    inserted_matches = []
    inserted_teams = set()

    try:
        for row in csv_input:
            if not row or len(row) < 5:
                continue

            match_no = int(row[0])
            red1, red2, blue1, blue2 = row[1].strip(), row[2].strip(), row[3].strip(), row[4].strip()

            # Ensure teams exist
            for team_num in [red1, red2, blue1, blue2]:
                if not Team.query.filter_by(name=team_num).first():
                    db.session.add(Team(name=team_num))
                    inserted_teams.add(team_num)

            # Add match if not existing
            if not Match.query.filter_by(match_number=match_no).first():
                new_match = Match(
                    match_number=match_no,
                    arena="Alpha",  # default, can be changed later
                    red_teams=f"{red1},{red2}",
                    blue_teams=f"{blue1},{blue2}",
                    status="pending"
                )
                db.session.add(new_match)
                inserted_matches.append(match_no)

        db.session.commit()
        return jsonify({
            "message": "Schedule uploaded successfully",
            "matches_added": inserted_matches,
            "teams_added": list(inserted_teams)
        }), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500

@app.route('/matches', methods=['GET'])
def get_matches():
    matches = Match.query.filter(Match.status != 'completed').all()
    return jsonify({
        'matches': [
            {
                'match_id': m.id,
                'match_number': m.match_number,
                'arena': m.arena,
                'red_teams': m.red_teams.split(',') if m.red_teams else [],
                'blue_teams': m.blue_teams.split(',') if m.blue_teams else [],
                'status': m.status
            } for m in matches
        ]
    }), 200

# -----------------------------
# Golden points helpers
# -----------------------------
def golden_points_from_grid(grid):
    """
    grid: list[list[bool]] top->bottom (row 0 is top, last row is bottom)
    Rule per column:
      - You can only stack contiguously from the bottom.
      - Points for height h in a column: sum_{k=0}^{h-1} (10 + 5*k)
    """
    if not isinstance(grid, list):
        return 0

    rows = len(grid)
    cols = len(grid[0]) if rows else 0
    total = 0

    for c in range(cols):
        # contiguous height from bottom
        h = 0
        for r in range(rows - 1, -1, -1):
            try:
                cell = bool(grid[r][c])
            except Exception:
                cell = False
            if cell:
                h += 1
            else:
                break
        total += 10 * h + 5 * (h * (h - 1) // 2)

    return total

def golden_points_from_text(grid_text: str | None) -> int:
    """Parse stored JSON text and compute golden points safely."""
    if not grid_text:
        return 0
    try:
        grid = json.loads(grid_text)
        return golden_points_from_grid(grid)
    except Exception:
        return 0

# -----------------------------
# Match details
# -----------------------------
@app.route('/match/<int:match_id>/details', methods=['GET'])
def get_match_details(match_id):
    match = get_by_id(Match, match_id)
    if not match:
        return jsonify({'error': 'Match not found'}), 404

    red_score = ScoreEntry.query.filter_by(match_id=match_id, alliance='red').first()
    blue_score = ScoreEntry.query.filter_by(match_id=match_id, alliance='blue').first()

    def serialize_score(score: ScoreEntry | None):
        if not score:
            return None
        return {
            "alliance_charge": score.alliance_charge,
            "captured_charge": score.captured_charge,
            "golden_charge_stack": score.golden_charge_stack,
            "golden_points": golden_points_from_text(score.golden_charge_stack),  # <-- NEW
            "minor_penalties": score.minor_penalties,
            "major_penalties": score.major_penalties,
            "full_parking": score.full_parking,
            "partial_parking": score.partial_parking,
            "docked": score.docked,
            "engaged": score.engaged,
            "supercharge_mode": score.supercharge_mode,
            "supercharge_end_time": score.supercharge_end_time,
            "submitted_by": score.submitted_by,
            "finalised": score.finalised,
            "confirmed_by": score.confirmed_by
        }

    return jsonify({
        "match_id": match.id,
        "match_number": match.match_number,
        "arena": match.arena,
        "status": match.status,
        "red_teams": match.red_teams.split(',') if match.red_teams else [],
        "blue_teams": match.blue_teams.split(',') if match.blue_teams else [],
        "red_score": serialize_score(red_score),
        "blue_score": serialize_score(blue_score)
    }), 200

# -----------------------------
# Scoring logic
# -----------------------------
def calculate_total_score(score):
    base_points = 5
    supercharge_bonus = 1 if getattr(score, 'supercharge_mode', False) else 0

    total = 0
    total += (score.alliance_charge or 0) * (base_points + supercharge_bonus)
    total += (score.captured_charge or 0) * 10
    total += (score.full_parking or 0) * 10
    total += (score.partial_parking or 0) * 5
    total += (score.docked or 0) * 15
    total += (score.engaged or 0) * 10

    # Golden stack points
    total += golden_points_from_text(score.golden_charge_stack)

    total -= (score.minor_penalties or 0) * 5
    total -= (score.major_penalties or 0) * 15
    return total

@app.route('/score/<int:match_id>/<alliance>', methods=['POST'])
def submit_score(match_id, alliance):
    if alliance not in ['red', 'blue']:
        return jsonify({'error': 'Alliance must be red or blue'}), 400

    match = get_by_id(Match, match_id)
    if not match:
        return jsonify({'error': 'Match not found'}), 404

    data = request.json or {}

    score = ScoreEntry.query.filter_by(match_id=match_id, alliance=alliance).first()
    if not score:
        score = ScoreEntry(match_id=match_id, alliance=alliance)

    # Assign with defaults
    score.alliance_charge      = int(data.get('alliance_charge', score.alliance_charge or 0))
    score.captured_charge      = int(data.get('captured_charge', score.captured_charge or 0))
    score.golden_charge_stack  = data.get('golden_charge_stack', score.golden_charge_stack or '')
    score.minor_penalties      = int(data.get('minor_penalties', score.minor_penalties or 0))
    score.major_penalties      = int(data.get('major_penalties', score.major_penalties or 0))
    score.full_parking         = int(data.get('full_parking', score.full_parking or 0))
    score.partial_parking      = int(data.get('partial_parking', score.partial_parking or 0))
    score.docked               = int(data.get('docked', score.docked or 0))
    score.engaged              = int(data.get('engaged', score.engaged or 0))
    score.supercharge_mode     = bool(data.get('supercharge_mode', score.supercharge_mode or False))
    score.supercharge_end_time = data.get('supercharge_end_time', score.supercharge_end_time or '')
    score.submitted_by         = data.get('submitted_by', score.submitted_by)

    db.session.add(score)
    db.session.commit()

    total_score = calculate_total_score(score)
    golden_pts = golden_points_from_text(score.golden_charge_stack)  # <-- NEW

    # Live emit (include golden_points)
    socketio.emit('score_update', {
        'match_id': match_id,
        'alliance': alliance,
        'score_breakdown': {
            'alliance_charge': score.alliance_charge,
            'captured_charge': score.captured_charge,
            'golden_charge_stack': score.golden_charge_stack,
            'golden_points': golden_pts,  # <-- NEW
            'minor_penalties': score.minor_penalties,
            'major_penalties': score.major_penalties,
            'full_parking': score.full_parking,
            'partial_parking': score.partial_parking,
            'docked': score.docked,
            'engaged': score.engaged,
            'supercharge_mode': score.supercharge_mode
        },
        'total_score': total_score,
        'finalised': score.finalised
    })

    return jsonify({
        'message': f'{alliance.title()} alliance score submitted successfully.',
        'total_score': total_score
    }), 200

@app.route('/finalise_score', methods=['POST'])
def finalise_score():
    data = request.json or {}
    match_id = data.get('match_id')
    confirmed_by = data.get('confirmed_by')

    if not match_id or not confirmed_by:
        return jsonify({'error': 'match_id and confirmed_by are required'}), 400

    match = get_by_id(Match, match_id)
    if not match:
        return jsonify({'error': 'Match not found'}), 404

    red_score = ScoreEntry.query.filter_by(match_id=match_id, alliance='red').first()
    blue_score = ScoreEntry.query.filter_by(match_id=match_id, alliance='blue').first()

    if not red_score or not blue_score:
        return jsonify({'error': 'Scores for both alliances must be submitted before finalisation'}), 400

    if red_score.finalised or blue_score.finalised:
        return jsonify({'error': 'Score already finalised'}), 400

    red_score.finalised = True
    blue_score.finalised = True
    red_score.confirmed_by = confirmed_by
    blue_score.confirmed_by = confirmed_by

    db.session.commit()

    # Optional: broadcast a "final" event
    socketio.emit('match_finalised', {
        'match_id': match_id,
        'red_total': calculate_total_score(red_score),
        'blue_total': calculate_total_score(blue_score),
        'confirmed_by': confirmed_by
    })

    return jsonify({'message': f'Match {match_id} scores finalised by Head Referee ID {confirmed_by}.'}), 200

@app.route('/match/<int:match_id>/summary', methods=['GET'])
def match_summary(match_id):
    match = get_by_id(Match, match_id)
    if not match:
        return jsonify({'error': 'Match not found'}), 404

    red_score = ScoreEntry.query.filter_by(match_id=match_id, alliance='red').first()
    blue_score = ScoreEntry.query.filter_by(match_id=match_id, alliance='blue').first()

    def serialize(score: ScoreEntry | None):
        if not score:
            return {
                "score_breakdown": {},
                "total_score": 0,
                "finalised": False
            }
        golden_pts = golden_points_from_text(score.golden_charge_stack)  # <-- NEW
        return {
            "score_breakdown": {
                "alliance_charge": score.alliance_charge,
                "captured_charge": score.captured_charge,
                "golden_charge_stack": score.golden_charge_stack,
                "golden_points": golden_pts,  # <-- NEW
                "minor_penalties": score.minor_penalties,
                "major_penalties": score.major_penalties,
                "full_parking": score.full_parking,
                "partial_parking": score.partial_parking,
                "docked": score.docked,
                "engaged": score.engaged,
                "supercharge_mode": score.supercharge_mode
            },
            "total_score": calculate_total_score(score),
            "finalised": score.finalised,
            "confirmed_by": score.confirmed_by
        }

    return jsonify({
        "match_id": match.id,
        "match_number": match.match_number,
        "arena": match.arena,
        "status": match.status,
        "teams": {
            "red": match.red_teams.split(',') if match.red_teams else [],
            "blue": match.blue_teams.split(',') if match.blue_teams else []
        },
        "score": {
            "red": serialize(red_score),
            "blue": serialize(blue_score)
        }
    }), 200

# -----------------------------
# Misc: broadcast & inspection & team profile
# -----------------------------
@app.route('/broadcast_score', methods=['POST'])
def broadcast_score():
    data = request.json or {}
    match_id = data.get('match_id')
    alliance = data.get('alliance')
    score = data.get('score')

    if not match_id or not alliance or score is None:
        return jsonify({'error': 'match_id, alliance, and score are required'}), 400

    socketio.emit('score_update', {
        'match_id': match_id,
        'alliance': alliance,
        'score': score
    })
    return jsonify({'message': 'Score update broadcasted'}), 200

@app.route('/inspection/team_number/<string:team_number>', methods=['POST'])
def update_inspection_by_team_number(team_number):
    data = request.json or {}
    status = data.get('inspection_status')

    if status not in ['passed', 'failed', 'pending']:
        return jsonify({'error': 'Invalid inspection status'}), 400

    team = Team.query.filter_by(name=team_number).first()
    if not team:
        return jsonify({'error': 'Team not found'}), 404

    team.inspection_status = status
    db.session.commit()

    return jsonify({'message': f'Inspection status for team {team_number} updated to {status}'}), 200

@app.route('/team/profile/<string:team_number>', methods=['GET'])
def view_team_profile_by_number(team_number):
    team = Team.query.filter_by(name=team_number).first()
    if not team:
        return jsonify({'error': 'Team not found'}), 404

    return jsonify({
        'team_number': team.name,
        'inspection_status': team.inspection_status,
        'red_cards': team.red_cards,
        'yellow_cards': team.yellow_cards
    }), 200

# -----------------------------
# Bootstrap & run
# -----------------------------
if __name__ == '__main__':
    with app.app_context():
        db.create_all()
    # Use socketio.run to serve both HTTP + websockets
    socketio.run(app, host='0.0.0.0', port=5000)
