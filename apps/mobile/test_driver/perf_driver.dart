// flutter drive 용: 통합 테스트가 보낸 프레임 요약을 build/에 저장한다
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    for (final e in data.entries) {
      await writeResponseData(e.value as Map<String, dynamic>, testOutputFilename: e.key);
    }
  },
);
