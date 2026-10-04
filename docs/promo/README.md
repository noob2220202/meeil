# 홍보 영상

- `meeil_promo.mp4` — 세로 1080×1920, 30fps, 11초, AAC 소리(배경음악 + 효과음)
- `poster.png` — 영상 6.3초 장면(썸네일)
- `screens/` — 영상에 쓴 앱 화면 캡처(Galaxy 해상도 1080×2400, 앱 코드로 렌더링)

모든 그림·소리는 이 저장소에서 만든 것이다(외부 이미지·음원·AI 생성 없음).
배경음악은 `tools/promo/src/bgm.ts`가 합성, 효과음은 `tools/sounds`, 염소는 앱의 `GoatPainterKit`.

## 다시 만들기

```bash
cd apps/mobile
flutter test --tags screenshot   # 앱 화면 → build/screenshots/
flutter test --tags store-assets # 아이콘·스플래시(인트로 얼굴에 사용)
flutter test --tags promo        # 염소 걷기·먹기 프레임 → build/promo/
cd ../..
pnpm --filter @meeil/tools-promo bgm    # 배경음악 → apps/mobile/build/promo/bgm.wav
pnpm --filter @meeil/tools-promo video  # 영상 → docs/promo/meeil_promo.mp4 (ffmpeg, Python Pillow 필요)
```

## 구성(음악 마디에 맞춘 컷)

| 시간     | 장면                            | 자막                                             | 소리             |
| -------- | ------------------------------- | ------------------------------------------------ | ---------------- |
| 0.0–2.0  | 햇살 속 염소 얼굴 등장, 제목    | 메에일 / 우체부 염소가 전해 주는 느린 편지       | 염소 울음        |
| 2.0–4.0  | 전국 지도(확대), 염소들 걸어감  | 우체부 염소들이 전국을 돌아요                    | 짧은 울음        |
| 4.0–6.0  | 편지 쓰기 → 번쩍 → 맡기기       | 우리 동네에 염소가 오면 / 염소 가방에 편지를 쏙! | 편지 소리        |
| 6.0–7.5  | 편지 도착, 하트 꽃가루          | 편지가 도착했어요!                               | 반짝, 편지       |
| 7.5–8.5  | 전국 두루마리                   | 다 같이 쓰는 롤링페이퍼                          | 도장             |
| 8.5–9.3  | 염소가 편지를 냠냠(흔들기)      | 나쁜 편지는 염소가 냠냠!                         | 냠냠             |
| 9.3–11.0 | 로고 도장 쾅, 염소 행진, 페이드 | 곧 Google Play에서 만나요                        | 도장, 반짝, 울음 |
