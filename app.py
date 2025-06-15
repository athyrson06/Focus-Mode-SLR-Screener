# app.py (New and Improved Version)

import os
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
import bibtexparser

app = Flask(__name__)
CORS(app)

# Updated database structure to handle the full list and the screening queue separately
db = {
    "all_entries": [],      # Will hold all articles from the .bib file
    "screening_queue": [],  # Will hold only the INDICES of articles needing a review
    "decisions": {}         # Will store decisions by the ORIGINAL index
}

@app.route('/load_bibtex', methods=['POST'])
def load_bibtex():
    """
    Receives a .bib file, parses it, and intelligently creates a queue of
    only the articles that have not already been assigned to a group.
    """
    if 'file' not in request.files:
        return jsonify({"error": "No file part"}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "No selected file"}), 400

    bib_database = bibtexparser.load(file)
    all_entries = bib_database.entries

    # Reset the database for the new session
    db["all_entries"] = all_entries
    db["screening_queue"] = []
    db["decisions"] = {}

    # Populate the screening queue and pre-fill decisions from existing groups
    for i, entry in enumerate(all_entries):
        # Check if the 'groups' field exists and is not empty
        if 'groups' in entry and entry['groups']:
            group_name = entry['groups'].lower()
            # If a group exists, we can log it and pre-populate its decision
            if 'include' in group_name:
                db['decisions'][i] = 'include'
            elif 'exclude' in group_name:
                db['decisions'][i] = 'exclude'
            elif 'maybe' in group_name:
                db['decisions'][i] = 'maybe'
            
            print(f"Article {i} ('{entry.get('ID', 'N/A')}') already has group '{entry['groups']}'. Skipping.")
        else:
            # This article has no group, so add its original index to the queue
            db["screening_queue"].append(i)
    
    total_to_screen = len(db["screening_queue"])
    print(f"Loaded {len(all_entries)} total articles. {total_to_screen} articles are new and have been queued for screening.")
    
    # IMPORTANT: Tell Flutter the size of the QUEUE, not the whole file
    return jsonify({
        "message": "File loaded successfully",
        "total_articles": total_to_screen 
    }), 200

@app.route('/article/<int:queue_index>', methods=['GET'])
def get_article(queue_index):
    """
    Returns an article based on its position in the screening queue, not its position in the original file.
    """
    if 0 <= queue_index < len(db["screening_queue"]):
        # 1. Get the original index from our queue list
        original_index = db["screening_queue"][queue_index]
        # 2. Return the full article data from the master list
        return jsonify(db["all_entries"][original_index])
    return jsonify({"error": "Article not found in queue"}), 404

@app.route('/decide', methods=['POST'])
def make_decision():
    """
    Records a decision for an article based on its position in the screening queue.
    """
    data = request.json
    queue_index = data.get('index')
    decision = data.get('decision')
    
    if 0 <= queue_index < len(db["screening_queue"]):
        # Map the queue index back to the article's original index
        original_index = db["screening_queue"][queue_index]
        db["decisions"][original_index] = decision
        print(f"Decision for original article index {original_index}: '{decision}'")
        return jsonify({"status": "success"}), 200
    return jsonify({"error": "Invalid queue index"}), 400
    
@app.route('/stats', methods=['GET'])
def get_stats():
    """
    Returns the total number of articles TO BE SCREENED in the current session.
    """
    return jsonify({
        "total": len(db["screening_queue"]),
        "screened": 0 # Let the Flutter app handle the count of what it has screened in this session
    })

@app.route('/export_bibtex', methods=['GET'])
def export_bibtex():
    """
    Applies ALL decisions (new and old) to the master list of entries and returns a new file.
    """
    updated_entries = []
    # Iterate through the original, complete list of all articles
    for i, entry in enumerate(db["all_entries"]):
        # Create a mutable copy to avoid modifying the master list in memory
        new_entry = entry.copy()
        
        # Check if there is a new decision for this entry
        decision = db["decisions"].get(i)
        if decision:
            # Apply the new decision, overwriting any old group
            new_entry['groups'] = f"SLR_{decision.upper()}"
        
        updated_entries.append(new_entry)

    bib_database = bibtexparser.bibdatabase.BibDatabase()
    bib_database.entries = updated_entries
    
    processed_dir = "bib_files"
    if not os.path.exists(processed_dir):
        os.makedirs(processed_dir)
    
    filepath = os.path.join(processed_dir, "processed_articles.bib")
    with open(filepath, 'w', encoding='utf-8') as bibfile:
        bibtexparser.dump(bib_database, bibfile)
        
    return send_from_directory(processed_dir, "processed_articles.bib", as_attachment=True)

if __name__ == '__main__':
    app.run(debug=True, port=5000)