import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/korean.dart';
import '../../data/regions.dart';
import '../../ui/widgets.dart';
import '../goats/goat_avatar.dart';
import '../goats/goat_sheet.dart';
import '../goats/goat_texts.dart';
import '../goats/goats_api.dart';
import '../goats/schedule.dart';
import '../location/my_region.dart';
import 'goat_painter.dart';
import 'map_geometry.dart';
import 'map_view.dart';

/// 지도 도형은 지역 데이터에서 한 번만 만든다
final mapGeometryProvider = FutureProvider<MapGeometry>((ref) async {
  final data = await ref.watch(regionDataProvider.future);
  return MapGeometry.build(data);
});

/// 메인 지도 탭 (SPEC 10)
class MapTab extends ConsumerStatefulWidget {
  const MapTab({super.key, this.clock});

  /// 테스트·스크린샷용 고정 시각
  final DateTime Function()? clock;

  @override
  ConsumerState<MapTab> createState() => _MapTabState();
}

class _MapTabState extends ConsumerState<MapTab> {
  final _map = MapViewController();
  String? _selectedRegion;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // 앱을 보고 있을 때만 위치를 쓴다(SPEC 8, 15)
    Future.microtask(() => ref.read(myRegionProvider.notifier).resume());
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.read(myRegionProvider.notifier).resume();
        ref.read(goatScheduleProvider.notifier).refreshQuietly();
      },
      onPause: () => ref.read(myRegionProvider.notifier).pause(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  DateTime _now(GoatSchedule? s) => widget.clock?.call() ?? s?.serverNow() ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final geo = ref.watch(mapGeometryProvider);
    return geo.when(
      loading: () => const Center(child: BobbingGoat(size: 120)),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NoticeBox('지도를 그리지 못했어요.'),
              const SizedBox(height: 12),
              ChunkyButton(label: '다시 시도', onPressed: () => ref.invalidate(regionDataProvider)),
            ],
          ),
        ),
      ),
      data: _body,
    );
  }

  Widget _body(MapGeometry geo) {
    final scheduleAsync = ref.watch(goatScheduleProvider);
    final schedule = scheduleAsync.value;
    final my = ref.watch(myRegionProvider);
    final now = _now(schedule);
    final banner = mapBanner(my: my, schedule: schedule, data: geo.data, now: now);

    return Stack(
      children: [
        Positioned.fill(
          child: MapView(
            geo: geo,
            schedule: schedule,
            myRegion: my.regionCode,
            selectedRegion: _selectedRegion,
            controller: _map,
            clock: widget.clock,
            onRegionTap: (code) => setState(() => _selectedRegion = code),
            onGoatTap: (goat) => showGoatSheet(
              context,
              ref: goat,
              schedule: schedule,
              data: geo.data,
              clock: widget.clock,
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: MediaQuery.paddingOf(context).top + 10,
          child: Column(
            children: [
              _BannerCard(
                banner: banner,
                onAction: banner.tone == BannerTone.arrived
                    ? () => context.push('/compose')
                    : () => ref.read(myRegionProvider.notifier).requestAndRefresh(),
              ),
              if (scheduleAsync.hasError && schedule == null) ...[
                const SizedBox(height: 8),
                _Pill(
                  text: '염소 일정을 불러오지 못했어요 · 다시 시도',
                  color: Palette.pink,
                  onTap: () => ref.invalidate(goatScheduleProvider),
                ),
              ] else if (scheduleAsync.isLoading && schedule == null) ...[
                const SizedBox(height: 8),
                const _Pill(text: '염소들을 불러오는 중…', color: Colors.white),
              ],
            ],
          ),
        ),
        Positioned(
          right: 12,
          bottom: (_selectedRegion != null ? 132 : 16),
          child: Column(
            children: [
              _RoundButton(
                icon: Icons.my_location_rounded,
                label: '내 위치',
                onTap: my.regionCode == null
                    ? () => ref.read(myRegionProvider.notifier).requestAndRefresh()
                    : () => _map.focusRegion(my.regionCode!),
              ),
              const SizedBox(height: 10),
              _RoundButton(icon: Icons.public_rounded, label: '전국', onTap: _map.showAll),
            ],
          ),
        ),
        if (_selectedRegion != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _RegionCard(
              region: geo.data.byCode[_selectedRegion]!,
              schedule: schedule,
              now: now,
              mine: _selectedRegion == my.regionCode,
              onClose: () => setState(() => _selectedRegion = null),
            ),
          ),
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.banner, required this.onAction});

  final MapBanner banner;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final color = switch (banner.tone) {
      BannerTone.arrived => Palette.yellow,
      BannerTone.waiting => Colors.white,
      BannerTone.info => Colors.white,
      BannerTone.warning => Palette.pink,
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Palette.outline, width: 2.5),
          boxShadow: const [BoxShadow(color: Color(0x335A4636), offset: Offset(0, 3))],
        ),
        child: Row(
          children: [
            if (banner.tone == BannerTone.arrived) ...[
              GoatAvatar(look: banner.goatLook ?? RollingLooks.city, size: 44),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    banner.title,
                    style: const TextStyle(
                      fontFamily: Fonts.title,
                      fontFamilyFallback: Fonts.fallback,
                      fontSize: 18,
                    ),
                  ),
                  if (banner.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(banner.subtitle!, style: const TextStyle(fontSize: 13.5, height: 1.35)),
                  ],
                ],
              ),
            ),
            if (banner.action != null) TextButton(onPressed: onAction, child: Text(banner.action!)),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, this.onTap});

  final String text;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Palette.outline, width: 2),
        ),
        child: Text(text, style: const TextStyle(fontSize: 13.5)),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Palette.outline, width: 2.5),
            boxShadow: const [BoxShadow(color: Color(0x335A4636), offset: Offset(0, 3))],
          ),
          child: Icon(icon, color: Palette.textBrown),
        ),
      ),
    );
  }
}

class _RegionCard extends StatelessWidget {
  const _RegionCard({
    required this.region,
    required this.schedule,
    required this.now,
    required this.mine,
    required this.onClose,
  });

  final Region region;
  final GoatSchedule? schedule;
  final DateTime now;
  final bool mine;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final here = schedule?.deliveryGoatsIn(region.code, now) ?? const [];
    final next = schedule?.nextDeliveryTo(region.code, now);
    final line = here.isNotEmpty
        ? '지금 ${namesIGa(here.map((g) => g.name).toList())} 머무는 중'
        : next != null
        ? '다음 배달 염소 ${next.$1.name} · ${formatRemaining(next.$2.difference(now))} 뒤 (${formatClock(next.$2)})'
        : schedule == null
        ? '염소 일정을 불러오는 중…'
        : '곧 염소가 들를 거예요';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.outline, width: 2.5),
        boxShadow: const [BoxShadow(color: Color(0x335A4636), offset: Offset(0, 3))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      region.fullName,
                      style: const TextStyle(
                        fontFamily: Fonts.title,
                        fontFamilyFallback: Fonts.fallback,
                        fontSize: 20,
                      ),
                    ),
                    if (mine) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Palette.yellow,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('우리 동네', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(line, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: '닫기',
            icon: const Icon(Icons.close_rounded, color: Palette.textBrown),
          ),
        ],
      ),
    );
  }
}
