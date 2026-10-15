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
import 'package:pixez/i18n.dart';
import 'package:pixez/page/zoom/tap_zone.dart';

/// 分区布局的本地化名称。
///
/// 设置页和提示层共用，避免两处各写一份而顺序或文案不一致。
String tapZoneModeLabel(BuildContext context, TapZoneMode mode) {
  final i18n = I18n.of(context);
  switch (mode) {
    case TapZoneMode.lShape:
      return i18n.tap_zone_l_shape;
    case TapZoneMode.kindlish:
      return i18n.tap_zone_kindlish;
    case TapZoneMode.edge:
      return i18n.tap_zone_edge;
    case TapZoneMode.rightAndLeft:
      return i18n.tap_zone_right_and_left;
    case TapZoneMode.disabled:
      return i18n.tap_zone_disabled;
  }
}

String _actionLabel(BuildContext context, TapZoneAction action) {
  final i18n = I18n.of(context);
  switch (action) {
    case TapZoneAction.previous:
      return i18n.tap_zone_action_prev;
    case TapZoneAction.next:
      return i18n.tap_zone_action_next;
    case TapZoneAction.menu:
      return i18n.tap_zone_action_menu;
    case TapZoneAction.none:
      return i18n.tap_zone_action_none;
  }
}

IconData? _actionIcon(TapZoneAction action) {
  switch (action) {
    case TapZoneAction.previous:
      return Icons.chevron_left;
    case TapZoneAction.next:
      return Icons.chevron_right;
    case TapZoneAction.menu:
      return Icons.tune;
    case TapZoneAction.none:
      return null;
  }
}

/// 反转方式的本地化名称。
String tapZoneInvertLabel(BuildContext context, TapZoneInvert invert) {
  final i18n = I18n.of(context);
  switch (invert) {
    case TapZoneInvert.none:
      return i18n.tap_zone_invert_none;
    case TapZoneInvert.horizontal:
      return i18n.tap_zone_invert_horizontal;
    case TapZoneInvert.vertical:
      return i18n.tap_zone_invert_vertical;
    case TapZoneInvert.both:
      return i18n.tap_zone_invert_both;
  }
}

/// 提示层里各动作的配色，沿用 Mihon 阅读器的取色习惯。
Color tapZoneActionColor(TapZoneAction action) {
  switch (action) {
    case TapZoneAction.previous:
      return const Color(0xFFFF7733);
    case TapZoneAction.next:
      return const Color(0xFF84E296);
    case TapZoneAction.menu:
      return const Color(0xFF95818D);
    case TapZoneAction.none:
      return const Color(0xFF9E9E9E);
  }
}

/// 进入图片查看器时短暂显示的分区提示层。
///
/// 把当前生效的分区画成半透明色块并标注动作，让用户一眼看到
/// 现在用的是哪种布局、点哪里会翻页。它本身不接收点击事件，
/// 由外层用 IgnorePointer 包住。
class TapZoneOverlay extends StatelessWidget {
  final TapZoneMode mode;
  final TapZoneInvert invert;

  const TapZoneOverlay({
    super.key,
    required this.mode,
    this.invert = TapZoneInvert.none,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Stack(
          children: [
            for (final zone in zonesOf(mode, invert: invert))
              Positioned(
                left: zone.rect.left * size.width,
                top: zone.rect.top * size.height,
                width: zone.rect.width * size.width,
                height: zone.rect.height * size.height,
                child: _ZoneTile(action: zone.action),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _TitleBar(
                text: _title(context),
              ),
            ),
          ],
        );
      },
    );
  }

  String _title(BuildContext context) {
    final i18n = I18n.of(context);
    final base = '${i18n.tap_zone_overlay_title} · '
        '${tapZoneModeLabel(context, mode)}';
    if (invert == TapZoneInvert.none) return base;
    return '$base · ${tapZoneInvertLabel(context, invert)}';
  }
}

class _TitleBar extends StatelessWidget {
  final String text;

  const _TitleBar({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 8,
      ),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: const BorderRadius.all(Radius.circular(16)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ZoneTile extends StatelessWidget {
  final TapZoneAction action;

  const _ZoneTile({required this.action});

  @override
  Widget build(BuildContext context) {
    final color = tapZoneActionColor(action);
    final icon = _actionIcon(action);
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        border: Border.all(color: color.withValues(alpha: 0.75), width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, color: Colors.white, size: 26)
            else
              const Icon(Icons.block, color: Colors.white, size: 22),
            const SizedBox(height: 2),
            Text(
              _actionLabel(context, action),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
