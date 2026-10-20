/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 *  WARRANTY; without even the implied warranty of  MERCHANTABILITY or FITNESS
 *  FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along with
 *  this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as Path;
import 'package:path_provider/path_provider.dart';
import 'package:pixez/er/lprinter.dart';
import 'package:pixez/er/prefer.dart';
import 'package:pixez/saf_plugin.dart';

/// 导出位置：优先用户设置过的默认文件夹，其次每次询问，最后 iOS 沙盒目录。
class NovelExportStorage {
  static const String dirUriKey = "novel_export_dir_uri";
  static const String dirNameKey = "novel_export_dir_name";

  static String? get dirUri => Prefer.getString(dirUriKey);
  static String? get dirName => Prefer.getString(dirNameKey);
  static bool get hasDefaultDir => (dirUri ?? "").isNotEmpty;

  static Future<void> setDefaultDir({
    required String uri,
    required String name,
  }) async {
    await Prefer.setString(dirUriKey, uri);
    await Prefer.setString(dirNameKey, name);
  }

  static Future<void> clearDefaultDir() async {
    await Prefer.remove(dirUriKey);
    await Prefer.remove(dirNameKey);
  }

  /// 保存文本，返回给用户看的保存位置。
  ///
  /// Android 上如果默认文件夹失效（被删、权限被回收），会清掉这个设置并
  /// 回退到“另存为”选择器，`fallbackToPicker` 会告诉调用方需要提示用户。
  static Future<NovelExportSaveResult> save(
    String fileName,
    String content,
  ) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    if (!Platform.isAndroid) {
      return _saveToDocuments(fileName, content);
    }

    final uri = dirUri;
    if (uri != null && uri.isNotEmpty) {
      try {
        await SAFPlugin.writeToDirectory(
          uri: uri,
          name: fileName,
          mimeType: "text/plain",
          data: bytes,
        );
        final folder = dirName;
        return NovelExportSaveResult(
          location: folder == null || folder.isEmpty
              ? fileName
              : "$folder/$fileName",
        );
      } on PlatformException catch (e) {
        LPrinter.d("novel export default dir failed: $e");
        await clearDefaultDir();
        final location = await _saveWithPicker(fileName, bytes);
        return NovelExportSaveResult(
          location: location,
          fallbackToPicker: true,
        );
      }
    }

    final location = await _saveWithPicker(fileName, bytes);
    return NovelExportSaveResult(location: location);
  }

  static Future<String> _saveWithPicker(
    String fileName,
    Uint8List bytes,
  ) async {
    try {
      final fileUri = await SAFPlugin.createFile(fileName, "text/plain");
      if (fileUri == null || fileUri.isEmpty) {
        throw const NovelExportCanceled();
      }
      await SAFPlugin.writeUri(fileUri, bytes);
      return fileName;
    } on PlatformException {
      // 用户在“另存为”里取消，原生侧同样回 error。
      throw const NovelExportCanceled();
    }
  }

  static Future<NovelExportSaveResult> _saveToDocuments(
    String fileName,
    String content,
  ) async {
    final path = await getApplicationDocumentsDirectory();
    final dir = Directory(Path.join(path.path, "novel_export", "All"));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File(Path.join(dir.path, fileName));
    await file.writeAsString(content);
    LPrinter.d("novel export path: ${file.path}");
    return NovelExportSaveResult(location: file.path);
  }
}

class NovelExportSaveResult {
  final String location;
  final bool fallbackToPicker;

  const NovelExportSaveResult({
    required this.location,
    this.fallbackToPicker = false,
  });
}

class NovelExportCanceled implements Exception {
  const NovelExportCanceled();
}
