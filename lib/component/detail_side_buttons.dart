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
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import 'package:material_ui/material_ui.dart';
import 'package:pixez/component/detail_jump_button.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/utils/haptic_util.dart';

/// 详情页左下角的两个悬浮按钮，和右下角的收藏按钮左右对称。
///
/// 上面那个回到页面最上方（浏览器里那种 Top 键），
/// 下面那个定位到作者/介绍/标签区。
///
/// [id] 用来生成 heroTag。详情页可以一层层往下推（点推荐又开一个新详情页），
/// 同一个路由栈里会有多个实例，heroTag 写死会直接崩。
class DetailSideButtons extends StatelessWidget {
  final GlobalKey anchorKey;
  final ScrollController scrollController;
  final int id;

  const DetailSideButtons({
    super.key,
    required this.anchorKey,
    required this.scrollController,
    required this.id,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildButton(
          context,
          heroTag: '${id}_to_top',
          icon: Icons.vertical_align_top,
          tooltip: I18n.of(context).jump_to_top,
          onPressed: _jumpToTop,
        ),
        const SizedBox(height: 12),
        _buildButton(
          context,
          heroTag: '${id}_to_author',
          icon: Icons.keyboard_arrow_down,
          tooltip: I18n.of(context).jump_to_author,
          onPressed: _jumpToAuthor,
        ),
      ],
    );
  }

  /// 样式和右下角的收藏按钮保持一致（不指定颜色，交给主题）。
  Widget _buildButton(
    BuildContext context, {
    required String heroTag,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return FloatingActionButton(
      heroTag: heroTag,
      tooltip: tooltip,
      onPressed: onPressed,
      child: Icon(icon),
    );
  }

  void _jumpToTop() {
    if (!scrollController.hasClients) return;
    HapticUtil.selectionClick();
    scrollController.animateTo(
      scrollController.position.minScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  void _jumpToAuthor() {
    HapticUtil.selectionClick();
    revealDetailAnchor(
      anchorKey: anchorKey,
      scrollController: scrollController,
    );
  }
}
