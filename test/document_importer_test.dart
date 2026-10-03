import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revai/services/document_importer.dart';

void main() {
  late Directory directory;
  final importer = DocumentImporter();
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('revai-import-'),
  );
  tearDown(() => directory.delete(recursive: true));

  Future<File> file(String name, List<int> bytes) =>
      File('${directory.path}/$name').writeAsBytes(bytes);
  List<int> zip(Map<String, String> parts) {
    final archive = Archive();
    for (final part in parts.entries) {
      final bytes = utf8.encode(part.value);
      archive.addFile(ArchiveFile(part.key, bytes.length, bytes));
    }
    return ZipEncoder().encode(archive);
  }

  test('PPTX follows relationships, keeps slide numbers and joins text runs', () async {
    const slides = 'http://schemas.openxmlformats.org/presentationml/2006/main';
    const drawing = 'http://schemas.openxmlformats.org/drawingml/2006/main';
    const rel =
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
    String slide(String content) =>
        '<x:sld xmlns:x="$slides" xmlns:y="$drawing"><x:cSld><x:spTree>$content</x:spTree></x:cSld></x:sld>';
    final bytes = zip({
      'ppt/presentation.xml':
          '<x:presentation xmlns:x="$slides" xmlns:rel="$rel"><x:sldIdLst><x:sldId id="256" rel:id="second"/><x:sldId id="257" rel:id="empty"/><x:sldId id="258" rel:id="first"/></x:sldIdLst></x:presentation>',
      'ppt/_rels/presentation.xml.rels':
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="first" Type="$rel/slide" Target="slides/slide1.xml"/><Relationship Id="empty" Type="$rel/slide" Target="slides/slide3.xml"/><Relationship Id="second" Type="$rel/slide" Target="/ppt/slides/slide2.xml"/></Relationships>',
      'ppt/slides/slide1.xml': slide(
        '<y:p><y:r><y:t>Last slide.</y:t></y:r></y:p>',
      ),
      'ppt/slides/slide2.xml': slide(
        '<y:p><y:r><y:t>Photo</y:t></y:r><y:r><y:t>synthesis</y:t></y:r><y:br/><y:r><y:t>Uses sunlight.</y:t></y:r></y:p>',
      ),
      'ppt/slides/slide3.xml': slide(''),
    });
    final document = await importer.read(
      await file('lesson.PPTX', bytes),
      'lesson.PPTX',
    );
    expect(document.sections.map((s) => s.label), ['Slide 1', 'Slide 3']);
    expect(document.sections.first.text, 'Photosynthesis\nUses sunlight.');
    expect(document.sections.last.text, 'Last slide.');
  });

  test(
    'DOCX accepts namespace aliases and preserves breaks between words',
    () async {
      final bytes = zip({
        'word/document.xml':
            '<d:document xmlns:d="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><d:body><d:p><d:pPr><d:pStyle d:val="Heading1"/></d:pPr><d:r><d:t>Biology</d:t></d:r></d:p><d:p><d:r><d:t>Cell</d:t><d:tab/><d:t>membrane</d:t><d:br/><d:t>Protects the cell.</d:t></d:r></d:p></d:body></d:document>',
      });
      final document = await importer.read(
        await file('lesson.docx', bytes),
        'lesson.docx',
      );
      expect(document.sections.last.text, 'Cell\tmembrane\nProtects the cell.');
      expect(document.sections.last.label, 'Biology · paragraph 2');
    },
  );

  test('Markdown preserves source wording, headings and line locators', () async {
    const content =
        '# Cells\r\n\r\n**Cells** are the basic unit of life.\r\n\r\n```text\r\n# This is code\r\n```\r\n\r\nEnergy\r\n------\r\nATP stores energy.';
    final document = await importer.read(
      await file('notes.md', utf8.encode(content)),
      'notes.md',
    );
    expect(document.sections[1].text, '**Cells** are the basic unit of life.');
    expect(document.sections[1].label, 'Cells · line 3');
    expect(document.sections[2].label, 'Cells · lines 5–7');
    expect(document.sections.last.label, 'Energy · lines 9–11');
  });

  test(
    'Org source blocks do not create headings and directives stay inert',
    () async {
      const content =
          '* Biology\nCells have membranes.\n\n#+begin_src text\n* not a heading\n#+end_src\n\n** Energy\nATP stores energy.';
      final document = await importer.read(
        await file('notes.org', utf8.encode(content)),
        'notes.org',
      );
      expect(document.sections[1].label, 'Biology · lines 4–6');
      expect(document.sections.last.label, 'Energy · lines 8–9');
      expect(document.text, contains('ATP stores energy.'));
    },
  );

  test('TXT decodes UTF-8 BOM and UTF-16 in both byte orders', () async {
    const content = 'Café 🌿\n\nPlants grow.';
    final encodings = [
      [0xef, 0xbb, 0xbf, ...utf8.encode(content)],
      [
        0xff,
        0xfe,
        for (final unit in content.codeUnits) ...[unit & 255, unit >> 8],
      ],
      [
        0xfe,
        0xff,
        for (final unit in content.codeUnits) ...[unit >> 8, unit & 255],
      ],
    ];
    for (final bytes in encodings) {
      final document = await importer.read(
        await file('notes.txt', bytes),
        'notes.txt',
      );
      expect(document.text, content);
    }
  });

  test(
    'Empty, binary, malformed Office and unsupported files report errors',
    () async {
      for (final entry in <String, List<int>>{
        'empty.txt': utf8.encode(' \n\t'),
        'bad.txt': [0, 1, 2],
        'bad.pptx': [1, 2, 3],
        'bad.docx': zip({'wrong.xml': '<x/>'}),
        'bad.org': [0xff],
        'old.ppt': [1],
      }.entries) {
        await expectLater(
          importer.read(await file(entry.key, entry.value), entry.key),
          throwsA(isA<DocumentImportException>()),
        );
      }
    },
  );
}
