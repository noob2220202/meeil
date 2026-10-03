import '../../core/korean.dart';
import '../../data/regions.dart';
import '../location/my_region.dart';
import '../map/goat_painter.dart';
import 'schedule.dart';

/// 염소 종류 이름
String goatKindLabel(GoatInfo g, RegionData data) => switch (g.kind) {
  GoatKind.delivery => '배달 염소',
  GoatKind.rollingNation => '전국 롤링 염소',
  GoatKind.rollingProvince => '${data.provinceByCode[g.scopeCode]?.shortName ?? ''} 롤링 염소'.trim(),
  GoatKind.rollingCity => '${data.byCode[g.scopeCode]?.name ?? ''} 롤링 염소'.trim(),
};

/// 지금 어디서 뭘 하는지 한 줄
String goatStatusLine(GoatMoment m, RegionData data, DateTime now) {
  String name(String code) => data.byCode[code]?.fullName ?? code;
  return switch (m) {
    GoatStaying(:final stop) =>
      '${name(stop.regionCode)}에서 쉬는 중 · ${formatRemaining(stop.departAt.difference(now))} 뒤 출발',
    GoatTraveling(:final to) when to.bySea =>
      '배를 타고 ${euro(name(to.regionCode))} 가는 중 · ${formatRemaining(to.arriveAt.difference(now))} 뒤 도착',
    GoatTraveling(:final from, :final to) =>
      '${name(from.regionCode)} → ${name(to.regionCode)} · ${formatRemaining(to.arriveAt.difference(now))} 뒤 도착',
    GoatUnknown() => '어디쯤 있는지 확인하고 있어요',
  };
}

enum BannerTone { arrived, waiting, info, warning }

/// 지도 위쪽 안내 문구
class MapBanner {
  const MapBanner(this.title, this.subtitle, this.tone, {this.action, this.goatLook});

  final String title;
  final String? subtitle;
  final BannerTone tone;

  /// 버튼 문구(위치 켜기 등)
  final String? action;

  /// 도착한 염소 모습(배너에 작게 그린다)
  final GoatLook? goatLook;
}

MapBanner mapBanner({
  required MyRegionState my,
  required GoatSchedule? schedule,
  required RegionData data,
  required DateTime now,
}) {
  switch (my.status) {
    case MyRegionStatus.denied:
      return const MapBanner(
        '우리 동네 염소를 기다려 볼까요?',
        '대략적인 위치를 켜면 염소가 언제 오는지 알려 드려요.',
        BannerTone.info,
        action: '위치 켜기',
      );
    case MyRegionStatus.serviceOff:
      return const MapBanner(
        '휴대폰 위치 기능이 꺼져 있어요',
        '설정에서 위치를 켜면 우리 동네 염소를 찾을 수 있어요.',
        BannerTone.warning,
        action: '다시 확인',
      );
    case MyRegionStatus.outsideKorea:
      return const MapBanner('지금은 대한민국 밖에 있어요', '염소들은 대한민국 안에서만 배달해요.', BannerTone.info);
    case MyRegionStatus.error:
      if (my.regionCode == null) {
        return const MapBanner(
          '위치를 확인하지 못했어요',
          '잠시 후 다시 시도해 주세요.',
          BannerTone.warning,
          action: '다시 확인',
        );
      }
    case MyRegionStatus.idle || MyRegionStatus.locating:
      if (my.regionCode == null) {
        return const MapBanner('우리 동네를 찾는 중…', null, BannerTone.info);
      }
    case MyRegionStatus.ok:
      break;
  }
  final code = my.regionCode!;
  final place = data.byCode[code]?.fullName ?? '';
  if (schedule == null) return MapBanner(place, '염소들의 일정을 불러오는 중…', BannerTone.info);
  final here = schedule.deliveryGoatsIn(code, now);
  if (here.isNotEmpty) {
    return MapBanner(
      '우체부 염소가 왔어요!',
      '${namesIGa(here.map((g) => g.name).toList())} $place에 머무는 중이에요.',
      BannerTone.arrived,
      goatLook: here.first.look,
    );
  }
  final next = schedule.nextDeliveryTo(code, now);
  if (next == null) return MapBanner(place, '곧 염소가 들를 거예요.', BannerTone.waiting);
  final (goat, at) = next;
  return MapBanner(
    '다음 염소 ${goat.name} · ${formatRemaining(at.difference(now))} 뒤',
    '$place에 ${formatClock(at)}쯤 도착해요.',
    BannerTone.waiting,
  );
}
