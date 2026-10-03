# 외부 자산 라이선스

앱·서버에 포함된 외부 자산의 출처와 라이선스. 라이선스가 불명확한 자산은 쓰지 않는다.

| 자산              | 위치                                                                          | 출처                                                                                                               | 라이선스                               |
| ----------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | -------------------------------------- |
| 시군구 경계(가공) | `apps/mobile/assets/map/regions.json`, `apps/server/prisma/data/regions.json` | 통계청 SGIS 행정동 경계 → [vuski/admdongkor](https://github.com/vuski/admdongkor) `ver20260701` (commit `dd18816`) | 공공누리 제1유형(출처표시) / CC BY 4.0 |
| Jua 폰트          | `apps/mobile/assets/fonts/Jua-Regular.ttf`                                    | [Google Fonts](https://fonts.google.com/specimen/Jua)                                                              | SIL OFL 1.1 (`OFL-jua.txt`)            |
| Gowun Dodum 폰트  | `apps/mobile/assets/fonts/GowunDodum-Regular.ttf`                             | [Google Fonts](https://fonts.google.com/specimen/Gowun+Dodum)                                                      | SIL OFL 1.1 (`OFL-gowundodum.txt`)     |
| Gaegu 폰트        | `apps/mobile/assets/fonts/Gaegu-*.ttf`                                        | [Google Fonts](https://fonts.google.com/specimen/Gaegu)                                                            | SIL OFL 1.1 (`OFL-gaegu.txt`)          |

| Material Icons | Flutter SDK 기본 포함 (`uses-material-design`) | [Google Material Icons](https://fonts.google.com/icons) | Apache 2.0 |

## 직접 제작한 자산

| 자산                                           | 원본                                                              | 번들                                |
| ---------------------------------------------- | ----------------------------------------------------------------- | ----------------------------------- |
| 우체부 염소 얼굴, 편지 봉투, 두루마리 일러스트 | `assets-src/svg/*.svg` (손으로 작성한 SVG)                        | `apps/mobile/assets/illustrations/` |
| 스티커 20종                                    | `tools/stickers/src/build.ts`가 생성 → `assets-src/svg/stickers/` | `apps/mobile/assets/stickers/`      |
| 염소 캐릭터(지도·연출)                         | 코드로 그림 `apps/mobile/lib/features/map/goat_painter.dart`      | —                                   |
| 편지지 3종                                     | 코드로 그림 `apps/mobile/lib/features/letters/letter_paper.dart`  | —                                   |

## 경계 데이터 출처 표기 (앱 내 "오픈소스 라이선스" 화면에도 표시)

> 본 데이터는 통계청 통계지리정보서비스(SGIS, https://sgis.kostat.go.kr)에서 공공누리 제1유형으로 개방한
> 행정동 경계를 가공한 것이며(가공: vuski/admdongkor, https://github.com/vuski/admdongkor), CC BY 4.0으로 배포됩니다.
> 메에일은 이를 시 단위로 병합·단순화하여 사용합니다.

## 도구 (번들되지 않음)

- mapshaper (MPL-2.0): 경계 병합·단순화 (`tools/regions`)
