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
import 'package:pixez/component/pixez_default_header.dart';
import 'package:pixez/exts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/lighting/lighting_filter.dart';
import 'package:pixez/models/novel_recom_response.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/page/novel/component/novel_bookmark_button.dart';
import 'package:pixez/page/novel/component/novel_filter_sheet.dart';
import 'package:pixez/page/novel/component/novel_lighting_store.dart';
import 'package:pixez/page/novel/novel_filter.dart';
import 'package:pixez/page/novel/viewer/novel_store.dart';
import 'package:pixez/page/novel/viewer/novel_viewer.dart';
import 'package:pixez/utils/haptic_util.dart';

class NovelRecomPage extends StatefulWidget {
  @override
  _NovelRecomPageState createState() => _NovelRecomPageState();
}

class _NovelRecomPageState extends State<NovelRecomPage>
    with AutomaticKeepAliveClientMixin {
  late NovelLightingStore _store;
  late EasyRefreshController _easyRefreshController;

  /// 阅读数 / 收藏数 / 字数 / 标签筛选。纯本地过滤，进页面时恢复上次的选择。
  late NovelFilter _filter = loadNovelFilter(NovelFilterScope.recommend);

  /// 过滤后实际要显示的列表。渲染时计算，不动 `_store.novels`。
  List<NovelStore> _visibleNovels = const [];

  /// 筛得太狠时主动多拉几页。
  bool _backfilling = false;
  int _backfillRounds = 0;
  static const int _filterTargetCount = 12;
  static const int _maxBackfillRounds = 4;

  @override
  void initState() {
    _easyRefreshController = EasyRefreshController(
      controlFinishLoad: true,
      controlFinishRefresh: true,
    );
    _store = NovelLightingStore(
      () => apiClient.getNovelRecommended(),
      _easyRefreshController,
    );
    super.initState();
  }

  @override
  void dispose() {
    _easyRefreshController.dispose();
    super.dispose();
  }

  /// 按当前筛选条件算出可见列表。
  List<NovelStore> _computeVisible() {
    if (_filter.isAny) return _store.novels.toList(growable: false);
    return _store.novels
        .where((e) => e.novel != null && _filter.matches(e.novel!))
        .toList(growable: false);
  }

  Future<void> _backfillForFilter() async {
    if (_backfilling) return;
    if (_filter.isAny) return;
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
    if (_filter.isAny) return;
    if (_visibleNovels.length >= _filterTargetCount) return;
    if (_backfillRounds >= _maxBackfillRounds) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _backfillForFilter();
    });
  }

  Widget _buildFirstRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Container(
            child: Padding(
              child: Text(
                I18n.of(context).recommend,
                style: TextStyle(
                  color: Theme.of(context).textTheme.titleLarge!.color,
                ),
              ),
              padding: EdgeInsets.only(left: 8.0, bottom: 10.0),
            ),
          ),
          NovelFilterButton(
            scope: NovelFilterScope.recommend,
            filter: _filter,
            onChanged: (filter) => setState(() {
              _filter = filter;
              _backfillRounds = 0;
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return EasyRefresh.builder(
      header: PixezDefault.header(context),
      onRefresh: () => _store.fetch(),
      onLoad: () => _store.next(),
      controller: _easyRefreshController,
      callRefreshOverOffset: 10,
      refreshOnStart: true,
      childBuilder: (context, physics) => Observer(
        builder: (context) {
          return CustomScrollView(
            physics: physics,
            slivers: [
              SliverAppBar(
                elevation: 0.0,
                titleSpacing: 0.0,
                automaticallyImplyLeading: false,
                backgroundColor: Colors.transparent,
                title: _buildFirstRow(context),
              ),
              if (_store.novels.isNotEmpty) _buildSliverList(),
            ],
          );
        },
      ),
    );
  }

  SliverList _buildSliverList() {
    _store.novels.removeWhere((element) => element.novel?.hateByUser() == true);
    _visibleNovels = _computeVisible();
    _scheduleBackfill();
    return SliverList(
      delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
        Novel novel = _visibleNovels[index].novel!;
        return _buildItem(context, novel, index);
      }, childCount: _visibleNovels.length),
    );
  }

  Widget _buildItem(BuildContext context, Novel novel, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: InkWell(
        onTap: () {
          HapticUtil.selectionClick();
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
                            padding: const EdgeInsets.only(top: 8.0, left: 8.0),
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
                                  style: Theme.of(context).textTheme.bodySmall!
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
                              spacing: 2, // gap between adjacent chips
                              runSpacing: 0,
                              children: [
                                for (var f in novel.tags)
                                  Text(
                                    f.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
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
  }

  @override
  bool get wantKeepAlive => true;
}
