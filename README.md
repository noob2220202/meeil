# 메에일 Meeil

대한민국 일러스트 지도 위를 우체부 염소들이 돌며 편지를 배달하는 Android 앱.

- 기획: [SPEC.md](SPEC.md) · 작업 규칙: [CLAUDE.md](CLAUDE.md) · 결정 기록: [docs/DECISIONS.md](docs/DECISIONS.md)

| 경로            | 내용                                     |
| --------------- | ---------------------------------------- |
| `apps/mobile`   | Flutter 앱 (Android, `com.meeil.app`)    |
| `apps/server`   | Fastify + Prisma + PostgreSQL API        |
| `apps/admin`    | React + Vite 관리자 웹                   |
| `tools/regions` | 행정구역 경계 → 시 단위 지역 데이터 생성 |

명령어는 [CLAUDE.md](CLAUDE.md)의 "명령어" 섹션 참고.
