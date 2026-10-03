import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import '../models/quiz.dart';

class DocumentImportException implements Exception {
  const DocumentImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

class DocumentImporter {
  static const supportedExtensions = [
    'pdf',
    'docx',
    'pptx',
    'org',
    'md',
    'txt',
  ];

  Future<SourceDocument> read(File file, String name) async {
    final extension = name.split('.').last.toLowerCase();
    if (!supportedExtensions.contains(extension)) {
      throw const DocumentImportException(
        'Choose a PDF, DOCX, PPTX, Org (.org), Markdown (.md), or text (.txt) file.',
      );
    }
    if (extension == 'pdf') return _readPdf(file, name);
    final bytes = await file.readAsBytes();
    if (extension == 'docx' || extension == 'pptx') {
      try {
        final archive = ZipDecoder().decodeBytes(bytes);
        return extension == 'docx'
            ? _readDocx(archive, name)
            : _readPptx(archive, name);
      } on DocumentImportException {
        rethrow;
      } catch (_) {
        throw DocumentImportException(
          'Could not read this ${extension.toUpperCase()} file. '
          'Open it in an editor and save a new, unencrypted copy, then retry.',
        );
      }
    }
    try {
      return _readText(_decodeText(bytes), name, extension);
    } on FormatException {
      throw const DocumentImportException(
        'Could not read this text file. Save it as UTF-8 or UTF-16 with a byte-order mark and retry.',
      );
    }
  }

  Future<SourceDocument> _readPdf(File file, String name) async {
    final document = await PdfDocument.openFile(file.path);
    try {
      final sections = <SourceSection>[];
      for (final page in document.pages) {
        final text = (await page.loadStructuredText()).fullText.trim();
        if (text.isNotEmpty) {
          sections.add(
            SourceSection(
              id: 'p${page.pageNumber}',
              label: 'Page ${page.pageNumber}',
              text: text,
            ),
          );
        }
      }
      if (sections.isEmpty) {
        throw const DocumentImportException(
          'No selectable text was found. This may be a scanned PDF; scanned pages need OCR, which is not supported yet.',
        );
      }
      return SourceDocument(name: name, extension: 'pdf', sections: sections);
    } finally {
      await document.dispose();
    }
  }

  SourceDocument _readDocx(Archive archive, String name) {
    final xml = _xmlPart(archive, 'word/document.xml');
    final body = _elements(xml, 'body').firstOrNull;
    if (body == null) {
      throw const DocumentImportException('No document body was found.');
    }
    final sections = <SourceSection>[];
    var heading = 'Document';
    var paragraphNumber = 0;
    for (final paragraph in _elements(body, 'p')) {
      paragraphNumber++;
      final text = _paragraphText(paragraph);
      if (text.isEmpty) continue;
      final style = _elements(
        paragraph,
        'pStyle',
      ).map((node) => node.getAttribute('val', namespaceUri: '*')).firstOrNull;
      if (style != null && style.toLowerCase().startsWith('heading')) {
        heading = text;
      }
      sections.add(
        SourceSection(
          id: 'd$paragraphNumber',
          label: '$heading · paragraph $paragraphNumber',
          text: text,
        ),
      );
    }
    return _withText(name, 'docx', sections);
  }

  SourceDocument _readPptx(Archive archive, String name) {
    final presentation = _xmlPart(archive, 'ppt/presentation.xml');
    final relationships = _xmlPart(archive, 'ppt/_rels/presentation.xml.rels');
    final targets = <String, String>{};
    for (final relationship in _elements(relationships, 'Relationship')) {
      if (relationship.getAttribute('TargetMode') == 'External' ||
          !(relationship.getAttribute('Type') ?? '').endsWith('/slide')) {
        continue;
      }
      final id = relationship.getAttribute('Id');
      final target = relationship.getAttribute('Target');
      if (id != null && target != null) targets[id] = target;
    }
    final sections = <SourceSection>[];
    var slideNumber = 0;
    // PowerPoint's slide order comes from this list, not ZIP entry names.
    for (final slideId in _elements(presentation, 'sldId')) {
      slideNumber++;
      final relationshipId = slideId.attributes
          .where(
            (attribute) =>
                attribute.name.local == 'id' &&
                (attribute.namespaceUri ?? '').endsWith('/relationships'),
          )
          .firstOrNull
          ?.value;
      final target = targets[relationshipId];
      if (target == null) {
        throw DocumentImportException(
          'Slide $slideNumber is missing from this PPTX file.',
        );
      }
      final uri = Uri.parse('package:/ppt/presentation.xml').resolve(target);
      if (uri.scheme != 'package' ||
          uri.hasAuthority ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw const DocumentImportException(
          'This PPTX contains an unsupported slide reference.',
        );
      }
      final slide = _xmlPart(
        archive,
        Uri.decodeComponent(uri.path.substring(1)),
      );
      final text = _elements(
        slide,
        'p',
      ).map(_paragraphText).where((text) => text.isNotEmpty).join('\n');
      if (text.isNotEmpty) {
        sections.add(
          SourceSection(
            id: 's$slideNumber',
            label: 'Slide $slideNumber',
            text: text,
          ),
        );
      }
    }
    if (sections.isEmpty) {
      throw const DocumentImportException(
        'No slide text was found. Slides containing only images need OCR, which is not supported yet.',
      );
    }
    return _withText(name, 'pptx', sections);
  }

  SourceDocument _readText(String text, String name, String extension) {
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final sections = <SourceSection>[];
    final buffer = <String>[];
    var heading = 'Document';
    var startLine = 1;
    var endLine = 1;
    var length = 0;
    String? fence;
    var fenceLength = 0;
    var orgBlock = false;

    void flush() {
      final content = buffer.join('\n').trim();
      if (content.isNotEmpty) {
        final location = startLine == endLine
            ? 'line $startLine'
            : 'lines $startLine–$endLine';
        sections.add(
          SourceSection(
            id: 't${sections.length + 1}',
            label: '$heading · $location',
            text: content,
          ),
        );
      }
      buffer.clear();
      length = 0;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      String? nextHeading;
      if (extension == 'md') {
        final marker = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
        if (marker != null) {
          final run = marker.group(1)!;
          if (fence == null) {
            fence = run[0];
            fenceLength = run.length;
          } else if (run[0] == fence &&
              run.length >= fenceLength &&
              line.substring(marker.end).trim().isEmpty) {
            fence = null;
          }
        } else if (fence == null) {
          nextHeading = RegExp(
            r'^ {0,3}#{1,6}\s+(.+?)\s*#*\s*$',
          ).firstMatch(line)?.group(1);
          if (nextHeading == null &&
              line.trim().isNotEmpty &&
              i + 1 < lines.length &&
              RegExp(r'^ {0,3}(=+|-+)\s*$').hasMatch(lines[i + 1])) {
            nextHeading = line.trim();
          }
        }
      } else if (extension == 'org') {
        if (RegExp(r'^\s*#\+begin_', caseSensitive: false).hasMatch(line)) {
          orgBlock = true;
        }
        if (!orgBlock) {
          nextHeading = RegExp(r'^\*+\s+(.+)$').firstMatch(line)?.group(1);
        }
        if (RegExp(r'^\s*#\+end_', caseSensitive: false).hasMatch(line)) {
          orgBlock = false;
        }
      }
      if (nextHeading != null) {
        flush();
        heading = nextHeading;
      }
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      // Bound section size while keeping source wording and line locations.
      var remaining = line;
      while (remaining.isNotEmpty) {
        var split = remaining.length;
        if (split > 4000) {
          split = remaining.lastIndexOf(RegExp(r'\s'), 4000);
          if (split <= 0) split = 4000;
        }
        final part = remaining.substring(0, split);
        if (length + part.length > 4000) flush();
        if (buffer.isEmpty) startLine = i + 1;
        endLine = i + 1;
        buffer.add(part);
        length += part.length + 1;
        remaining = remaining.substring(split).trimLeft();
        if (remaining.isNotEmpty) flush();
      }
    }
    flush();
    return _withText(name, extension, sections);
  }

  SourceDocument _withText(
    String name,
    String extension,
    List<SourceSection> sections,
  ) {
    if (sections.isEmpty) {
      throw DocumentImportException(
        'No text was found in this ${extension.toUpperCase()} file.',
      );
    }
    return SourceDocument(name: name, extension: extension, sections: sections);
  }

  XmlDocument _xmlPart(Archive archive, String path) {
    final entry = archive.findFile(path);
    if (entry == null) {
      throw DocumentImportException('This document is missing $path.');
    }
    return XmlDocument.parse(_decodeText(entry.content));
  }

  Iterable<XmlElement> _elements(XmlNode node, String localName) =>
      node.findAllElements(localName, namespaceUri: '*');

  String _paragraphText(XmlElement paragraph) {
    final result = StringBuffer();
    for (final element in paragraph.descendants.whereType<XmlElement>()) {
      if (element.namespaceUri != paragraph.namespaceUri) continue;
      switch (element.name.local) {
        case 't':
          result.write(element.innerText);
        case 'tab':
          result.write('\t');
        case 'br':
        case 'cr':
          result.write('\n');
      }
    }
    return result.toString().trim();
  }

  String _decodeText(List<int> bytes) {
    String text;
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff))) {
      if (bytes.length.isOdd) {
        throw const FormatException('Incomplete UTF-16 character');
      }
      final littleEndian = bytes[0] == 0xff;
      final units = <int>[];
      for (var i = 2; i < bytes.length; i += 2) {
        units.add(
          littleEndian
              ? bytes[i] | bytes[i + 1] << 8
              : bytes[i] << 8 | bytes[i + 1],
        );
      }
      for (var i = 0; i < units.length; i++) {
        if (units[i] >= 0xd800 && units[i] <= 0xdbff) {
          if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
            throw const FormatException('Invalid UTF-16 surrogate');
          }
        } else if (units[i] >= 0xdc00 && units[i] <= 0xdfff) {
          throw const FormatException('Invalid UTF-16 surrogate');
        }
      }
      text = String.fromCharCodes(units);
    } else {
      text = utf8.decode(bytes);
    }
    if (text.startsWith('\ufeff')) text = text.substring(1);
    if (RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]').hasMatch(text)) {
      throw const FormatException('Binary content');
    }
    return text;
  }
}
