import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

class SAFPlugin {
  static const platform = const MethodChannel('com.perol.dev/saf');

  static Future<String?> createFile(String name, String type) async {
    final result = await platform.invokeMethod("createFile", {
      'name': name,
      'mimeType': type,
    });
    if (result != null) {
      return result;
    }
    return null;
  }

  static Future<void> writeUri(String uri, Uint8List data) async {
    return platform.invokeMethod("writeUri", {'uri': uri, 'data': data});
  }

  static Future<Uint8List?> openFile() async {
    if (Platform.isIOS) {
      try {
        final result = await FilePicker.pickFile();
        return await result!.readAsBytes();
      } catch (e) {}
      return null;
    }
    return platform.invokeMethod<Uint8List>("openFile", {
      'type': "application/json",
    });
  }

  /// 让用户选一个文件夹（Android SAF tree），并持久化读取/写入权限。
  /// 返回 `{'uri': ..., 'name': ...}`，取消时返回 null。
  static Future<Map<String, String>?> pickDirectory() async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await platform.invokeMapMethod<String, dynamic>(
        "pickDirectory",
      );
      if (result == null) return null;
      final uri = result['uri'];
      if (uri is! String || uri.isEmpty) return null;
      final name = result['name'];
      return {
        'uri': uri,
        'name': name is String && name.isNotEmpty ? name : uri,
      };
    } on PlatformException {
      // 用户取消选择时原生侧同样回 error，这里按“没选”处理，不弹错误。
      return null;
    }
  }

  /// 直接把文件写进之前选过的文件夹，返回新文件的 uri。
  /// 同名文件会被覆盖（而不是生成 `xxx (1).txt`）。
  static Future<String?> writeToDirectory({
    required String uri,
    required String name,
    required String mimeType,
    required Uint8List data,
  }) async {
    if (!Platform.isAndroid) return null;
    return platform.invokeMethod<String>("writeToDirectory", {
      'uri': uri,
      'name': name,
      'mimeType': mimeType,
      'data': data,
    });
  }
}
