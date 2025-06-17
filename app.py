import os
import json
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
import bibtexparser

# --- Flask App Initialization ---
app = Flask(__name__)
CORS(app)

# --- In-Memory Database ---
db = {
    "current_filename": None,
    "all_entries": [],
    "screening_queue": [],
    "decisions": {}
}

# --- State Management Functions (for Backup/Auto-Save) ---

def _get_backup_filepath():
    """Generates the backup file path based on the current .bib file."""
    if not db.get("current_filename"):
        return None
    safe_filename = os.path.basename(db["current_filename"])
    return f"{safe_filename}.session.json"

def _save_state():
    """Saves the current decisions dictionary to its specific backup file."""
    backup_file = _get_backup_filepath()
    if not backup_file: return
    try:
        state_to_save = {"decisions": db["decisions"]}
        with open(backup_file, 'w', encoding='utf-8') as f:
            json.dump(state_to_save, f, indent=4)
        print(f"State saved to {backup_file}")
    except Exception as e:
        print(f"Error saving state: {e}")

def _load_state():
    """Loads decisions from the specific backup file if it exists."""
    backup_file = _get_backup_filepath()
    if not backup_file: return
    db["decisions"] = {}
    try:
        if os.path.exists(backup_file):
            with open(backup_file, 'r', encoding='utf-8') as f:
                loaded_state = json.load(f)
                db["decisions"] = {int(k): v for k, v in loaded_state.get("decisions", {}).items()}
                print(f"Successfully loaded {len(db['decisions'])} decisions from {backup_file}")
    except Exception as e:
        print(f"Error loading state from {backup_file}: {e}")

# --- API Endpoints ---

@app.route('/load_bibtex', methods=['POST'])
def load_bibtex():
    if 'file' not in request.files: return jsonify({"error": "No file part"}), 400
    original_filename = request.form.get('original_filename')
    if not original_filename: return jsonify({"error": "Filename not provided"}), 400

    db["current_filename"] = original_filename
    _load_state()

    file = request.files['file']
    bib_database = bibtexparser.load(file)
    db["all_entries"] = bib_database.entries
    db["screening_queue"] = []
    
    for i, entry in enumerate(db["all_entries"]):
        has_group = 'groups' in entry and entry['groups']
        has_decision = i in db["decisions"]
        if not has_group and not has_decision:
            db["screening_queue"].append(i)
    
    total_to_screen = len(db["screening_queue"])
    print(f"Loaded {db['current_filename']}. Total entries: {len(db['all_entries'])}. "
          f"Restored {len(db['decisions'])} decisions. Remaining to screen: {total_to_screen}.")
    
    return jsonify({"total_articles": total_to_screen}), 200

@app.route('/article/<int:queue_index>', methods=['GET'])
def get_article(queue_index):
    if 0 <= queue_index < len(db["screening_queue"]):
        original_index = db["screening_queue"][queue_index]
        return jsonify(db["all_entries"][original_index])
    return jsonify({"error": "Article not found in queue"}), 404

@app.route('/decide', methods=['POST'])
def make_decision():
    data = request.json
    queue_index = data.get('index')
    decision = data.get('decision')
    
    if 0 <= queue_index < len(db["screening_queue"]):
        original_index = db["screening_queue"][queue_index]
        db["decisions"][original_index] = decision
        _save_state()
        return jsonify({"status": "success"}), 200
    return jsonify({"error": "Invalid queue index"}), 400
    
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
        updated_entries.append(new_entry)
    bib_database = bibtexparser.bibdatabase.BibDatabase()
    bib_database.entries = updated_entries
    processed_dir = "bib_files"
    if not os.path.exists(processed_dir): os.makedirs(processed_dir)
    filepath = os.path.join(processed_dir, os.path.basename(db["current_filename"] or "processed.bib"))
    with open(filepath, 'w', encoding='utf-8') as bibfile:
        bibtexparser.dump(bib_database, bibfile)
    return send_from_directory(processed_dir, os.path.basename(filepath), as_attachment=True)

# --- Main Application Runner ---
if __name__ == '__main__':
    app.run(host='0.0.0.0', debug=True, port=5000)