import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

/// 读进来的文件。
class OpenedFile {
  const OpenedFile({required this.name, required this.content, this.path});

  final String name;
  final String content;

  /// 可回写的本地路径。Android 通过 SAF 选的文件拿到的是 `content://` URI，
  /// 这里为 null —— 下次保存必须重新让用户选位置。
  final String? path;
}

/// 用户挑的一张图片。
class PickedImage {
  const PickedImage({
    required this.bytes,
    required this.mimeType,
    required this.name,
  });

  final Uint8List bytes;
  final String mimeType;
  final String name;
}

/// 系统文件对话框 + 本地读写。
///
/// 全部失败路径都返回 null/false 而不是抛异常：用户点了取消、系统没有文件
/// 管理器、沙箱拒绝写入，这些都是正常情况，不该让应用崩在一个对话框上。
class DocumentStore {
  DocumentStore._();

  static const XTypeGroup _wbType = XTypeGroup(
    label: 'wb-pro 白板',
    extensions: <String>['wbpro'],
    mimeTypes: <String>['application/json'],
    uniformTypeIdentifiers: <String>['public.json'],
  );

  static const XTypeGroup _imageType = XTypeGroup(
    label: '图片',
    extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
    mimeTypes: <String>['image/*'],
    uniformTypeIdentifiers: <String>['public.image'],
  );

  static String? _lastDirectory;

  static String _ensureExtension(String name, String extension) =>
      name.toLowerCase().endsWith('.$extension') ? name : '$name.$extension';

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }

  /// 去掉 `.wbpro` 后缀，作为文档显示名。
  static String displayNameOf(String pathOrName) {
    final base = _basename(pathOrName);
    final dot = base.lastIndexOf('.');
    return dot <= 0 ? base : base.substring(0, dot);
  }

  static bool _looksWritable(String? path) {
    if (path == null || path.isEmpty) return false;
    if (path.contains('://')) return false;
    return true;
  }

  static Future<OpenedFile?> openDocument() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[_wbType],
        initialDirectory: _lastDirectory,
      );
      if (file == null) return null;
      final content = await file.readAsString();
      final path = _looksWritable(file.path) ? file.path : null;
      if (path != null) _lastDirectory = File(path).parent.path;
      return OpenedFile(
        name: displayNameOf(file.name.isEmpty ? path ?? '未命名白板' : file.name),
        content: content,
        path: path,
      );
    } catch (_) {
      return null;
    }
  }

  /// 直接读一个已知路径（最近文件、命令行参数）。
  static Future<OpenedFile?> readPath(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      _lastDirectory = file.parent.path;
      return OpenedFile(
        name: displayNameOf(path),
        content: content,
        path: path,
      );
    } catch (_) {
      return null;
    }
  }

  /// 弹出保存对话框，返回目标路径。用户取消返回 null。
  static Future<String?> chooseSavePath(
    String suggestedName, {
    String extension = 'wbpro',
    String label = 'wb-pro 白板',
  }) async {
    try {
      final type = extension == 'wbpro'
          ? _wbType
          : XTypeGroup(label: label, extensions: <String>[extension]);
      final location = await getSaveLocation(
        suggestedName: _ensureExtension(suggestedName, extension),
        acceptedTypeGroups: <XTypeGroup>[type],
        initialDirectory: _lastDirectory,
      );
      if (location == null) return null;
      var path = location.path;
      if (path.isEmpty) return null;
      if (!path.toLowerCase().endsWith('.$extension')) {
        path = '$path.$extension';
      }
      if (_looksWritable(path)) _lastDirectory = File(path).parent.path;
      return path;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> writeBytes(String path, Uint8List bytes) async {
    if (!_looksWritable(path)) return false;
    try {
      await File(path).writeAsBytes(bytes, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> writeText(String path, String text) =>
      writeBytes(path, Uint8List.fromList(utf8.encode(text)));

  /// 写入失败时的兜底：存到应用文档目录，至少不会让用户白画。
  static Future<String?> writeToDocuments(String name, Uint8List bytes) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Future<PickedImage?> pickImage() async {
    try {
      final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[_imageType]);
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      final name = file.name.isEmpty ? 'image.png' : file.name;
      return PickedImage(
        bytes: bytes,
        mimeType: _mimeFor(name),
        name: name,
      );
    } catch (_) {
      return null;
    }
  }

  static String _mimeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'image/png';
  }
}

/// 自动保存。
///
/// 单独存一份，和用户手动保存的文件互不影响：用户按 Ctrl+S 存到 `方案.wbpro`，
/// 自动保存仍然写到应用私有目录，崩溃恢复时不会覆盖用户主动保存的版本。
class AutosaveStore {
  AutosaveStore._();

  static File? _cached;

  static Future<File?> _file() async {
    if (_cached != null) return _cached;
    try {
      final dir = await getApplicationSupportDirectory();
      final target = Directory('${dir.path}${Platform.pathSeparator}wb-pro');
      if (!await target.exists()) {
        await target.create(recursive: true);
      }
      return _cached = File('${target.path}${Platform.pathSeparator}autosave.wbpro');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> write(String content) async {
    final file = await _file();
    if (file == null) return false;
    try {
      await file.writeAsString(content, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> read() async {
    final file = await _file();
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      return content.isEmpty ? null : content;
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> modifiedAt() async {
    final file = await _file();
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      return (await file.stat()).modified;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final file = await _file();
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 删不掉就算了，下次启动会覆盖。
    }
  }
}
