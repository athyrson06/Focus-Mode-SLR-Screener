import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';
import 'dart:async'; // For TimeoutException

class ScreeningPage extends StatefulWidget {
  const ScreeningPage({super.key});

  @override
  State<ScreeningPage> createState() => _ScreeningPageState();
}

class _ScreeningPageState extends State<ScreeningPage> {
  // --- STATE VARIABLES ---
  // These variables hold the current state of the screening process.
  int _currentIndex = 0;
  int _screenedCount = 0;
  int _totalArticles = 0;
  Map<String, dynamic>? _currentArticle;
  bool _isLoading = true;
  String _errorMessage = '';

  // Keywords for highlighting in the abstract.
  final List<String> inclusionKeywords = [
    'gam', 
    'gamm', 
    'generalized additive', // Handles multi-word phrases
    'ebm', 
    'xai',
    'explainab', // Catches 'explainable', 'explainability'
    'interpret', // Catches 'interpretable', 'interpretability', 'interpreting'
    'intelligib' // Catches 'intelligible'
  ];

  final List<String> exclusionKeywords = ['review', 'survey', 'overview'];

  @override
  void initState() {
    super.initState();
    // Start the process when the page first loads.
    _initializeScreening();
  }

  Future<void> _initializeScreening() async {
    await _fetchStats();
    await _loadArticle(_currentIndex);
  }

  // --- API FUNCTIONS ---
  // These functions communicate with the Python backend.

  Future<void> _fetchStats() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:5000/stats'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _totalArticles = data['total'];
          _screenedCount = data['screened'];
        });
      }
    } catch (e) {
      print("Error fetching stats: $e");
    }
  }

  Future<void> _loadArticle(int index) async {
    if (index >= _totalArticles && _totalArticles > 0) {
      setState(() {
        _currentArticle = {"title": "Screening Complete!", "abstract": "You have reviewed all articles."};
        _isLoading = false;
      });
      return;
    }

    setState(() { _isLoading = true; _errorMessage = ''; });

    try {
      print("Flutter: Fetching article at index $index...");
      final response = await http.get(Uri.parse('http://127.0.0.1:5000/article/$index'));
      
      if (response.statusCode == 200) {
        print("Flutter: Successfully received article $index.");
        setState(() {
          _currentArticle = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        print("Flutter: Failed to load article $index. Status: ${response.statusCode}");
        setState(() {
          _errorMessage = "Failed to load article. Please try again.";
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Flutter: An error occurred while fetching article $index: $e");
      setState(() {
        _errorMessage = "An error occurred. Check the Python server and your connection.";
        _isLoading = false;
      });
    }
  }

  Future<void> _makeDecision(String decision) async {
    // Prevent making a decision if screening is complete
    if (_currentIndex >= _totalArticles) return;

    try {
        await http.post(
        Uri.parse('http://127.0.0.1:5000/decide'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'index': _currentIndex, 'decision': decision}),
      );
      setState(() { _currentIndex++; _screenedCount++; });
      _loadArticle(_currentIndex);

    } catch (e) {
      print("Flutter: Failed to send decision for article $_currentIndex: $e");
    }
  }

  Future<void> _exportBibtex() async {
    try {
      print("Flutter: Requesting export...");
      final response = await http.get(Uri.parse('http://127.0.0.1:5000/export_bibtex'));

      if (response.statusCode == 200) {
        // Get the raw bytes of the file content
        final Uint8List fileBytes = response.bodyBytes;

        // Use file_saver to save the file. This works on web, desktop, and mobile!
        await FileSaver.instance.saveFile(
          name: 'processed_articles', // The name of the file
          bytes: fileBytes,           // The file content
          ext: 'bib',                 // The file extension
          mimeType: MimeType.text     // The file type
        );

        print("Flutter: File save request sent successfully.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File saved successfully!'), backgroundColor: Colors.green),
          );
        }
      } else {
        print("Flutter: Failed to export file. Status: ${response.statusCode}");
      }
    } catch (e) {
      print("Flutter: An error occurred during export: $e");
    }
  }

  

  // --- WIDGET BUILDING ---
  // Replace the old function with this new, more powerful version.
// Replace the old function with this version to fix the deprecation warning.
  // slr_app/lib/screening_page.dart -> inside _ScreeningPageState

// --- NEW FUNCTION 1: A helper that styles a single paragraph ---
// This contains our previous highlighting logic.
  RichText _createHighlightedParagraph(String text) {
    List<TextSpan> textSpans = [];
    final String allKeywordsPattern = (inclusionKeywords + exclusionKeywords).join('|');
    final RegExp pattern = RegExp(r'\b(' + allKeywordsPattern + r')\w*\b', caseSensitive: false);

    text.splitMapJoin(
      pattern,
      onMatch: (Match match) {
        String word = match.group(0)!;
        TextStyle style;
        if (inclusionKeywords.any((keyword) => word.toLowerCase().startsWith(keyword))) {
          style = TextStyle(
            fontSize: 18, color: Colors.black87, height: 1.5,
            backgroundColor: Colors.green.withAlpha(77),
            fontWeight: FontWeight.bold
          );
        } else {
          style = TextStyle(
            fontSize: 18, color: Colors.black87, height: 1.5,
            backgroundColor: Colors.orange.withAlpha(77),
            fontWeight: FontWeight.bold
          );
        }
        textSpans.add(TextSpan(text: word, style: style));
        return '';
      },
      onNonMatch: (String nonMatch) {
        textSpans.add(TextSpan(
          text: nonMatch,
          style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.5)
        ));
        return '';
      },
    );
    return RichText(text: TextSpan(children: textSpans));
  }

// --- NEW FUNCTION 2: This is the main function that builds the paragraphs ---
// It splits the abstract into sentences, groups them, and then uses the helper above.
  Widget _buildParagraphsFromAbstract(String abstractText) {
    // Regex to split text into sentences while keeping the punctuation.
    final sentencePattern = RegExp(r'(?<=[.?!])\s*');
    final sentences = abstractText.split(sentencePattern).where((s) => s.isNotEmpty).toList();
    
    List<Widget> paragraphs = [];

    // Group sentences into paragraphs of 2
    for (int i = 0; i < sentences.length; i += 2) {
      String paragraphText;
      if (i + 1 < sentences.length) {
        // Combine two sentences
        paragraphText = "${sentences[i]} ${sentences[i+1]}";
      } else {
        // Handle the last sentence if it's an odd one out
        paragraphText = sentences[i];
      }
      
      // Create a styled paragraph and add it to our list of widgets
      paragraphs.add(_createHighlightedParagraph(paragraphText));
      
      // Add some vertical space between paragraphs
      paragraphs.add(const SizedBox(height: 16.0));
    }
    
    // Return all the paragraph widgets arranged in a column
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: paragraphs,
    );
  }

  @override
  Widget build(BuildContext context) {
    String titleText = 'Screening: $_screenedCount / $_totalArticles';
    if (_currentIndex >= _totalArticles && _totalArticles > 0) {
        titleText = "Screening Complete!";
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.save_alt),
            label: const Text('Export BibTeX'),
            onPressed: _exportBibtex,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage.isNotEmpty
                ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontSize: 18)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Card(
                          elevation: 4,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentArticle?['title'] ?? 'No Title',
                                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 16),
                                Text("Authors: ${_currentArticle?['author'] ?? 'N/A'}", style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic)),
                                Text("Journal: ${_currentArticle?['journal'] ?? 'N/A'}, ${_currentArticle?['year'] ?? ''}", style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic)),
                                const Divider(height: 32),
                                
                                // --- CORRECTED SECTION START ---
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'Abstract:',
                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.copy_all_rounded),
                                      tooltip: 'Copy Abstract to Clipboard',
                                      color: Colors.grey.shade600,
                                      onPressed: () {
                                        final abstractText = _currentArticle?['abstract'] ?? '';
                                        Clipboard.setData(ClipboardData(text: abstractText));
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                            content: Text('Abstract copied to clipboard!'),
                                            duration: Duration(seconds: 2)));
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // This line was missing and is now restored:
                                _buildParagraphsFromAbstract(_currentArticle?['abstract'] ?? 'No Abstract.'),
                                // --- CORRECTED SECTION END ---
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Only show decision buttons if screening is not complete
                      if (_currentIndex < _totalArticles)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton.icon(icon: const Icon(Icons.check_circle), label: const Text('INCLUDE'), onPressed: () => _makeDecision('include'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15))),
                            ElevatedButton.icon(icon: const Icon(Icons.help), label: const Text('MAYBE'), onPressed: () => _makeDecision('maybe'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15))),
                            ElevatedButton.icon(icon: const Icon(Icons.cancel), label: const Text('EXCLUDE'), onPressed: () => _makeDecision('exclude'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15))),
                          ],
                        )
                    ],
                  ),
      ),
    );
  }

}