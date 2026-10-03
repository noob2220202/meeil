import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import '../../data/regions.dart';
import '../auth/session.dart';

/// 기기 위치 한 번 읽은 결과. 좌표는 기기 안에서만 쓰고 서버로 보내지 않는다.
class LocationFix {
  const LocationFix(this.lon, this.lat, {this.mocked = false});
  final double lon;
  final double lat;
  final bool mocked;
}

enum LocationAccess { granted, denied, deniedForever, serviceOff }

/// 위치 읽기 추상화(테스트에서 교체)
abstract class LocationSource {
  Future<LocationAccess> access();
  Future<LocationAccess> requestAccess();
  Future<LocationFix?> currentFix();
  Future<void> openSettings();
}

/// 대략적 위치(coarse)·포그라운드에서만 (SPEC 8)
class GeolocatorSource implements LocationSource {
  @override
  Future<LocationAccess> access() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;
    return _map(await Geolocator.checkPermission());
  }

  @override
  Future<LocationAccess> requestAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;
    return _map(await Geolocator.requestPermission());
  }

  LocationAccess _map(LocationPermission p) => switch (p) {
    LocationPermission.always || LocationPermission.whileInUse => LocationAccess.granted,
    LocationPermission.deniedForever => LocationAccess.deniedForever,
    _ => LocationAccess.denied,
  };

  @override
  Future<LocationFix?> currentFix() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return LocationFix(p.longitude, p.latitude, mocked: p.isMocked);
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      return last == null
          ? null
          : LocationFix(last.longitude, last.latitude, mocked: last.isMocked);
    }
  }

  @override
  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }
}

final locationSourceProvider = Provider<LocationSource>((ref) => GeolocatorSource());

/// 서버 보고 결과
class RegionReport {
  const RegionReport({required this.accepted, this.regionCode});
  final bool accepted;

  /// 서버가 인정한 현재 지역(거부 시 이전 값)
  final String? regionCode;
}

/// 지역 코드 보고 API(좌표는 보내지 않는다)
class RegionApi {
  RegionApi(this.client);
  final ApiClient client;

  Future<RegionReport> report(String regionCode, {required bool mocked}) async {
    final res = await client.post('/me/region', {'regionCode': regionCode, 'mocked': mocked});
    return RegionReport(
      accepted: res['accepted'] as bool,
      regionCode: res['regionCode'] as String?,
    );
  }
}

final regionApiProvider = Provider<RegionApi>((ref) => RegionApi(ref.watch(apiClientProvider)));

enum MyRegionStatus { idle, locating, ok, denied, serviceOff, outsideKorea, error }

class MyRegionState {
  const MyRegionState({required this.status, this.regionCode, this.rejected = false});

  final MyRegionStatus status;

  /// 서버가 받아들인 내 시
  final String? regionCode;

  /// 마지막 보고가 거부됨(가짜 위치 등)
  final bool rejected;

  MyRegionState copyWith({MyRegionStatus? status, String? regionCode, bool? rejected}) =>
      MyRegionState(
        status: status ?? this.status,
        regionCode: regionCode ?? this.regionCode,
        rejected: rejected ?? this.rejected,
      );
}

/// 내 시 판정·보고. 앱을 보고 있는 동안에만, 지역이 바뀌거나 5분마다 보고한다(SPEC 15 배터리).
class MyRegionController extends Notifier<MyRegionState> {
  static const reportInterval = Duration(minutes: 5);

  Timer? _timer;
  DateTime? _lastReportAt;
  String? _lastReportedCode;

  @override
  MyRegionState build() {
    ref.onDispose(() => _timer?.cancel());
    return const MyRegionState(status: MyRegionStatus.idle);
  }

  /// 화면에 보일 때 호출. 권한이 없으면 묻지 않고 상태만 알린다(묻는 건 버튼으로).
  void resume() {
    _timer?.cancel();
    unawaited(refresh());
    _timer = Timer.periodic(reportInterval, (_) => refresh());
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  /// 권한 요청 버튼
  Future<void> requestAndRefresh() async {
    final access = await ref.read(locationSourceProvider).requestAccess();
    if (access == LocationAccess.deniedForever) {
      await ref.read(locationSourceProvider).openSettings();
    }
    await refresh();
  }

  Future<void> refresh() async {
    final source = ref.read(locationSourceProvider);
    final access = await source.access();
    if (access == LocationAccess.serviceOff) {
      state = state.copyWith(status: MyRegionStatus.serviceOff);
      return;
    }
    if (access != LocationAccess.granted) {
      state = state.copyWith(status: MyRegionStatus.denied);
      return;
    }
    if (state.regionCode == null) state = state.copyWith(status: MyRegionStatus.locating);
    try {
      final fix = await source.currentFix();
      if (fix == null) {
        state = state.copyWith(status: MyRegionStatus.error);
        return;
      }
      final data = await ref.read(regionDataProvider.future);
      final code = data.locate(fix.lon, fix.lat);
      if (code == null) {
        state = state.copyWith(status: MyRegionStatus.outsideKorea);
        return;
      }
      final due =
          _lastReportAt == null ||
          DateTime.now().difference(_lastReportAt!) >= reportInterval - const Duration(seconds: 5);
      if (code == _lastReportedCode && !due) return;
      final res = await ref.read(regionApiProvider).report(code, mocked: fix.mocked);
      _lastReportAt = DateTime.now();
      _lastReportedCode = code;
      state = MyRegionState(
        status: MyRegionStatus.ok,
        regionCode: res.accepted ? code : (res.regionCode ?? state.regionCode),
        rejected: !res.accepted,
      );
    } on ApiException {
      state = state.copyWith(status: MyRegionStatus.error);
    }
  }
}

final myRegionProvider = NotifierProvider<MyRegionController, MyRegionState>(
  MyRegionController.new,
);
