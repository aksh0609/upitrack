import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../parser/statement_parser.dart';

/// The PDF is encrypted (most bank statements are; the password is usually
/// your customer ID or date of birth, see the bank's email).
class PasswordRequired implements Exception {
  const PasswordRequired({required this.wrongPassword});

  final bool wrongPassword;
}

class UnreadableFile implements Exception {
  const UnreadableFile(this.message);

  final String message;

  @override
  String toString() => message;
}

class StatementReader {
  StatementReader._();

  static const List<String> extensions = ['pdf', 'csv'];

  /// Reads a statement file. Everything happens on the phone.
  static Future<StatementResult> read({
    required String fileName,
    required Uint8List bytes,
    String? password,
  }) async {
    final name = fileName.toLowerCase();
    if (name.endsWith('.csv') || name.endsWith('.txt')) {
      return StatementParser.parseCsv(utf8.decode(bytes, allowMalformed: true));
    }
    if (name.endsWith('.pdf')) {
      // PDF text extraction can take a few seconds on long statements, so
      // it runs off the UI thread.
      final (text, error) = await compute(_extractPdfText, (bytes, password));
      if (error != null) {
        final e = error.toLowerCase();
        if (e.contains('password') || e.contains('encrypt')) {
          throw PasswordRequired(wrongPassword: password != null);
        }
        throw UnreadableFile('Could not open this PDF ($error).');
      }
      return StatementParser.parseText(text ?? '');
    }
    throw const UnreadableFile(
        'Only PDF and CSV statements are supported. For Excel files, open '
        'them and save as CSV first.');
  }
}

/// Top-level so it can run in a background isolate.
(String?, String?) _extractPdfText((Uint8List, String?) job) {
  final (bytes, password) = job;
  try {
    final document = PdfDocument(inputBytes: bytes, password: password);
    try {
      return (PdfTextExtractor(document).extractText(layoutText: true), null);
    } finally {
      document.dispose();
    }
  } catch (e) {
    return (null, e.toString());
  }
}
