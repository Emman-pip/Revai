import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/quiz.dart';

class QuizPdfExporter {
  Future<void> share(SavedQuiz quiz) async {
    final bytes = await build(quiz);
    await Printing.sharePdf(bytes: bytes, filename: _fileName(quiz));
  }

  Future<File> save(SavedQuiz quiz) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${_fileName(quiz)}');
    await file.writeAsBytes(await build(quiz), flush: true);
    return file;
  }

  Future<Uint8List> build(SavedQuiz quiz) async {
    final document = pw.Document(title: quiz.title, author: 'Revai');
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(42),
        header: (_) => _header(quiz, 'QUIZ'),
        build: (context) => [
          pw.SizedBox(height: 16),
          pw.Text(
            quiz.title,
            style: const pw.TextStyle(
              fontSize: 21,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Name: ___________________________________    Date: ______________',
          ),
          pw.SizedBox(height: 20),
          for (var i = 0; i < quiz.questions.length; i++)
            ..._questionWidgets(i + 1, quiz.questions[i]),
        ],
      ),
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(42),
        header: (_) => _header(quiz, 'ANSWER KEY'),
        build: (context) => [
          pw.Text(
            'Answer key',
            style: const pw.TextStyle(
              fontSize: 21,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 18),
          for (var i = 0; i < quiz.questions.length; i++)
            _answerWidget(i + 1, quiz.questions[i]),
        ],
      ),
    );
    return document.save();
  }

  pw.Widget _header(SavedQuiz quiz, String label) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 8),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'REVAI  /  ${quiz.title}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.Text(
          label,
          style: const pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  List<pw.Widget> _questionWidgets(int number, QuizQuestion question) => [
    pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '$number. ${question.prompt}',
            style: const pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          if (question.kind == QuestionKind.multipleChoice)
            for (var i = 0; i < question.options.length; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 3),
                child: pw.Text(
                  '${String.fromCharCode(65 + i)}.  ${question.options[i]}',
                ),
              )
          else ...[
            pw.SizedBox(height: 14),
            pw.Container(height: 1, color: PdfColors.grey600),
            pw.SizedBox(height: 18),
            pw.Container(height: 1, color: PdfColors.grey600),
          ],
        ],
      ),
    ),
  ];

  pw.Widget _answerWidget(int number, QuizQuestion question) {
    final option = question.kind == QuestionKind.multipleChoice
        ? question.options.indexWhere((value) => value == question.answer)
        : -1;
    final answer = option >= 0
        ? '${String.fromCharCode(65 + option)}. ${question.answer}'
        : question.answer;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 13),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '$number. $answer',
            style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (question.explanation.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text(
                question.explanation,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Text(
              'Source: ${question.sourceLabel}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ),
        ],
      ),
    );
  }

  String _fileName(SavedQuiz quiz) =>
      '${quiz.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}.pdf';
}
