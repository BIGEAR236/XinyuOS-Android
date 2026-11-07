import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only, per-role digital person configuration. Off by default.
/// API keys never enter JSON preferences, prompt logs, or character documents.
class DigitalPersonConfig {
  final String roleId;
  bool enabled;
  String portraitPath;
  String imageEndpoint;
  String imageModel;
  String sttEndpoint;
  String sttModel;
  String ttsEndpoint;
  String ttsModel;
  String voiceId;
  String voiceSamplePath;
  List<String> portraitGallery;
  List<String> voiceSamples;
  bool voiceConsent;
  double scale;
  double dx;
  double dy;
  DigitalPersonConfig(this.roleId, {this.enabled = false, this.portraitPath = '',
    this.imageEndpoint = '', this.imageModel = '', this.sttEndpoint = '',
    this.sttModel = '', this.ttsEndpoint = '', this.ttsModel = '',
    this.voiceId = '', this.voiceSamplePath = '',
    this.portraitGallery = const [], this.voiceSamples = const [],
    this.voiceConsent = false,
    this.scale = 1.0, this.dx = 0.5, this.dy = 0.33});
  factory DigitalPersonConfig.fromJson(String id, Map<String, dynamic> json) =>
      DigitalPersonConfig(id,
        enabled: json['enabled'] == true,
        portraitPath: '${json['portraitPath'] ?? ''}',
        imageEndpoint: '${json['imageEndpoint'] ?? ''}',
        imageModel: '${json['imageModel'] ?? ''}',
        sttEndpoint: '${json['sttEndpoint'] ?? ''}',
        sttModel: '${json['sttModel'] ?? ''}',
        ttsEndpoint: '${json['ttsEndpoint'] ?? ''}',
        ttsModel: '${json['ttsModel'] ?? ''}',
        voiceId: '${json['voiceId'] ?? ''}',
        voiceSamplePath: '${json['voiceSamplePath'] ?? ''}',
        portraitGallery: (json['portraitGallery'] is List)
          ? (json['portraitGallery'] as List).map((e)=>'$e').toList() : [],
        voiceSamples: (json['voiceSamples'] is List)
          ? (json['voiceSamples'] as List).map((e)=>'$e').toList() : [],
        voiceConsent: json['voiceConsent'] == true,
        scale: ((json['scale'] as num?) ?? 1).toDouble().clamp(.5, 1.8).toDouble(),
        dx: ((json['dx'] as num?) ?? .5).toDouble().clamp(0, 1).toDouble(),
        dy: ((json['dy'] as num?) ?? .33).toDouble().clamp(0, 1).toDouble());
  Map<String, dynamic> toJson() => {
    'enabled': enabled, 'portraitPath': portraitPath,
    'imageEndpoint': imageEndpoint, 'imageModel': imageModel,
    'sttEndpoint': sttEndpoint, 'sttModel': sttModel,
    'ttsEndpoint': ttsEndpoint, 'ttsModel': ttsModel,
    'voiceId': voiceId, 'voiceSamplePath': voiceSamplePath,
    'portraitGallery':portraitGallery,'voiceSamples':voiceSamples,
    'voiceConsent': voiceConsent, 'scale': scale, 'dx': dx, 'dy': dy,
  };
}

class DigitalPersonStore {
  static const _keys = FlutterSecureStorage();
  static final _prefs = SharedPreferencesAsync();
  static String _roleKey(String id) => 'v41.digitalPerson.${Uri.encodeComponent(id)}';
  static String _secretKey(String id, String type) =>
      'v41.digitalSecret.${Uri.encodeComponent(id)}.$type';

  static Future<DigitalPersonConfig> load(String id) async {
    try {
      final raw = await _prefs.getString(_roleKey(id));
      if (raw == null) return DigitalPersonConfig(id);
      final result=DigitalPersonConfig.fromJson(id, Map<String, dynamic>.from(jsonDecode(raw)));
      if(result.portraitPath.isNotEmpty&&!result.portraitGallery.contains(result.portraitPath)) {
        result.portraitGallery=[...result.portraitGallery,result.portraitPath];
      }
      if(result.voiceSamplePath.isNotEmpty&&!result.voiceSamples.contains(result.voiceSamplePath)) {
        result.voiceSamples=[...result.voiceSamples,result.voiceSamplePath];
      }
      return result;
    } catch (_) {
      return DigitalPersonConfig(id);
    }
  }
  static Future<void> save(DigitalPersonConfig config) =>
      _prefs.setString(_roleKey(config.roleId), jsonEncode(config.toJson()));
  static Future<void> setKey(String roleId, String kind, String value) async {
    if (value.trim().isEmpty) return;
    await _keys.write(key: _secretKey(roleId, kind), value: value.trim());
  }
  static Future<String> getKey(String roleId, String kind) async =>
      await _keys.read(key: _secretKey(roleId, kind)) ?? '';

  static Future<String> saveMedia(String roleId, String extension, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 15 * 1024 * 1024) {
      throw const FormatException('单份图片/音频样本需在 1B～15MB 内。');
    }
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/v41_digital_people');
    await directory.create(recursive: true);
    final cleaned = roleId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final suffix = extension.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final file = File('${directory.path}/${cleaned}_${DateTime.now().microsecondsSinceEpoch}.$suffix');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}

class DigitalPersonApi {
  static Uri _https(String value) {
    final uri = Uri.parse(value.trim());
    if (uri.scheme != 'https' || !uri.hasAuthority || uri.userInfo.isNotEmpty) {
      throw const FormatException('数字人外部 API 必须为可信 HTTPS 地址。');
    }
    return uri;
  }
  static Future<Uint8List> generatePortrait({required String endpoint,
      required String model, required String key, required String prompt}) async {
    final uri = _https(endpoint);
    if (key.isEmpty || model.isEmpty) throw StateError('请先配置文生图模型与密钥。');
    final client = http.Client();
    try {
      final response = await client.post(uri,
        headers: {'Authorization': 'Bearer $key', 'Content-Type': 'application/json'},
        body: jsonEncode({'model': model, 'prompt': prompt, 'size': '1024x1024',
          'response_format': 'b64_json'})).timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('图片 API 请求失败（HTTP ${response.statusCode}）。');
      }
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final items = root['data'] as List?;
      if (items == null || items.isEmpty || items.first is! Map) {
        throw const FormatException('当前服务商没有返回兼容的图片数据。');
      }
      final item = Map<String, dynamic>.from(items.first as Map);
      final b64 = item['b64_json'];
      if (b64 is String && b64.isNotEmpty) return base64Decode(b64);
      final url = item['url'];
      if (url is String && url.isNotEmpty) {
        final target = _https(url);
        final download = await client.get(target).timeout(const Duration(seconds: 40));
        if (download.statusCode != 200 || download.bodyBytes.length > 15 * 1024 * 1024) {
          throw const FormatException('图片下载失败或图片过大。');
        }
        return download.bodyBytes;
      }
      throw const FormatException('服务商既未返回 b64_json，也未返回图片 URL。');
    } finally { client.close(); }
  }

  static Future<String> transcribe({required String endpoint,
      required String model, required String key, required File audio}) async {
    final uri = _https(endpoint);
    if (key.isEmpty || model.isEmpty) throw StateError('尚未配置语音识别 API。');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $key'
      ..fields['model'] = model
      ..files.add(await http.MultipartFile.fromPath('file', audio.path));
    final client = http.Client();
    try {
      final response = await client.send(request).timeout(const Duration(seconds: 60));
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('语音识别请求失败（HTTP ${response.statusCode}）。');
      }
      final result = jsonDecode(body) as Map<String, dynamic>;
      return '${result['text'] ?? ''}'.trim();
    } finally { client.close(); }
  }

  static Future<Uint8List> synthesize({required String endpoint, required String model,
      required String voice, required String key, required String text}) async {
    final uri = _https(endpoint);
    if (key.isEmpty || model.isEmpty || voice.isEmpty) {
      throw StateError('尚未配置语音合成 API 和音色 ID。');
    }
    final client = http.Client();
    try {
      final response = await client.post(uri,
        headers: {'Authorization': 'Bearer $key', 'Content-Type': 'application/json'},
        body: jsonEncode({'model': model, 'voice': voice, 'input': text,
          'response_format': 'mp3'})).timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('语音合成请求失败（HTTP ${response.statusCode}）。');
      }
      if (response.bodyBytes.length > 15 * 1024 * 1024) {
        throw const FormatException('语音结果超出 15MB 限制。');
      }
      return response.bodyBytes;
    } finally { client.close(); }
  }
}
