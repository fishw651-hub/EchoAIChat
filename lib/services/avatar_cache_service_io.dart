import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart' as pp;

import '../utils/server_url.dart';

/// IO 平台实现：头像下载到应用文档目录 avatar_cache/。
const _dirName = 'avatar_cache';
final Set<String> _inFlight = {};

/// 由服务器相对路径生成安全的缓存文件名（纯函数，便于测试）
String avatarCacheFileName(String raw) {
  final base = raw.split('/').last.split('?').first;
  final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return safe.isEmpty ? 'avatar' : safe;
}

Future<Directory?> _dir() async {
  try {
    final docs = await pp.getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  } catch (_) {
    return null;
  }
}

Future<File?> _cachedFile(String raw) async {
  final dir = await _dir();
  if (dir == null) return null;
  final f = File('${dir.path}/${avatarCacheFileName(raw)}');
  return await f.exists() ? f : null;
}

Future<File?> _download(String url, String raw) async {
  if (!_inFlight.add(raw)) return null;
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close();
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      return null;
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in resp) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) return null;
    final dir = await _dir();
    if (dir == null) return null;
    final f = File('${dir.path}/${avatarCacheFileName(raw)}');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  } catch (_) {
    return null;
  } finally {
    client.close();
    _inFlight.remove(raw);
  }
}

Future<ImageProvider?> resolveAvatarImage(String? raw) async {
  if (raw == null || raw.isEmpty) return null;
  final url = resolveServerUrl(raw);
  if (url == null) return null;
  final cached = await _cachedFile(raw);
  if (cached != null) return FileImage(cached);
  final downloaded = await _download(url, raw);
  if (downloaded != null) return FileImage(downloaded);
  return NetworkImage(url);
}

Future<void> refreshForUser(String? avatarRaw) async {
  if (avatarRaw == null || avatarRaw.isEmpty) return;
  final url = resolveServerUrl(avatarRaw);
  if (url == null) return;
  final current = await _cachedFile(avatarRaw) ?? await _download(url, avatarRaw);
  if (current == null) return;
  // 清理旧头像缓存文件，避免无限增长
  final dir = await _dir();
  if (dir == null) return;
  try {
    await for (final e in dir.list()) {
      if (e is File && e.path != current.path) await e.delete();
    }
  } catch (_) {}
}
