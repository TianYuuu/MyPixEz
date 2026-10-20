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

/// 导出用的纯逻辑：文件名、单篇 txt、系列合并 txt、系列话序。
/// 这里刻意不依赖 Flutter / 网络，方便单测。

/// 系列里的一话。`prevId` / `nextId` 来自正文接口的 `seriesNavigation`，
/// 用来在接口顺序不可靠时还原正确的话序。
class NovelExportChapter {
  final int id;
  final String title;
  final String text;
  final int? prevId;
  final int? nextId;

  const NovelExportChapter({
    required this.id,
    required this.title,
    required this.text,
    this.prevId,
    this.nextId,
  });
}

/// 和 `String.toLegal()` 同一套规则（去掉文件名里的非法字符）。
String sanitizeNovelFileName(String title) {
  final cleaned = title
      .replaceAll("/", "")
      .replaceAll("\\", "")
      .replaceAll(":", "")
      .replaceAll("*", "")
      .replaceAll("?", "")
      .replaceAll(">", "")
      .replaceAll("|", "")
      .replaceAll("<", "")
      .trim();
  return cleaned.isEmpty ? "novel" : cleaned;
}

String novelTxtFileName(String title) => "${sanitizeNovelFileName(title)}.txt";

/// 单篇导出保持原来的行为：文件里只有正文。
String buildSingleNovelTxt(String text) => text;

/// 把整个系列按顺序拼成一个 txt：
///
/// ```
/// 《系列名》
/// 共 3 话
///
/// ========================================
/// 第 1 话  第一章
///
/// 正文……
/// ```
String buildSeriesNovelTxt({
  required String seriesTitle,
  required List<NovelExportChapter> chapters,
}) {
  final buffer = StringBuffer();
  final divider = List.filled(40, "=").join();
  buffer.writeln("《$seriesTitle》");
  buffer.writeln("共 ${chapters.length} 话");
  buffer.writeln();
  for (var i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    buffer.writeln(divider);
    buffer.writeln("第 ${i + 1} 话  ${chapter.title.trim()}");
    buffer.writeln();
    buffer.writeln(chapter.text.trimRight());
    buffer.writeln();
  }
  return buffer.toString();
}

/// 按 `seriesNavigation` 的 prev/next 链还原话序。
///
/// 系列列表接口返回的顺序大多数时候就是对的，但接口并不保证；
/// 这里用每话正文自带的相邻关系兜底，链不完整（缺话/循环）时退回原始顺序。
List<NovelExportChapter> orderSeriesChapters(
  List<NovelExportChapter> chapters,
) {
  if (chapters.length <= 1) return chapters;
  final byId = <int, NovelExportChapter>{
    for (final chapter in chapters) chapter.id: chapter,
  };

  NovelExportChapter? head;
  for (final chapter in chapters) {
    final prev = chapter.prevId;
    if (prev == null || !byId.containsKey(prev)) {
      head = chapter;
      break;
    }
  }
  if (head == null) return chapters;

  final ordered = <NovelExportChapter>[];
  final visited = <int>{};
  NovelExportChapter? current = head;
  while (current != null && visited.add(current.id)) {
    ordered.add(current);
    final nextId = current.nextId;
    current = nextId == null ? null : byId[nextId];
  }
  if (ordered.length != chapters.length) return chapters;
  return ordered;
}
