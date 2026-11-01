import 'package:flutter/material.dart';

import '../../../app/state/settings_layout_state.dart';
import '../../../app/tv/tv_layout.dart';

enum HomeSection {
  roam('漫游'),
  favorites('收藏'),
  history('最近播放'),
  albums('最新专辑'),
  playlists('我的歌单'),
  tracks('最近添加');

  const HomeSection(this.label);
  final String label;
}

class HomeSectionFeedback extends StatelessWidget {
  const HomeSectionFeedback({
    super.key,
    required this.section,
    required this.loading,
    required this.onRetry,
  });

  final HomeSection section;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scale = AppLayoutSettings.tvMode.value
        ? TvLayout.uiScale(context)
        : 1.0;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8 * scale),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8 * scale,
        children: [
          if (loading)
            SizedBox(
              width: 16 * scale,
              height: 16 * scale,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          Text(
            '${section.label}${loading ? '加载中…' : '加载失败'}',
            style: TextStyle(fontSize: 13 * scale),
          ),
          if (!loading) TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
