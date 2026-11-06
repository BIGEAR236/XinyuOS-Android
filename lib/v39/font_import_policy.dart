/// User-selected font import limit. Validation accepts PlatformFile metadata,
/// not dart:io File: file_picker v13 returns PlatformFile, whose length is nullable.
class FontImportPolicy {
  static const int maxBytes = 50 * 1024 * 1024;

  static String? validate({required String filename, required int? bytes}) {
    final ext = filename.toLowerCase();
    if (!ext.endsWith('.ttf') && !ext.endsWith('.otf')) {
      return '只支持 TTF / OTF 字体文件。';
    }
    if (bytes != null && bytes == 0) return '字体文件为空。';
    if (bytes != null && bytes > maxBytes) return '字体最大支持 50 MB。';
    // Some Android file providers cannot report size until the file is copied.
    // Callers must recheck saved File.length() in app-private storage.
    return null;
  }
}
