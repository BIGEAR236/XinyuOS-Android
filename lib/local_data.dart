import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class LocalData {
  final Directory root;
  LocalData(this.root);

  static Future<LocalData> open() async {
    final dir = await getApplicationDocumentsDirectory();
    return LocalData(dir);
  }

  String get dataFilePath => '${root.path}/xinyu_state_v3.json';

  Future<AppData> load() async {
    final file = File(dataFilePath);
    if (!await file.exists()) return AppData.initial();
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) throw const FormatException('本地数据文件格式错误');
    return AppData.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> persist(String text) async {
    final temp = File('$dataFilePath.tmp');
    await temp.writeAsString(text, flush: true);
    await temp.rename(dataFilePath); // atomic replacement on Android/iOS file systems
  }

  Future<String> copyIntoApp(PlatformFile picked, String folder) async {
    final dest = Directory('${root.path}/$folder');
    await dest.create(recursive: true);
    final safeName = picked.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final filename = '${newId()}_$safeName';
    final path = '${dest.path}/$filename';
    if (picked.path != null) {
      await File(picked.path!).copy(path);
    } else {
      // file_picker >=12 uses streaming reads instead of the removed .bytes field.
      final output = File(path).openWrite();
      try {
        await output.addStream(picked.readAsByteStream());
        await output.flush();
      } finally {
        await output.close();
      }
    }
    return '$folder/$filename';
  }

  File resolve(String relativePath) => File('${root.path}/$relativePath');
}

class PersonaFileReader {
  static const maxFileBytes = 2 * 1024 * 1024;
  static const maxTextLength = 26000;

  static Future<String?> pickAndRead() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom, allowedExtensions: ['txt', 'md', 'json', 'docx']);
    if (file == null) return null;
    final fileSize = await file.length();
    if (fileSize != null && fileSize > maxFileBytes) {
      throw const FormatException('人格文件最多支持 2 MB。请先精简后再导入。');
    }
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.length > maxFileBytes) {
      throw const FormatException('人格文件超过 2 MB 大小限制。');
    }
    final ext = file.extension?.toLowerCase() ?? '';
    String text;
    if (ext == 'docx') {
      text = _readDocx(bytes);
    } else {
      text = utf8.decode(bytes, allowMalformed: true).replaceAll('\u0000', '');
      if (ext == 'json') {
        final decoded = jsonDecode(text);
        text = const JsonEncoder.withIndent('  ').convert(decoded);
      }
    }
    text = text.trim();
    if (text.isEmpty) throw const FormatException('没有在文件中找到可读取的人格文本。');
    return text.length > maxTextLength ? text.substring(0, maxTextLength) : text;
  }

  static String _readDocx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.findFile('word/document.xml');
    if (file == null) throw const FormatException('不是有效的 DOCX 文件，或文档没有正文。');
    if (file.size > maxFileBytes) throw const FormatException('DOCX 解压正文过大。');
    String xml = utf8.decode(file.content, allowMalformed: true);
    // Read text of Word paragraphs. No macros, external links or embedded media run.
    xml = xml.replaceAll(RegExp(r'</w:p\s*>'), '\n')
        .replaceAll(RegExp(r'<w:tab\s*/>'), '\t')
        .replaceAll(RegExp(r'<w:br\s*/>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    xml = xml.replaceAllMapped(RegExp(r'&#(x[0-9A-Fa-f]+|\d+);'), (m) {
      final val = m.group(1)!;
      final num = val.startsWith('x')
          ? int.parse(val.substring(1), radix: 16) : int.parse(val);
      return num >= 0 && num <= 0x10FFFF ? String.fromCharCode(num) : '';
    });
    return xml.replaceAll('&lt;', '<').replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"').replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&').trim();
  }
}
