#!/usr/bin/env bash
# 매일 DB 백업(SPEC 2: 일 1회 pg_dump → R2). VPS의 cron에서 저장소 루트 기준으로 실행한다.
#   18 3 * * *  /srv/meeil/deploy/backup.sh >> /var/log/meeil-backup.log 2>&1
# 필요: deploy/.env.backup 에 BACKUP_PASSPHRASE(분실하면 복구 불가 — 비밀번호 관리자에 보관),
#       apps/server/.env.production 에 R2_* 와 R2_BACKUP_BUCKET(사진과 다른 비공개 버킷).
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f deploy/.env.backup ] && set -a && . deploy/.env.backup && set +a
: "${BACKUP_PASSPHRASE:?deploy/.env.backup 에 BACKUP_PASSPHRASE가 필요해요}"
COMPOSE=${COMPOSE:-"docker compose --profile full"}
# 백업 보관소 CLI(기본: api 컨테이너 안). 리허설에서는 로컬 빌드 + BACKUP_DIR로 바꿔 끼운다
BACKUP_CLI=${BACKUP_CLI:-"$COMPOSE exec -T api node dist/ops/backup-cli.js"}
PGUSER_=${POSTGRES_USER:-meeil}
PGDB_=${POSTGRES_DB:-meeil}
LOCAL_DIR=${BACKUP_LOCAL_DIR:-/var/backups/meeil}
LOCAL_DAYS=${BACKUP_LOCAL_DAYS:-7}
KEY="db/meeil-$(date -u +%Y%m%dT%H%MZ).dump.enc"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
started=$(date +%s)

echo "[$(date -Is)] 백업 시작 $KEY"
# 1) 덤프(custom 형식: 압축 + 선택 복구 가능). 소유자·권한은 복구 대상에 맡긴다
$COMPOSE exec -T postgres pg_dump -U "$PGUSER_" -d "$PGDB_" -Fc --no-owner --no-privileges > "$TMP/db.dump"
# 2) 덤프가 읽히는지 목차로 확인(깨진 덤프를 올리지 않는다)
$COMPOSE exec -T postgres pg_restore --list < "$TMP/db.dump" > "$TMP/toc.txt"
tables=$(grep -c " TABLE DATA " "$TMP/toc.txt" || true)
[ "$tables" -ge 20 ] || { echo "덤프 목차가 이상해요(테이블 데이터 $tables개)"; exit 1; }
# 3) 암호화(생년월일 등 개인정보가 들어 있다)
openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass env:BACKUP_PASSPHRASE \
  -in "$TMP/db.dump" -out "$TMP/db.enc"
# 4) 올리기 + 보관 규칙(30일 매일 + 12개월 월초)
$BACKUP_CLI put "$KEY" < "$TMP/db.enc"
$BACKUP_CLI prune
# 5) VPS에도 최근 며칠치(R2 장애 대비)
mkdir -p "$LOCAL_DIR" && chmod 700 "$LOCAL_DIR"
cp "$TMP/db.enc" "$LOCAL_DIR/$(basename "$KEY")"
find "$LOCAL_DIR" -name 'meeil-*.dump.enc' -mtime +"$LOCAL_DAYS" -delete

size=$(du -h "$TMP/db.enc" | cut -f1)
echo "[$(date -Is)] 백업 완료 $KEY ($size, 테이블 $tables개, $(( $(date +%s) - started ))초)"
# 6) 성공 신호(선택): 외부 하트비트 모니터가 하루 넘게 신호를 못 받으면 알림
if [ -n "${BACKUP_HEARTBEAT_URL:-}" ]; then curl -fsS -m 10 "$BACKUP_HEARTBEAT_URL" > /dev/null || true; fi
