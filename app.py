# app.py (Final Version with Auto-Save/Backup)

import os
import json
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
import bibtexparser

app = Flask(__name__)
CORS(app)

# --- NEW: Define the backup file path ---
BACKUP_FILE = 'screening_session.json'

# Updated database structure
db = {
    "all_entries": [],
    "screening_queue": [],
    "decisions": {} # Decisions will be stored as { original_index: "decision_string" }
}

# --- NEW: Function to save the current state ---
def _save_state():
    """Saves the current decisions dictionary to a JSON backup file."""
    try:
        # We only need to save the decisions, as everything else is derived from the .bib file
        state_to_save = {"decisions": db["decisions"]}
        with open(BACKUP_FILE, 'w', encoding='utf-8') as f:
            json.dump(state_to_save, f, indent=4)
        print(f"State saved to {BACKUP_FILE}")
    except Exception as e:
        print(f"Error saving state: {e}")

# --- NEW: Function to load state on startup ---
def _load_state():
    """Loads decisions from the JSON backup file if it exists."""
    try:
        if os.path.exists(BACKUP_FILE):
            with open(BACKUP_FILE, 'r', encoding='utf-8') as f:
                loaded_state = json.load(f)
                # The keys in JSON are strings, so we convert them back to integers
                db["decisions"] = {int(k): v for k, v in loaded_state.get("decisions", {}).items()}
                print(f"Successfully loaded {len(db['decisions'])} decisions from {BACKUP_FILE}")
    except Exception as e:
        print(f"Error loading state: {e}")
        db["decisions"] = {}


@app.route('/load_bibtex', methods=['POST'])
def load_bibtex():
    """
    Loads a .bib file and intelligently filters out already-screened articles
    based on the state loaded from the backup file.
    """
    if 'file' not in request.files: return jsonify({"error": "No file part"}), 400
    file = request.files['file']
    if file.filename == '': return jsonify({"error": "No selected file"}), 400

    bib_database = bibtexparser.load(file)
    all_entries = bib_database.entries

    # Set the master list of entries
    db["all_entries"] = all_entries
    db["screening_queue"] = []
    
    # Note: We keep the decisions loaded by _load_state() to remember progress
    # between app restarts, but we will re-calculate the queue.

    for i, entry in enumerate(all_entries):
        # An article needs screening if it's not in our decisions backup AND it has no group in the .bib file
        has_group = 'groups' in entry and entry['groups']
        has_decision = i in db["decisions"]

        if not has_group and not has_decision:
            db["screening_queue"].append(i)
    
    total_to_screen = len(db["screening_queue"])
    print(f"Loaded {len(all_entries)} total articles. Previous decisions restored. {total_to_screen} articles remaining to be screened.")
    
    return jsonify({"total_articles": total_to_screen}), 200


@app.route('/decide', methods=['POST'])
def make_decision():
    """
    Records a decision and immediately saves the new state to the backup file.
    """
    data = request.json
    queue_index = data.get('index')
    decision = data.get('decision')
    
    if 0 <= queue_index < len(db["screening_queue"]):
        original_index = db["screening_queue"][queue_index]
        db["decisions"][original_index] = decision
        print(f"Decision for original article index {original_index}: '{decision}'")
        
        # --- NEW: Auto-save state after every decision ---
        _save_state()
        
        return jsonify({"status": "success"}), 200
    return jsonify({"error": "Invalid queue index"}), 400

# The other endpoints (get_article, stats, export_bibtex) do not need to be changed
# from the version in our previous conversation, as they already use the new db structure.
# I am including them here for completeness.

@app.route('/article/<int:queue_index>', methods=['GET'])
def get_article(queue_index):
    if 0 <= queue_index < len(db["screening_queue"]):
        original_index = db["screening_queue"][queue_index]
        return jsonify(db["all_entries"][original_index])
    return jsonify({"error": "Article not found in queue"}), 404
    
@app.route('/stats', methods=['GET'])
def get_stats():
    return jsonify({"total": len(db["screening_queue"]), "screened": 0})

@app.route('/export_bibtex', methods=['GET'])
def export_bibtex():
    updated_entries = []
    for i, entry in enumerate(db["all_entries"]):
        new_entry = entry.copy()
        decision = db["decisions"].get(i)
        if decision:
            new_entry['groups'] = f"SLR_{decision.upper()}"
        elif 'groups' in new_entry:
            # If a decision was made in a previous session (and is in the .bib file),
            # but then removed from the backup, we should respect the original file.
            # This logic just ensures we don't accidentally remove old groups.
            pass
        updated_entries.append(new_entry)

    bib_database = bibtexparser.bibdatabase.BibDatabase()
    bib_database.entries = updated_entries
    
    processed_dir = "bib_files"
    if not os.path.exists(processed_dir): os.makedirs(processed_dir)
    filepath = os.path.join(processed_dir, "processed_articles.bib")
    with open(filepath, 'w', encoding='utf-8') as bibfile:
        bibtexparser.dump(bib_database, bibfile)
        
    return send_from_directory(processed_dir, "processed_articles.bib", as_attachment=True)


if __name__ == '__main__':
    # --- NEW: Load previous state when the server starts ---
    _load_state()
    app.run(debug=True, port=5050)