# 성능 점검 (M7, SPEC 11.1: 염소 12~30마리 60fps)

## 자동 측정 (CI, 디버그 JIT 기준이라 실제보다 느리다)

`apps/mobile/test/map_perf_test.dart` — 한 프레임의 그리기 명령 기록 비용

| 상황                                          | 프레임당 | 예산   |
| --------------------------------------------- | -------- | ------ |
| 전국 보기 29마리                              | 약 2.1ms | < 8ms  |
| 서울 확대 59마리(시 롤링 염소 포함)           | 약 1.7ms | < 8ms  |
| 스트레스: 일정 2배, 전국 58마리               | 약 2.7ms | < 10ms |
| 땅 레이어 다시 그리기(배율 6% 이상 바뀔 때만) | 약 1.7ms | < 16ms |

## 실기기(Galaxy) 측정

GPU 래스터까지 포함한 진짜 프레임 시간은 실기기에서 잰다.

```bash
cd apps/mobile
flutter drive --profile --driver=test_driver/perf_driver.dart \
  --target=integration_test/map_perf_test.dart --dart-define=GOATS=30   # 60으로도 한 번
```

- 서버 없이 결정적 가짜 일정으로 염소 N마리를 띄우고, 5초 대기 → 지도 끌기 4번 → 서울 확대 → 끌기를 한다.
- 결과: `build/map_frames.timeline_summary.json` — `90th_percentile_frame_build_time_millis`, `90th_percentile_frame_rasterizer_time_millis`, `missed_frame_build_budget_count` 등.
- 기준: 90퍼센타일 빌드·래스터 각각 16ms 미만, 놓친 프레임 5% 미만. 넘으면 DevTools Performance 탭에서 `OverlayPainter`/`LandPainter`를 본다.

## 적용한 최적화

- 땅(시 경계·물결)은 `RepaintBoundary` + `isComplex` 레이어로 분리, 이동 중엔 다시 그리지 않고 배율이 6% 넘게 바뀔 때만 다시 그린다.
- 염소·이름표는 별도 오버레이 레이어에서만 매 프레임 그린다. 화면 밖 염소는 건너뛴다.
- 이름표 `TextPainter`, 물결 위치, 경로는 캐시한다.
- 동작 줄이기 설정이면 매 프레임 대신 1초에 한 번만 갱신한다.
- 탭에 없을 때(`TickerMode`) 지도 애니메이션이 멈춘다.

## 크래시 대비

- `CrashGuard`: 프레임워크·비동기 오류를 잡아 앱을 끝내지 않고, 운영 빌드는 오류 요약(메시지·스택 앞부분, 사용자 정보 없음)을 `POST /client-errors`로 보낸다(같은 오류 1번, 1분 5건). 서버는 로그로만 남긴다.
- 운영 빌드에서 위젯 하나가 실패하면 빨간 화면 대신 "염소가 여기를 그리다 넘어졌어요" 카드.
