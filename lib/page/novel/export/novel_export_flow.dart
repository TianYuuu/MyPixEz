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

import 'package:bot_toast/bot_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pixez/er/lprinter.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/models/novel_recom_response.dart';
import 'package:pixez/models/novel_series_detail.dart';
import 'package:pixez/models/novel_web_response.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/page/novel/export/novel_export_format.dart';
import 'package:pixez/page/novel/export/novel_export_storage.dart';
import 'package:pixez/page/novel/viewer/novel_store.dart';

/// 导出入口：系列作品先让用户选“本篇 / 整个系列”，然后带进度条地导出。
Future<void> showNovelExportMenu(BuildContext context, NovelStore store) async {
  final novel = store.novel;
  final text = store.novelTextResponse?.text;
  if (novel == null) return;
  if (text == null || text.isEmpty) {
    BotToast.showText(text: I18n.of(context).novel_export_empty);
    return;
  }

  final seriesId = novel.series.id;
  var scope = NovelExportScope.single;
  if (seriesId != null) {
    final selected = await showModalBottomSheet<NovelExportScope>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (sheetContext) {
        final i18n = I18n.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  i18n.export,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(i18n.novel_export_this_novel),
                subtitle: Text(
                  novel.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(NovelExportScope.single),
              ),
              ListTile(
                leading: const Icon(Icons.library_books_outlined),
                title: Text(i18n.novel_export_series_merged),
                subtitle: Text(i18n.novel_export_series_hint),
                onTap: () =>
                    Navigator.of(sheetContext).pop(NovelExportScope.series),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    scope = selected;
  }

  if (!context.mounted) return;
  await _exportWithProgress(
    context,
    novel: novel,
    text: text,
    seriesId: scope == NovelExportScope.series ? seriesId : null,
  );
}

enum NovelExportScope { single, series }

class NovelExportProgress {
  final int done;
  final int total;
  final String message;

  const NovelExportProgress({this.done = 0, this.total = 0, this.message = ""});

  double? get value =>
      total <= 0 ? null : (done / total).clamp(0.0, 1.0).toDouble();
}

class _NovelExportOutcome {
  final String location;
  final bool fallbackToPicker;
  final int skipped;
  final int chapters;

  const _NovelExportOutcome({
    required this.location,
    this.fallbackToPicker = false,
    this.skipped = 0,
    this.chapters = 1,
  });
}

Future<void> _exportWithProgress(
  BuildContext context, {
  required Novel novel,
  required String text,
  required int? seriesId,
}) async {
  final progress = ValueNotifier<NovelExportProgress>(
    NovelExportProgress(message: novel.title),
  );
  var canceled = false;
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => NovelExportProgressDialog(
      progress: progress,
      onCancel: () => canceled = true,
    ),
  );

  _NovelExportOutcome? outcome;
  Object? error;
  var wasCanceled = false;
  try {
    if (seriesId == null) {
      outcome = await _exportSingle(novel, text, progress);
    } else {
      outcome = await _exportSeries(novel, seriesId, progress, () => canceled);
    }
  } on NovelExportCanceled {
    wasCanceled = true;
  } catch (e) {
    LPrinter.d("novel export failed: $e");
    error = e;
  }
  navigator.pop();
  progress.dispose();
  if (!context.mounted) return;

  if (wasCanceled) {
    BotToast.showText(text: I18n.of(context).novel_export_canceled);
    return;
  }
  final i18n = I18n.of(context);
  if (error != null || outcome == null) {
    await _showExportMessage(
      context,
      title: i18n.novel_export_failed,
      lines: ["$error"],
    );
    return;
  }

  final lines = <String>["${i18n.novel_export_saved_to}: ${outcome.location}"];
  if (outcome.chapters > 1) {
    lines.add("${i18n.novel_export_merged_chapters}: ${outcome.chapters}");
  }
  if (outcome.skipped > 0) {
    lines.add("${i18n.novel_export_skipped}: ${outcome.skipped}");
  }
  if (outcome.fallbackToPicker) {
    lines.add(i18n.novel_export_fallback_dir);
  }
  await _showExportMessage(
    context,
    title: i18n.novel_export_done,
    lines: lines,
  );
}

Future<_NovelExportOutcome> _exportSingle(
  Novel novel,
  String text,
  ValueNotifier<NovelExportProgress> progress,
) async {
  progress.value = NovelExportProgress(done: 0, total: 1, message: novel.title);
  final result = await NovelExportStorage.save(
    novelTxtFileName(novel.title),
    text,
  );
  progress.value = NovelExportProgress(done: 1, total: 1, message: novel.title);
  return _NovelExportOutcome(
    location: result.location,
    fallbackToPicker: result.fallbackToPicker,
  );
}

Future<_NovelExportOutcome> _exportSeries(
  Novel novel,
  int seriesId,
  ValueNotifier<NovelExportProgress> progress,
  bool Function() isCanceled,
) async {
  final seriesTitle = (novel.series.title ?? novel.title).trim();
  final novels = await _fetchSeriesNovels(seriesId, isCanceled);
  if (isCanceled()) throw const NovelExportCanceled();

  final chapters = <NovelExportChapter>[];
  var skipped = 0;
  for (var i = 0; i < novels.length; i++) {
    if (isCanceled()) throw const NovelExportCanceled();
    final item = novels[i];
    progress.value = NovelExportProgress(
      done: i,
      total: novels.length,
      message: "${i + 1}/${novels.length}  ${item.title}",
    );
    try {
      final response = await apiClient.webviewNovel(item.id);
      final json = parseNovelJsonFromHtml(response.data);
      if (json == null) {
        throw const FormatException("cannot parse novel text");
      }
      final web = NovelWebResponse.fromJson(jsonDecode(json));
      chapters.add(
        NovelExportChapter(
          id: item.id,
          title: web.title.isNotEmpty ? web.title : item.title,
          text: web.text,
          prevId: web.seriesNavigation?.prevNovel?.id,
          nextId: web.seriesNavigation?.nextNovel?.id,
        ),
      );
    } catch (e) {
      skipped++;
      LPrinter.d("novel series export skipped ${item.id}: $e");
    }
    if (i < novels.length - 1) {
      // 顺序拉正文，给接口留一点间隔，避免整系列导出被限流。
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }
  if (isCanceled()) throw const NovelExportCanceled();
  if (chapters.isEmpty) {
    throw Exception("no chapter exported");
  }

  final ordered = orderSeriesChapters(chapters);
  progress.value = NovelExportProgress(
    done: novels.length,
    total: novels.length,
    message: seriesTitle,
  );
  final result = await NovelExportStorage.save(
    novelTxtFileName(seriesTitle),
    buildSeriesNovelTxt(seriesTitle: seriesTitle, chapters: ordered),
  );
  return _NovelExportOutcome(
    location: result.location,
    fallbackToPicker: result.fallbackToPicker,
    skipped: skipped,
    chapters: ordered.length,
  );
}

Future<List<Novel>> _fetchSeriesNovels(
  int seriesId,
  bool Function() isCanceled,
) async {
  final collected = <Novel>[];
  final seen = <int>{};
  void collect(NovelSeriesResponse page) {
    for (final novel in page.novels) {
      if (seen.add(novel.id)) collected.add(novel);
    }
  }

  final first = NovelSeriesResponse.fromJson(
    (await apiClient.novelSeries(seriesId)).data,
  );
  collect(first);
  var next = first.nextUrl;
  var pages = 0;
  while (next != null && next.isNotEmpty && pages < 50) {
    if (isCanceled()) throw const NovelExportCanceled();
    final page = NovelSeriesResponse.fromJson(
      (await apiClient.getNext(next)).data,
    );
    collect(page);
    next = page.nextUrl;
    pages++;
  }
  if (collected.isEmpty) {
    throw Exception("empty series");
  }
  return collected;
}

class NovelExportProgressDialog extends StatelessWidget {
  final ValueNotifier<NovelExportProgress> progress;
  final VoidCallback onCancel;

  const NovelExportProgressDialog({
    super.key,
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(i18n.novel_export_progress_title),
        content: ValueListenableBuilder<NovelExportProgress>(
          valueListenable: progress,
          builder: (context, value, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LinearProgressIndicator(value: value.value),
                const SizedBox(height: 12),
                Text(
                  value.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          },
        ),
        actions: <Widget>[
          TextButton(onPressed: onCancel, child: Text(i18n.cancel)),
        ],
      ),
    );
  }
}

Future<void> _showExportMessage(
  BuildContext context, {
  required String title,
  required List<String> lines,
}) {
  return showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText(line),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(I18n.of(dialogContext).ok),
          ),
        ],
      );
    },
  );
}
