// slr_app/lib/main.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart'; // To check for web platform (kIsWeb)

// Make sure the path to your screening page file is correct
import './screening_page.dart'; 

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SLR Screener',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      // Start with the HomePage
      home: const HomePage(),
    );
  }
}

// This is the first screen the user will see
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // Replace the old function in your HomePage widget with this one

Future<void> _loadBibtexFile(BuildContext context) async {
  try {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bib'],
      withData: true,
    );

    if (result != null) {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:5000/load_bibtex'),
      );
      
      if (kIsWeb) {
        final fileBytes = result.files.first.bytes!;
        final fileName = result.files.first.name;

        // Add the filename to the request
        request.fields['original_filename'] = fileName; // <-- ADD THIS LINE

        request.files.add(http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
          contentType: MediaType('application', 'x-bibtex'),
        ));
      } else {
        File file = File(result.files.single.path!);
        
        // Add the filename to the request
        request.fields['original_filename'] = file.path.split(Platform.pathSeparator).last; // <-- ADD THIS LINE

        request.files.add(await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: MediaType('application', 'x-bibtex'),
        ));
      }
      
      // The rest of the function remains the same...
      var response = await request.send();
      if (response.statusCode == 200) {
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ScreeningPage()),
          );
        }
      } else {
        final responseBody = await response.stream.bytesToString();
        print('Failed to upload file. Status code: ${response.statusCode}, Body: $responseBody');
      }
    } else {
      print('No file selected.');
    }
  } catch (e) {
    print('An error occurred: $e');
  }
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SLR Screener - Load File'),
      ),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.file_upload),
          label: const Text('Load .bib File'),
          onPressed: () => _loadBibtexFile(context),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            textStyle: const TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}