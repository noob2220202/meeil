#!/usr/bin/env bash
# 백업에서 DB 복구(docs/OPERATIONS.md "복구"). 기본은 새 DB(meeil_restore)에 풀어 확인만 한다.
#   deploy/restore.sh                      # R2의 가장 최근 백업 → meeil_restore
#   deploy/restore.sh db/meeil-…dump.enc   # 특정 백업
#   deploy/restore.sh --file x.dump.enc    # VPS 로컬 사본
#   TARGET_DB=meeil deploy/restore.sh …    # 실제 교체(서버를 먼저 멈춘다 — 문서 절차대로)
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f deploy/.env.backup ] && set -a && . deploy/.env.backup && set +a
: "${BACKUP_PASSPHRASE:?deploy/.env.backup 에 BACKUP_PASSPHRASE가 필요해요}"
COMPOSE=${COMPOSE:-"docker compose --profile full"}
# 백업 보관소 CLI(기본: api 컨테이너 안). 리허설에서는 로컬 빌드 + BACKUP_DIR로 바꿔 끼운다
BACKUP_CLI=${BACKUP_CLI:-"$COMPOSE exec -T api node dist/ops/backup-cli.js"}
PGUSER_=${POSTGRES_USER:-meeil}
TARGET_DB=${TARGET_DB:-meeil_restore}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
started=$(date +%s)

if [ "${1:-}" = "--file" ]; then
  cp "$2" "$TMP/db.enc"; SRC="$2"
else
  KEY=${1:-$($BACKUP_CLI latest)}
  $BACKUP_CLI get "$KEY" > "$TMP/db.enc"; SRC="$KEY"
fi
echo "[$(date -Is)] 복구 시작: $SRC → $TARGET_DB"

openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:BACKUP_PASSPHRASE \
  -in "$TMP/db.enc" -out "$TMP/db.dump"

if [ "$TARGET_DB" != "meeil_restore" ] && [ "${CONFIRM:-}" != "yes" ]; then
  echo "운영 DB($TARGET_DB)를 덮어써요. 서버를 멈췄다면 CONFIRM=yes 를 붙여 다시 실행하세요."; exit 1
fi
$COMPOSE exec -T postgres dropdb -U "$PGUSER_" --if-exists --force "$TARGET_DB"
$COMPOSE exec -T postgres createdb -U "$PGUSER_" "$TARGET_DB"
$COMPOSE exec -T postgres pg_restore -U "$PGUSER_" -d "$TARGET_DB" --no-owner --no-privileges \
  --exit-on-error < "$TMP/db.dump"

echo "--- 정합성 점검 ---"
$COMPOSE exec -T postgres psql -U "$PGUSER_" -d "$TARGET_DB" -v ON_ERROR_STOP=1 -q < deploy/sql/integrity.sql
bad=$($COMPOSE exec -T postgres psql -U "$PGUSER_" -d "$TARGET_DB" -tA < deploy/sql/integrity.sql | awk -F'|' '$2 != 0' | wc -l)
[ "$bad" -eq 0 ] || { echo "정합성 점검 실패 $bad건"; exit 1; }
echo "[$(date -Is)] 복구 완료 $TARGET_DB ($(( $(date +%s) - started ))초)"
