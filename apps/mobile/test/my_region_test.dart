import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/core/token_store.dart';
import 'package:meeil/features/location/my_region.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<ProviderContainer> container({
  required FakeLocationSource location,
  FakeRegionApi? api,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = MemoryTokenStore();
  final c = ProviderContainer(
    overrides: await appOverrides(
      backend: FakeBackend(),
      store: store,
      location: location,
      regionApi: api ?? FakeRegionApi(store),
    ),
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('기기에서 시를 판정해 코드만 보고한다', () async {
    final api = FakeRegionApi(MemoryTokenStore());
    final c = await container(
      location: FakeLocationSource(fix: const LocationFix(126.9769, 37.5759)),
      api: api,
    );
    await c.read(myRegionProvider.notifier).refresh();
    final s = c.read(myRegionProvider);
    expect(s.status, MyRegionStatus.ok);
    expect(s.regionCode, '11110');
    expect(api.reports, ['11110']);

    // 같은 시에서 5분 안에 다시 읽으면 보고하지 않는다
    await c.read(myRegionProvider.notifier).refresh();
    expect(api.reports, ['11110']);
  });

  test('가짜 위치는 서버가 거부 → 내 시로 쓰지 않는다', () async {
    final c = await container(
      location: FakeLocationSource(fix: const LocationFix(126.9769, 37.5759, mocked: true)),
    );
    await c.read(myRegionProvider.notifier).refresh();
    final s = c.read(myRegionProvider);
    expect(s.rejected, isTrue);
    expect(s.regionCode, isNull);
  });

  test('권한 거부·위치 꺼짐·해외', () async {
    for (final (src, status) in [
      (FakeLocationSource(grant: LocationAccess.denied), MyRegionStatus.denied),
      (FakeLocationSource(grant: LocationAccess.serviceOff), MyRegionStatus.serviceOff),
      (FakeLocationSource(fix: const LocationFix(139.69, 35.69)), MyRegionStatus.outsideKorea),
    ]) {
      final c = await container(location: src);
      await c.read(myRegionProvider.notifier).refresh();
      expect(c.read(myRegionProvider).status, status);
    }
  });
}
