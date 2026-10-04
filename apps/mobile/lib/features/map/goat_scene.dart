import 'dart:math' as math;
import 'dart:ui';

import '../goats/schedule.dart';
import 'goat_painter.dart';
import 'map_geometry.dart';
import 'map_painters.dart';

/// 머무는 염소의 어슬렁 동작(화면 px): 쉬기 3초 → 오른쪽으로 2초 → 쉬기 2초 → 왼쪽으로 2초.
/// 지도가 늘 살아 움직이도록 하는 연출일 뿐, 스케줄 위치는 그대로다.
({double dx, bool walking, bool faceLeft}) strollAt(double t, double phase, {double reach = 14}) {
  const period = 9.0;
  final u = (t + phase * period) % period;
  if (u < 3) return (dx: 0, walking: false, faceLeft: false);
  if (u < 5) return (dx: reach * (u - 3) / 2, walking: true, faceLeft: false);
  if (u < 7) return (dx: reach, walking: false, faceLeft: true);
  return (dx: reach * (1 - (u - 7) / 2), walking: true, faceLeft: true);
}

/// 시 롤링 염소가 보이기 시작하는 배율(전국 보기 대비). SPEC 4.2: 시로 줌인했을 때만
const cityGoatRelZoom = 4.0;

/// 탭으로 고른 염소: 스케줄 염소 id 또는 시 롤링 염소(지역 코드)
sealed class GoatRef {
  const GoatRef();
}

class ScheduledGoatRef extends GoatRef {
  const ScheduledGoatRef(this.goatId);
  final String goatId;
}

class CityGoatRef extends GoatRef {
  const CityGoatRef(this.regionCode);
  final String regionCode;
}

const cityGoatPrefix = 'city:';

/// 지금 그릴 염소 목록을 만든다(순수 함수 — 같은 입력이면 같은 결과).
List<GoatSprite> buildGoatSprites({
  required MapGeometry geo,
  required GoatSchedule? schedule,
  required DateTime now,
  required double t,
  required double relZoom,
  required Rect visibleWorld,
  required double goatSize,
}) {
  final out = <GoatSprite>[];
  if (schedule != null) {
    // 같은 지역에 머무는 염소들은 옆으로 비켜 선다
    final stayingByRegion = <String, List<String>>{};
    final moments = <String, GoatMoment>{};
    for (final tr in schedule.tracks.values) {
      final m = tr.at(now);
      moments[tr.goat.id] = m;
      if (m is GoatStaying) {
        stayingByRegion.putIfAbsent(m.stop.regionCode, () => []).add(tr.goat.id);
      }
    }
    for (final list in stayingByRegion.values) {
      list.sort();
    }

    for (final tr in schedule.tracks.values) {
      final g = tr.goat;
      final priority = switch (g.kind) {
        GoatKind.delivery => 3,
        GoatKind.rollingProvince => 2,
        GoatKind.rollingNation => 2,
        GoatKind.rollingCity => 1,
      };
      switch (moments[g.id]!) {
        case GoatStaying(:final stop):
          final here = geo.regionCenter(stop.regionCode);
          final mates = stayingByRegion[stop.regionCode]!;
          final i = mates.indexOf(g.id);
          final spread = goatSize * 0.62;
          final nudge = Offset((i - (mates.length - 1) / 2) * spread, (i.isOdd ? 6 : 0));
          final stroll = strollAt(t, phaseOf(g.id));
          out.add(
            GoatSprite(
              id: g.id,
              world: here,
              look: g.look,
              pose: stroll.walking ? GoatPose.walk : GoatPose.idle,
              faceLeft: stroll.faceLeft,
              phase: phaseOf(g.id),
              priority: priority,
              screenNudge: nudge + Offset(stroll.dx - 7, 0),
            ),
          );
        case GoatTraveling(:final from, :final to, :final progress):
          final a = geo.regionCenter(from.regionCode);
          final b = geo.regionCenter(to.regionCode);
          out.add(
            GoatSprite(
              id: g.id,
              world: lerpTravel(a, b, progress),
              look: g.look,
              pose: GoatPose.walk,
              faceLeft: b.dx < a.dx,
              phase: phaseOf(g.id),
              bySea: to.bySea,
              priority: priority,
            ),
          );
        case GoatUnknown():
          break;
      }
    }
  }

  // 시 롤링 염소: 자기 시 안을 천천히 어슬렁
  if (relZoom >= cityGoatRelZoom) {
    final look = schedule?.cityGoatLook ?? RollingLooks.city;
    for (final shape in geo.regions.values) {
      if (!visibleWorld.contains(shape.center)) continue;
      final ph = phaseOf(shape.region.code) * 2 * math.pi;
      final wx = math.sin(t * 0.35 + ph);
      out.add(
        GoatSprite(
          id: '$cityGoatPrefix${shape.region.code}',
          world: shape.center,
          look: look,
          pose: GoatPose.walk,
          faceLeft: math.cos(t * 0.35 + ph) < 0,
          phase: ph,
          priority: 1,
          screenNudge: Offset(22 * wx, 26 + 6 * math.sin(t * 0.22 + ph)),
        ),
      );
    }
  }
  return out;
}

GoatRef? goatRefOf(String spriteId) => spriteId.startsWith(cityGoatPrefix)
    ? CityGoatRef(spriteId.substring(cityGoatPrefix.length))
    : ScheduledGoatRef(spriteId);
