/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */

import 'package:easy_refresh/easy_refresh.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/pixez_default_header.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/lighting/lighting_store.dart';
import 'package:pixez/lighting/lighting_filter.dart';
import 'package:pixez/models/novel_recom_response.dart';
import 'package:pixez/page/novel/component/novel_bookmark_button.dart';
import 'package:pixez/page/novel/component/novel_lighting_store.dart';
import 'package:pixez/page/novel/novel_filter.dart';
import 'package:pixez/page/novel/viewer/novel_store.dart';
import 'package:pixez/page/novel/viewer/novel_viewer.dart';
import 'package:pixez/exts.dart';

class NovelLightingList extends StatefulWidget {
  final FutureGet futureGet;
  final bool? isNested;

  /// 可选：本地筛选条件。传了就在渲染时按它过滤，
  /// 原始列表不动（改条件后已隐藏的条目能回来）。
  final NovelFilter? filter;

  const NovelLightingList({
    Key? key,
    required this.futureGet,
    this.isNested,
    this.filter,
  }) : super(key: key);

  @override
  _NovelLightingListState createState() => _NovelLightingListState();
}

class _NovelLightingListState extends State<NovelLightingList> {
  late EasyRefreshController _easyRefreshController;
  late NovelLightingStore _store;
  late bool _isNested;

  /// 过滤后实际要显示的列表。渲染时计算，不动 `_store.novels`。
  List<NovelStore> _visibleNovels = const [];

  /// 筛得太狠时主动多拉几页，避免撑不满一屏就再也触发不了"加载更多"。
  bool _backfilling = false;
  int _backfillRounds = 0;
  static const int _filterTargetCount = 12;
  static const int _maxBackfillRounds = 4;

  @override
  void initState() {
    _isNested = widget.isNested ?? false;
    _easyRefreshController = EasyRefreshController(
      controlFinishLoad: true,
      controlFinishRefresh: true,
    );
    _store = NovelLightingStore(widget.futureGet, _easyRefreshController);
    super.initState();
    if (_isNested) _store.fetch();
  }

  @override
  void didUpdateWidget(NovelLightingList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.futureGet != widget.futureGet) {
      _store.source = widget.futureGet;
      _store.fetch();
    }
  }

  @override
  void dispose() {
    _easyRefreshController.dispose();
    super.dispose();
  }

  /// 按当前筛选条件算出可见列表。
  List<NovelStore> _computeVisible() {
    final filter = widget.filter;
    if (filter == null || filter.isAny) {
      return _store.novels.toList(growable: false);
    }
    return _store.novels
        .where((e) => e.novel != null && filter.matches(e.novel!))
        .toList(growable: false);
  }

  /// 过滤后条目太少时，继续拉取更多直到够一屏或到达上限。
  Future<void> _backfillForFilter() async {
    final filter = widget.filter;
    if (_backfilling) return;
    if (filter == null || filter.isAny) return;
    if (!shouldFetchMoreForFilter(
      visibleCount: _visibleNovels.length,
      targetCount: _filterTargetCount,
      nextUrl: _store.nextUrl,
      roundsDone: _backfillRounds,
      maxRounds: _maxBackfillRounds,
    )) {
      return;
    }
    _backfilling = true;
    try {
      while (mounted &&
          shouldFetchMoreForFilter(
            visibleCount: _visibleNovels.length,
            targetCount: _filterTargetCount,
            nextUrl: _store.nextUrl,
            roundsDone: _backfillRounds,
            maxRounds: _maxBackfillRounds,
          )) {
        final before = _store.novels.length;
        _backfillRounds++;
        await _store.next();
        if (!mounted) return;
        _visibleNovels = _computeVisible();
        if (_store.novels.length == before) break;
      }
    } finally {
      _backfilling = false;
      if (mounted) setState(() {});
    }
  }

  void _scheduleBackfill() {
    final filter = widget.filter;
    if (filter == null || filter.isAny) return;
    if (_visibleNovels.length >= _filterTargetCount) return;
    if (_backfillRounds >= _maxBackfillRounds) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _backfillForFilter();
    });
  }

  Widget _buildBody(BuildContext context) {
    if (_store.errorMessage != null) {
      return Container(
        child: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                ':(',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            TextButton(
              onPressed: () {
                _store.fetch();
              },
              child: Text(I18n.of(context).retry),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('${_store.errorMessage}'),
            ),
          ],
        ),
      );
    }
    return _buildListBody();
  }

  ListView _buildListBody() {
    _store.novels.removeWhere((element) => element.novel?.hateByUser() == true);
    _visibleNovels = _computeVisible();
    _scheduleBackfill();
    return ListView.builder(
      padding: EdgeInsets.all(0),
      itemBuilder: (context, index) {
        Novel novel = _visibleNovels[index].novel!;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: InkWell(
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (BuildContext context) => NovelViewerPage(
                    id: novel.id,
                    novelStore: _visibleNovels[index],
                  ),
                ),
              );
            },
            child: Card(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    flex: 5,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: PixivImage(novel.imageUrls.medium, width: 80),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 8.0,
                                  left: 8.0,
                                ),
                                child: Text(
                                  novel.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyLarge,
                                  maxLines: 3,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      novel.user.name,
                                      maxLines: 1,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall!
                                          .copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.secondary,
                                          ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.only(left: 8),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.article,
                                            size: 12,
                                            color: Theme.of(
                                              context,
                                            ).textTheme.labelSmall!.color,
                                          ),
                                          SizedBox(width: 2),
                                          Text(
                                            '${novel.textLength}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                ),
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 2,
                                  runSpacing: 0,
                                  children: [
                                    for (var f in novel.tags)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 1,
                                        ),
                                        child: Text(
                                          f.name,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(height: 8.0),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        NovelBookmarkButton(novel: novel),
                        Text(
                          '${novel.totalBookmarks}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      itemCount: _visibleNovels.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return EasyRefresh(
      onLoad: () => _store.next(),
      onRefresh: () => _store.fetch(),
      refreshOnStart: _isNested ? false : true,
      controller: _easyRefreshController,
      header: PixezDefault.header(context),
      child: Observer(
        builder: (context) {
          return _buildBody(context);
        },
      ),
    );
  }
}
