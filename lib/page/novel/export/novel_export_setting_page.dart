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

import 'package:bot_toast/bot_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/page/novel/export/novel_export_storage.dart';
import 'package:pixez/saf_plugin.dart';

/// 小说导出设置：选一个固定文件夹，导出时不再每次都弹系统选择器。
class NovelExportSettingPage extends StatefulWidget {
  const NovelExportSettingPage({super.key});

  @override
  State<NovelExportSettingPage> createState() => _NovelExportSettingPageState();
}

class _NovelExportSettingPageState extends State<NovelExportSettingPage> {
  String? _uri;
  String? _name;

  bool get _hasDir => (_uri ?? "").isNotEmpty;

  @override
  void initState() {
    super.initState();
    _uri = NovelExportStorage.dirUri;
    _name = NovelExportStorage.dirName;
  }

  Future<void> _pickDirectory() async {
    try {
      final result = await SAFPlugin.pickDirectory();
      if (result == null) return;
      final uri = result['uri']!;
      final name = result['name'] ?? uri;
      await NovelExportStorage.setDefaultDir(uri: uri, name: name);
      if (!mounted) return;
      setState(() {
        _uri = uri;
        _name = name;
      });
    } catch (e) {
      if (!mounted) return;
      BotToast.showText(text: I18n.of(context).novel_export_pick_failed);
    }
  }

  Future<void> _clearDirectory() async {
    await NovelExportStorage.clearDefaultDir();
    if (!mounted) return;
    setState(() {
      _uri = null;
      _name = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: Text(i18n.novel_export_settings)),
      body: ListView(
        children: <Widget>[
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(i18n.novel_export_default_dir),
                  subtitle: Text(
                    _hasDir ? _name ?? _uri! : i18n.novel_export_dir_none,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickDirectory,
                ),
                if (_hasDir)
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: errorColor),
                    title: Text(
                      i18n.novel_export_clear_dir,
                      style: TextStyle(color: errorColor),
                    ),
                    onTap: _clearDirectory,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              i18n.novel_export_dir_hint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
