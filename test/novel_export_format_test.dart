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

import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/page/novel/export/novel_export_format.dart';

NovelExportChapter _chapter(
  int id, {
  String? title,
  String? text,
  int? prevId,
  int? nextId,
}) {
  return NovelExportChapter(
    id: id,
    title: title ?? "第 $id 话",
    text: text ?? "正文 $id",
    prevId: prevId,
    nextId: nextId,
  );
}

void main() {
  group("novelTxtFileName", () {
    test("去掉文件名里的非法字符", () {
      expect(
        novelTxtFileName('a/b\\c:d*e?f>g|h<i'),
        'abcdefghi.txt',
      );
    });

    test("标题为空时给一个兜底文件名", () {
      expect(novelTxtFileName('  /  '), 'novel.txt');
    });

    test("中文标题原样保留", () {
      expect(novelTxtFileName('初音未来的消失'), '初音未来的消失.txt');
    });
  });

  group("buildSeriesNovelTxt", () {
    test("单篇导出只保留正文", () {
      expect(buildSingleNovelTxt("只有正文"), "只有正文");
    });

    test("合并后带系列名、话数和章节标题", () {
      final txt = buildSeriesNovelTxt(
        seriesTitle: "测试系列",
        chapters: [
          _chapter(1, title: "开端", text: "第一段"),
          _chapter(2, title: "发展", text: "第二段"),
        ],
      );

      expect(txt, contains("《测试系列》"));
      expect(txt, contains("共 2 话"));
      expect(txt, contains("第 1 话  开端"));
      expect(txt, contains("第 2 话  发展"));
      // 正文按顺序出现
      expect(txt.indexOf("第一段"), lessThan(txt.indexOf("第二段")));
      // 章节之间要有分隔线
      expect(txt, contains(List.filled(40, "=").join()));
    });

    test("章节正文末尾的空行不会层层堆叠", () {
      final txt = buildSeriesNovelTxt(
        seriesTitle: "系列",
        chapters: [_chapter(1, text: "正文\n\n")],
      );
      expect(txt.endsWith("\n"), isTrue);
      expect(txt.contains("正文\n\n\n"), isFalse);
    });
  });

  group("orderSeriesChapters", () {
    test("按 prev/next 链把乱序的章节排回正序", () {
      final shuffled = [
        _chapter(3, prevId: 2, nextId: null),
        _chapter(1, prevId: null, nextId: 2),
        _chapter(2, prevId: 1, nextId: 3),
      ];

      final ordered = orderSeriesChapters(shuffled);

      expect(ordered.map((e) => e.id).toList(), [1, 2, 3]);
    });

    test("链完整时和输入顺序无关", () {
      final chapters = [
        _chapter(2, prevId: 1, nextId: 3),
        _chapter(3, prevId: 2, nextId: 4),
        _chapter(1, prevId: null, nextId: 2),
        _chapter(4, prevId: 3, nextId: null),
      ];

      expect(
        orderSeriesChapters(chapters).map((e) => e.id).toList(),
        [1, 2, 3, 4],
      );
    });

    test("链断了就退回接口原始顺序，而不是丢掉章节", () {
      final chapters = [
        _chapter(1, prevId: null, nextId: null),
        _chapter(2, prevId: null, nextId: null),
        _chapter(3, prevId: null, nextId: null),
      ];

      expect(
        orderSeriesChapters(chapters).map((e) => e.id).toList(),
        [1, 2, 3],
      );
    });

    test("只有一话时原样返回", () {
      final chapters = [_chapter(9)];
      expect(identical(orderSeriesChapters(chapters), chapters), isTrue);
    });
  });
}
