// lib/screens/file_preview_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p; // For getting the file name

class FilePreviewScreen extends StatefulWidget {
  final File file;
  const FilePreviewScreen({super.key, required this.file});

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  final TextEditingController _captionController = TextEditingController();

  // Helper to check if the file is an image based on extension
  bool get _isImage {
    final extension = p.extension(widget.file.path).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.gif'].contains(extension);
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Expanded to take up most of the screen for the preview
            Expanded(
              child: Center(
                child:
                    _isImage
                        ? Image.file(widget.file, fit: BoxFit.contain)
                        : Container(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.insert_drive_file_rounded,
                                color: Colors.white70,
                                size: 100,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                p.basename(
                                  widget.file.path,
                                ), // Display file name
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
              ),
            ),

            // Caption input field and send button at the bottom
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8.0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(25.0),
                      ),
                      child: TextField(
                        controller: _captionController,
                        style: const TextStyle(
                          color: Color.fromARGB(255, 0, 0, 0),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Add a caption...',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18.0,
                          ),
                          hintStyle: TextStyle(color: Colors.grey[400]),
                        ),
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send Button
                  FloatingActionButton(
                    mini: false,
                    onPressed: () {
                      // Pop the screen and return the caption text
                      Navigator.of(context).pop(_captionController.text.trim());
                    },
                    child: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
