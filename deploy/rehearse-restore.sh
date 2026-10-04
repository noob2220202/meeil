#!/usr/bin/env bash
# 백업·복구 리허설(M9, 분기마다 반복 — docs/OPERATIONS.md).
# 지금 DB를 백업 → 새 DB(meeil_restore)로 복구 → 행 수 비교·정합성·마이그레이션·서버 기동까지 확인하고
# 걸린 시간(RTO 실측)을 출력한다. 운영 DB는 읽기만 한다.
#   VPS:    deploy/rehearse-restore.sh
#   로컬:   LOCAL=1 deploy/rehearse-restore.sh   (R2 대신 임시 폴더, 서버는 로컬 빌드로 기동)
set -euo pipefail
cd "$(dirname "$0")/.."

COMPOSE=${COMPOSE:-"docker compose --profile full"}
PGUSER_=${POSTGRES_USER:-meeil}
PGDB_=${POSTGRES_DB:-meeil}
psql_() { $COMPOSE exec -T postgres psql -U "$PGUSER_" -tA "$@"; }

if [ "${LOCAL:-}" = "1" ]; then
  COMPOSE="docker compose"
  export BACKUP_DIR=${BACKUP_DIR:-$(mktemp -d)}
  export BACKUP_LOCAL_DIR=$BACKUP_DIR/local
  export BACKUP_PASSPHRASE=${BACKUP_PASSPHRASE:-rehearsal-only-$(date +%s)}
  export BACKUP_CLI="node apps/server/dist/ops/backup-cli.js"
  export COMPOSE
  (cd apps/server && npx tsc -p tsconfig.build.json)
fi

counts() {
  psql_ -d "$1" -c "SELECT string_agg(t || '=' || n, ' ' ORDER BY t) FROM (
    SELECT table_name t, (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) c FROM %I', table_name), false, true, '')))[1]::text::bigint n
    FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE') x"
}

t0=$(date +%s)
echo "== 1. 원본 행 수 ($PGDB_)"
before=$(counts "$PGDB_"); echo "$before" | tr ' ' '\n' | sed 's/=/ /;s/^/  /'

echo "== 2. 백업"
deploy/backup.sh
t1=$(date +%s)

echo "== 3. 복구 → meeil_restore"
TARGET_DB=meeil_restore deploy/restore.sh
t2=$(date +%s)

echo "== 4. 행 수 비교"
after=$(counts meeil_restore)
fail=0
for kv in $before; do
  t=${kv%%=*}; n=${kv#*=}
  m=$(echo "$after" | tr ' ' '\n' | grep "^$t=" | cut -d= -f2 || echo missing)
  # 운영 중 리허설이면 덤프 사이에 들어온 쓰기만큼 차이가 날 수 있다(1% + 5행까지 허용)
  if [ "$m" = "missing" ] || [ $(( n - m < 0 ? m - n : n - m )) -gt $(( n / 100 + 5 )) ]; then
    echo "  ✗ $t 원본 $n / 복구 $m"; fail=1
  fi
done
[ $fail -eq 0 ] && echo "  ✓ 모든 테이블 행 수 일치($(echo "$before" | wc -w)개)"

echo "== 5. 마이그레이션 상태"
src_mig=$(psql_ -d "$PGDB_" -c "SELECT count(*) || ':' || max(migration_name) FROM _prisma_migrations WHERE finished_at IS NOT NULL")
dst_mig=$(psql_ -d meeil_restore -c "SELECT count(*) || ':' || max(migration_name) FROM _prisma_migrations WHERE finished_at IS NOT NULL")
if [ "$src_mig" = "$dst_mig" ]; then echo "  ✓ $dst_mig"; else echo "  ✗ 원본 $src_mig / 복구 $dst_mig"; fail=1; fi

echo "== 6. 복구한 DB로 서버 기동"
if [ "${LOCAL:-}" = "1" ]; then
  url="postgresql://$PGUSER_:${POSTGRES_PASSWORD:-meeil}@localhost:5432/meeil_restore"
  ( cd apps/server && DATABASE_URL=$url PORT=3299 JOBS_ENABLED=false AUTH_DEV_LOGIN=false \
      exec node dist/server.js > /tmp/meeil-rehearsal-server.log 2>&1 ) &
  pid=$!
  ok=0; for _ in $(seq 1 20); do sleep 1; curl -fs localhost:3299/health > /dev/null && { ok=1; break; }; done
  regions=$(curl -fs localhost:3299/regions | grep -o '"code"' | wc -l || true)
  kill "$pid" 2>/dev/null || true
else
  ok=0
  $COMPOSE run --rm -e DATABASE_URL="postgresql://$PGUSER_:${POSTGRES_PASSWORD:-meeil}@postgres:5432/meeil_restore" \
    -e JOBS_ENABLED=false -e PORT=3299 api sh -c 'node dist/server.js & sleep 8; wget -qO- http://127.0.0.1:3299/regions' > /tmp/meeil-rehearsal-regions.json && ok=1
  regions=$(grep -o '"code"' /tmp/meeil-rehearsal-regions.json | wc -l || true)
fi
if [ $ok -eq 1 ] && [ "$regions" -gt 100 ]; then echo "  ✓ /health, /regions($regions)"; else echo "  ✗ 서버 기동 실패"; fail=1; fi

echo "== 결과"
echo "  백업 $((t1 - t0))초 · 복구 $((t2 - t1))초 · 전체 $(( $(date +%s) - t0 ))초"
psql_ -d meeil_restore -c "SELECT pg_size_pretty(pg_database_size('meeil_restore'))" | sed 's/^/  DB 크기 /'
if [ $fail -eq 0 ]; then echo "  리허설 통과"; else echo "  리허설 실패"; exit 1; fi
[ "${KEEP:-}" = "1" ] || psql_ -d postgres -c "DROP DATABASE meeil_restore WITH (FORCE)" > /dev/null
