// lib/screens/syncfusion_pdf_viewer_screen.dart

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class SyncfusionPdfViewerScreen extends StatefulWidget {
  final String fileUrl;
  final String fileName;

  const SyncfusionPdfViewerScreen({
    super.key,
    required this.fileUrl,
    required this.fileName,
  });

  @override
  State<SyncfusionPdfViewerScreen> createState() =>
      _SyncfusionPdfViewerScreenState();
}

class _SyncfusionPdfViewerScreenState extends State<SyncfusionPdfViewerScreen> {
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        actions: <Widget>[
          IconButton(
            icon: const Icon(
              Icons.bookmark,
              color: Colors.white,
              semanticLabel: 'Bookmark',
            ),
            onPressed: () {
              _pdfViewerKey.currentState?.openBookmarkView();
            },
          ),
        ],
      ),
      // The SfPdfViewer.network widget handles everything for you.
      body: SfPdfViewer.network(widget.fileUrl, key: _pdfViewerKey),
    );
  }
}
