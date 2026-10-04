-- 데이터 정합성 점검(부하 테스트 후, 백업 복구 리허설 후). 모든 violations가 0이어야 한다.
-- 사용: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f deploy/sql/integrity.sql
SELECT check_name, violations FROM (
  -- 포인트: 잔액 = 원장 합계(원장이 권위, CLAUDE.md)
  SELECT 'balance_equals_ledger_sum' AS check_name, count(*) AS violations
  FROM users u
  LEFT JOIN (SELECT "userId", sum(delta) AS s FROM points_ledger GROUP BY "userId") l ON l."userId" = u.id
  WHERE u."pointsBalance" <> coalesce(l.s, 0)
  UNION ALL
  SELECT 'no_negative_balance', count(*) FROM users WHERE "pointsBalance" < 0
  UNION ALL
  -- 원장 각 줄의 balanceAfter가 같은 사용자 직전 줄 + delta와 맞는가
  SELECT 'ledger_chain', count(*) FROM (
    SELECT "balanceAfter", delta,
           lag("balanceAfter") OVER (PARTITION BY "userId" ORDER BY "createdAt", "balanceAfter" - delta) AS prev
    FROM points_ledger
  ) c WHERE c.prev IS NOT NULL AND c.prev + c.delta <> c."balanceAfter"
  UNION ALL
  SELECT 'ledger_never_negative', count(*) FROM points_ledger WHERE "balanceAfter" < 0
  UNION ALL
  -- 광고 보상: 하루(KST) 5회 상한
  SELECT 'ad_reward_daily_cap', count(*) FROM (
    SELECT "userId", ("createdAt" AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul')::date d, count(*) n
    FROM points_ledger WHERE reason = 'AD_REWARD' GROUP BY 1, 2 HAVING count(*) > 5
  ) a
  UNION ALL
  -- 편지: 보낸 사람·받는 사람이 같은 편지 없음, 배달된 편지는 배달 시각이 있다
  SELECT 'no_self_letters', count(*) FROM letters WHERE "senderId" = "recipientId"
  UNION ALL
  SELECT 'delivered_has_time', count(*) FROM letters WHERE status = 'DELIVERED' AND "deliveredAt" IS NULL
  UNION ALL
  -- 롤링: 장당 1인 1회
  SELECT 'rolling_one_per_paper', count(*) FROM (
    SELECT "paperId", "authorId" FROM rolling_entries GROUP BY 1, 2 HAVING count(*) > 1
  ) r
  UNION ALL
  -- 위치: 사용자 테이블에 좌표 칼럼이 없다
  SELECT 'no_coordinate_columns', count(*) FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name IN ('users', 'user_region_reports', 'region_visits')
    AND column_name ~* '(lat|lng|lon|coord|geo)'
) checks
ORDER BY check_name;
