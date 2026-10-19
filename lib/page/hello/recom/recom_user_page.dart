/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful, but WITHOUT ANY
 *  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:easy_refresh/easy_refresh.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/illust_filter_sheet.dart';
import 'package:pixez/component/painer_card.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/lighting/illust_filter.dart';
import 'package:pixez/lighting/lighting_filter.dart';
import 'package:pixez/models/user_preview.dart';
import 'package:pixez/page/hello/recom/recom_user_store.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

class RecomUserPage extends StatefulWidget {
  final RecomUserStore? recomUserStore;

  const RecomUserPage({Key? key, this.recomUserStore}) : super(key: key);

  @override
  _RecomUserPageState createState() => _RecomUserPageState();
}

class _RecomUserPageState extends State<RecomUserPage> {
  late EasyRefreshController _refreshController;
  late RecomUserStore _recomUserStore;

  /// 筛选推荐作者。
  ///
  /// 接口里没有粉丝数，但每个作者都带着几张近期作品，而那些作品本来就有
  /// `total_view` / `total_bookmarks` / `page_count` / `tags`，所以这里能
  /// **零额外请求**地复用同一套 [IllustFilter]：
  /// 近期作品里有一张满足条件，就把这个作者留下。
  late IllustFilter _filter = loadIllustFilter(
      IllustFilterScope.recommendUser);

  /// 过滤后实际要显示的列表。原始 `users` 保持不动，改条件能立刻重算。
  List<UserPreviews> _visibleUsers = const [];

  /// 筛得太狠时主动多拉几页，否则列表撑不满一屏就再也触发不了"加载更多"。
  bool _backfilling = false;
  int _backfillRounds = 0;
  static const int _filterTargetCount = 12;
  static const int _maxBackfillRounds = 4;

  @override
  void initState() {
    _refreshController = EasyRefreshController(
        controlFinishLoad: true, controlFinishRefresh: true);
    _recomUserStore =
        widget.recomUserStore ?? RecomUserStore(_refreshController);
    if (widget.recomUserStore != null) {
      _recomUserStore.controller = _refreshController;
    }
    super.initState();
  }

  @override
  void dispose() {
    _recomUserStore.controller = null;
    _refreshController.dispose();
    super.dispose();
  }

  /// 按当前条件算出可见作者。
  List<UserPreviews> _computeVisible() {
    final all = _recomUserStore.users;
    if (_filter.isAny) return all.toList(growable: false);
    return all
        .where((e) => _filter.matchesAnyIllust(e.illusts))
        .toList(growable: false);
  }

  /// 过滤后太少时，继续拉取更多推荐作者直到够一屏或到达上限。
  Future<void> _backfillForFilter() async {
    if (_backfilling) return;
    if (_filter.isAny) return;
    if (!shouldFetchMoreForFilter(
      visibleCount: _visibleUsers.length,
      targetCount: _filterTargetCount,
      nextUrl: _recomUserStore.nextUrl,
      roundsDone: _backfillRounds,
      maxRounds: _maxBackfillRounds,
    )) {
      return;
    }
    _backfilling = true;
    try {
      while (mounted &&
          shouldFetchMoreForFilter(
            visibleCount: _visibleUsers.length,
            targetCount: _filterTargetCount,
            nextUrl: _recomUserStore.nextUrl,
            roundsDone: _backfillRounds,
            maxRounds: _maxBackfillRounds,
          )) {
        final before = _recomUserStore.users.length;
        _backfillRounds++;
        await _recomUserStore.next();
        if (!mounted) return;
        _visibleUsers = _computeVisible();
        // 没有拿到新数据就收手，避免空转。
        if (_recomUserStore.users.length == before) break;
      }
    } finally {
      _backfilling = false;
      if (mounted) setState(() {});
    }
  }

  /// 延后一帧再补足，避免在 build 期间触发网络请求与 setState。
  void _scheduleBackfill() {
    if (_filter.isAny) return;
    if (_visibleUsers.length >= _filterTargetCount) return;
    if (_backfillRounds >= _maxBackfillRounds) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _backfillForFilter();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      return Scaffold(
        appBar: AppBar(
          title: Text(I18n.of(context).recommend_for_you),
          actions: [
            IllustFilterButton(
              scope: IllustFilterScope.recommendUser,
              filter: _filter,
              onChanged: (filter) => setState(() {
                _filter = filter;
                // 换了条件就重新给补足逻辑一次机会。
                _backfillRounds = 0;
              }),
            ),
          ],
        ),
        body: EasyRefresh(
          controller: _refreshController,
          onRefresh: () => _recomUserStore.fetch(),
          onLoad: () => _recomUserStore.next(),
          refreshOnStart: widget.recomUserStore == null,
          child: _buildList(),
        ),
      );
    });
  }

  Widget _buildList() {
    _visibleUsers = _computeVisible();
    _scheduleBackfill();

    // 有数据但被筛光了：空白列表滚不动，会卡住"加载更多"，所以给个提示 + 入口。
    if (_visibleUsers.isEmpty && _recomUserStore.users.isNotEmpty) {
      return WaterfallFlow.builder(
        gridDelegate: SliverWaterfallFlowDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 600,
        ),
        itemCount: 1,
        itemBuilder: (context, index) => _buildFilteredEmpty(context),
      );
    }

    return WaterfallFlow.builder(
      gridDelegate: SliverWaterfallFlowDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 600,
      ),
      itemCount: _visibleUsers.length,
      itemBuilder: (context, index) {
        return PainterCard(
          user: _visibleUsers[index],
        );
      },
    );
  }

  Widget _buildFilteredEmpty(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              I18n.of(context).filter_no_result,
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: _backfilling
                  ? null
                  : () {
                      _backfillRounds = 0;
                      _backfillForFilter();
                    },
              child: Text(
                _backfilling
                    ? I18n.of(context).footer_loading
                    : I18n.of(context).load_more,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
