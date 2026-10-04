# 운영 (M9) — 배포 · 백업 · 복구

## 1. 배포 구성 (SPEC 2)

VPS 한 대에 Docker Compose: `postgres` · `api` · `caddy`.

```
인터넷 ─443→ caddy ─┬─ /admin*   관리자 SPA(정적, apps/admin/dist)
                    ├─ /api/*    → api:3000 (접두사 떼고, 관리자 SPA용)
                    └─ 그 밖      → api:3000 (앱·약관·계정 삭제·AdMob 콜백)
api ─ postgres(내부망, 5432는 127.0.0.1에만)
```

### 처음 한 번

```bash
git clone … /srv/meeil && cd /srv/meeil
cp apps/server/.env.example apps/server/.env.production   # 아래 값 채우기, 커밋 금지
echo 'API_DOMAIN=api.<도메인>' > .env                     # compose 변수(커밋 금지)
echo 'POSTGRES_PASSWORD=<openssl rand -base64 32>' >> .env
pnpm install && pnpm --filter @meeil/admin build          # 관리자 SPA → apps/admin/dist
docker compose --profile full --profile prod up -d --build
# 지역·염소·업적 시드(운영 이미지엔 tsx가 없어 호스트에서. 5432는 127.0.0.1에만 열려 있다)
DATABASE_URL=postgresql://meeil:<POSTGRES_PASSWORD>@localhost:5432/meeil pnpm --filter @meeil/server db:seed
docker compose exec -e ADMIN_PASSWORD=… api node dist/admin/cli.js <아이디> ADMIN
```

`apps/server/.env.production`에 꼭 넣을 값:

| 값                                       | 비고                                        |
| ---------------------------------------- | ------------------------------------------- |
| `JWT_SECRET`, `ADMIN_SECRET_KEY`         | 각각 `openssl rand -base64 48`              |
| `KAKAO_APP_ID`, `GOOGLE_CLIENT_IDS`      | `docs/SOCIAL_LOGIN.md`                      |
| `STORAGE_DRIVER=r2`, `R2_*`, `R2_BUCKET` | 사진(비공개)                                |
| `R2_BACKUP_BUCKET`                       | DB 백업(사진과 **다른** 비공개 버킷)        |
| `FCM_*`                                  | `docs/PUSH_AND_STORAGE.md`                  |
| `PUBLIC_BASE_URL=https://api.<도메인>`   |                                             |
| `ADMOB_AD_UNIT_IDS`                      | `docs/ADS.md`                               |
| `WEB_CONCURRENCY`, `DATABASE_POOL_MAX`   | 기본 1·20. 늘리는 기준은 `docs/LOADTEST.md` |

### 업데이트

```bash
git pull && docker compose --profile full --profile prod up -d --build api   # 기동 때 마이그레이션 자동 적용
pnpm --filter @meeil/admin build                                              # 관리자 SPA가 바뀌었으면
```

마이그레이션이 들어간 업데이트 전에는 `deploy/backup.sh`를 한 번 손으로 돌린다.

## 2. 백업

|        |                                                                                                                                                       |
| ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| 무엇   | PostgreSQL 전체(`pg_dump -Fc`, 압축·선택 복구 가능). 사진은 R2에 따로 있다(아래 "사진")                                                               |
| 언제   | 매일 03:18 KST(cron), 마이그레이션 배포 직전 수동                                                                                                     |
| 어디   | R2 백업 버킷 `db/meeil-YYYYMMDDTHHMMZ.dump.enc` + VPS `/var/backups/meeil`(최근 7일, R2 장애 대비)                                                    |
| 암호화 | AES-256-CBC, PBKDF2 20만 회. 암호 `BACKUP_PASSPHRASE`는 `deploy/.env.backup`(커밋 금지)과 **비밀번호 관리자 두 곳**에 둔다. 잃어버리면 백업을 못 푼다 |
| 보관   | 최근 30일은 매일, 그 이전은 달마다 첫 백업 12개월. 가장 최근 것은 늘 남김(`src/ops/retention.ts`)                                                     |
| 확인   | 올리기 전 덤프 목차를 읽어 테이블 데이터 20개 이상인지 검사, 1KB 미만 업로드 거부                                                                     |
| 알림   | `BACKUP_HEARTBEAT_URL`(예: healthchecks.io)을 넣으면 성공할 때마다 신호 → 하루 넘게 없으면 메일                                                       |

```bash
# VPS crontab -e (UTC 18:18 = KST 03:18)
18 18 * * * /srv/meeil/deploy/backup.sh >> /var/log/meeil-backup.log 2>&1
```

**목표**: RPO 24시간(하루치 데이터까지 잃을 수 있음), RTO 1시간(아래 절차로 서비스 재개).
편지는 하루에 몇 통 수준이고 포인트는 원장이라, 출시 초기에는 일 1회로 충분하다(SPEC 2). 사용자가 크게 늘면 WAL 아카이빙(PITR)을 검토한다.

### 사진

사진은 R2 비공개 버킷에만 있고 DB에는 키만 있다. R2는 내구성이 높아 따로 백업하지 않는다(정책 결정, `docs/DECISIONS.md`). DB를 과거 시점으로 되돌리면 그 뒤에 올라온 사진은 DB에 기록이 없는 파일로 R2에 남는다(매일 정리 작업은 DB 기록 기준이라 이 파일은 못 지운다). 양이 적어 그대로 두되, 개인정보라 복구 후 한 달 안에 백업 시점 이후에 올라온 `letters/*.webp` 객체(업로드 날짜로 구분)를 R2 콘솔에서 지운다.

## 3. 복구 절차

**먼저 새 DB에 풀어 확인 → 그다음 교체**. 운영 DB를 바로 덮어쓰지 않는다.

```bash
cd /srv/meeil
# 1) 최신 백업을 meeil_restore에 풀고 정합성 점검(운영은 그대로 돈다)
deploy/restore.sh                                   # 또는 deploy/restore.sh db/meeil-20261003T1818Z.dump.enc
                                                    # R2가 안 되면 --file /var/backups/meeil/meeil-….dump.enc
# 2) 내용 확인(최근 편지 시각 등)
docker compose exec postgres psql -U meeil meeil_restore -c 'select max("handedAt") from letters'
# 3) 교체: 서버 멈춤 → 운영 DB를 백업으로 덮어씀 → 서버 재개
docker compose --profile full stop api
TARGET_DB=meeil CONFIRM=yes deploy/restore.sh <같은 백업 키>
docker compose --profile full --profile prod up -d api
curl -fs https://api.<도메인>/health
```

교체 뒤 할 일:

- 앱 공지(관리자 → 공지·푸시)로 "○시 이후 보낸 편지가 사라졌을 수 있어요"를 알린다.
- 백업 시점 이후 가입한 사람의 refresh 토큰은 없으므로 다시 로그인하게 된다(정상).
- AdMob 보상·출석은 멱등 키가 있어 다시 들어와도 두 번 지급되지 않는다.

### VPS를 통째로 잃었을 때

새 VPS에서 "처음 한 번"을 하되 시드 대신 `TARGET_DB=meeil CONFIRM=yes deploy/restore.sh`로 R2의 최신 백업을 넣는다(`BACKUP_PASSPHRASE`·`.env.production`은 비밀번호 관리자에서). DNS를 새 IP로 바꾸면 Caddy가 인증서를 다시 받는다.

## 4. 복구 리허설

`deploy/rehearse-restore.sh` — 지금 DB를 백업 → `meeil_restore`로 복구 → 테이블별 행 수 비교 · 정합성 SQL 9개 · 마이그레이션 상태 · 복구한 DB로 서버 기동(`/health`, `/regions`)까지 확인하고 걸린 시간을 찍는다. 운영 DB는 읽기만 한다. **분기마다 한 번, 큰 마이그레이션 전에 한 번** 돌리고 아래 기록을 남긴다.

```bash
deploy/rehearse-restore.sh                 # VPS(R2 사용)
LOCAL=1 deploy/rehearse-restore.sh         # 개발 PC(임시 폴더, 로컬 빌드 서버)
```

| 날짜       | 어디서                               | 데이터                                                     | 백업 | 복구 | 결과                                                                                                         |
| ---------- | ------------------------------------ | ---------------------------------------------------------- | ---: | ---: | ------------------------------------------------------------------------------------------------------------ |
| 2026-10-04 | 개발 환경(`LOCAL=1`, 부하 테스트 DB) | 사용자 7,502 · 편지 1,344 · 원장 12,315 · 테이블 29 · 26MB |  1초 |  2초 | 통과: 행 수 29/29 일치, 정합성 위반 0, 마이그레이션 8:`20261003100000_deletion_requests`, 서버 기동·지역 246 |
| 출시 전    | VPS(R2)                              |                                                            |      |      | ⬜ 운영 키로 한 번                                                                                           |

함께 확인한 것: 암호화된 백업 파일에 평문(덤프 머리글 `PGDMP`, 닉네임, 생년월일)이 없고, 틀린 암호로는 풀리지 않는다.

## 5. 모니터링·장애 대응

| 무엇           | 어떻게                                                                                                          |
| -------------- | --------------------------------------------------------------------------------------------------------------- |
| 서버 살아 있음 | 외부 업타임 모니터가 `https://api.<도메인>/health`를 1분마다(Docker healthcheck도 15초마다 확인, 죽으면 재시작) |
| 백업 성공      | `BACKUP_HEARTBEAT_URL`                                                                                          |
| 앱 크래시      | `POST /client-errors` → 서버 로그 `client error`(관리자 대시보드 확장 후보)                                     |
| 디스크         | `df -h` 80% 넘으면 오래된 Docker 이미지(`docker image prune`)·로그 정리                                         |
| 로그           | `docker compose logs -f api` (요청당 한 줄: 메서드·라우트·상태·ms)                                              |

자주 있을 일:

- **서버가 안 뜸** → `docker compose logs api | tail -50`. `환경변수 오류`면 `.env.production` 확인. 마이그레이션 실패면 백업에서 복구 후 원인 수정.
- **느림** → `docs/LOADTEST.md`의 용량 추정과 비교, `WEB_CONCURRENCY`를 코어 수까지.
- **시크릿 유출 의심** → `JWT_SECRET` 교체(모두 다시 로그인), R2 토큰 재발급, `ADMIN_SECRET_KEY`는 교체 시 관리자 전원 재생성, 감사 로그 확인.
- **악성 사용자** → 관리자 화면에서 제재(즉시 반영: 요청마다 계정 상태 확인).
