from flask import Flask, request, jsonify  # Core Flask modules for API creation
from flask_sqlalchemy import SQLAlchemy     # ORM for SQLite database interaction
from flask_cors import CORS                 # Handles CORS for frontend-backend communication
import hashlib                              # Used for secure password hashing
import csv
from io import StringIO

# Step 1: Initialize the Flask app
app = Flask(__name__)
CORS(app)  # Enable CORS so that frontend (Flutter Web) can communicate with backend

# Step 2: Configure SQLite database
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///nrl_scoring.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# Step 3: Initialize SQLAlchemy with the app
db = SQLAlchemy(app)

# Step 4: Define the User model (table) for authentication
class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)                      # Auto-increment ID
    username = db.Column(db.String(80), unique=True, nullable=False) # Must be unique
    email = db.Column(db.String(120), unique=True, nullable=False)   # Must be unique
    password_hash = db.Column(db.String(128), nullable=False)        # Store hashed password
    role = db.Column(db.String(50), nullable=False)                  # e.g., referee, head_referee, admin

# Step 5: Password hashing function using SHA-256
def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()

# Model for participating teams
class Team(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    inspection_status = db.Column(db.String(50), default="pending")  # passed, failed, pending
    red_cards = db.Column(db.Integer, default=0)
    yellow_cards = db.Column(db.Integer, default=0)

# Model for a scheduled match
class Match(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    match_number = db.Column(db.Integer, unique=True, nullable=False)
    arena = db.Column(db.String(50), nullable=False)  # Alpha / Bravo
    red_teams = db.Column(db.String(100))  # Comma-separated team IDs
    blue_teams = db.Column(db.String(100))
    status = db.Column(db.String(50), default="pending")  # pending / live / completed

# Model to store score entries per alliance
class ScoreEntry(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    match_id = db.Column(db.Integer, db.ForeignKey('match.id'), nullable=False)
    alliance = db.Column(db.String(10), nullable=False)  # red or blue
    alliance_charge = db.Column(db.Integer, default=0)
    captured_charge = db.Column(db.Integer, default=0)
    golden_charge_stack = db.Column(db.String(50), default="")  # 4x4 status grid, e.g., "1100110011001100"
    minor_penalties = db.Column(db.Integer, default=0)
    major_penalties = db.Column(db.Integer, default=0)
    full_parking = db.Column(db.Integer, default=0)
    partial_parking = db.Column(db.Integer, default=0)
    docked = db.Column(db.Integer, default=0)
    engaged = db.Column(db.Integer, default=0)
    supercharge_mode = db.Column(db.Boolean, default=False)
    supercharge_end_time = db.Column(db.String(50), default="")
    submitted_by = db.Column(db.Integer, db.ForeignKey('user.id'))
    finalized_by = db.Column(db.Integer, db.ForeignKey('user.id'))


# Step 6: API route to register a user (used by admin to add referees/head refs)
@app.route('/register', methods=['POST'])
def register():
    data = request.json
    try:
        hashed_pw = hash_password(data['password'])  # Securely hash the password
        new_user = User(
            username=data['username'],
            email=data['email'],
            password_hash=hashed_pw,
            role=data['role']
        )
        db.session.add(new_user)
        db.session.commit()
        return jsonify({'message': 'User registered successfully'}), 201
    except KeyError as e:
        return jsonify({'error': f'Missing field: {e.args[0]}'}), 400


# Step 7: API route to login and return user role
@app.route('/login', methods=['POST'])
def login():
    data = request.json
    user = User.query.filter_by(username=data['username']).first()
    if user and user.password_hash == hash_password(data['password']):
        return jsonify({
            'message': 'Login successful',
            'user_id': user.id,
            'role': user.role
        }), 200
    return jsonify({'message': 'Invalid credentials'}), 401

@app.route('/upload_schedule', methods=['POST'])
def upload_schedule():
    file = request.files['file']
    if not file.filename.endswith('.csv'):
        return jsonify({"error": "Invalid file format. Upload a CSV."}), 400

    stream = StringIO(file.stream.read().decode("UTF8"), newline=None)
    csv_input = csv.reader(stream)

    # Skip header
    headers = next(csv_input)

    inserted_matches = []
    inserted_teams = set()

    for row in csv_input:
        match_no = int(row[0])
        red1 = row[1].strip()
        red2 = row[2].strip()
        blue1 = row[3].strip()
        blue2 = row[4].strip()

        # Add teams if not already in DB
        for team_id in [red1, red2, blue1, blue2]:
            if not Team.query.filter_by(name=team_id).first():
                new_team = Team(name=team_id)
                db.session.add(new_team)
                inserted_teams.add(team_id)

        # Add match
        if not Match.query.filter_by(match_number=match_no).first():
            new_match = Match(
                match_number=match_no,
                arena="Alpha",  # Default for now
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

@app.route('/matches', methods=['GET'])
def get_matches():
    # Optional: filter by arena in the future
    matches = Match.query.filter(Match.status != 'completed').all()

    match_list = []
    for match in matches:
        match_list.append({
            'match_id': match.id,
            'match_number': match.match_number,
            'arena': match.arena,
            'red_teams': match.red_teams.split(','),
            'blue_teams': match.blue_teams.split(','),
            'status': match.status
        })

    return jsonify({'matches': match_list}), 200


# Step 8: Run server and auto-create DB tables if not present
if __name__ == '__main__':
    with app.app_context():
        db.create_all()  # Automatically create tables based on models

    app.run(debug=True)  # Start the Flask server on localhost:5000
