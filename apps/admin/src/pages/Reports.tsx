import { useState } from 'react';
import { fmt, statusLabel, type Api, type ReportItem } from '../api';
import { Empty, Loaded, useAction, useLoad } from '../ui';

const TYPE_LABEL = { LETTER: '편지', ROLLING_ENTRY: '두루마리 글', USER: '사용자' } as const;

/** 신고 큐: 오래된 것부터. 먹기(삭제) / 기각 / 사용자로 이동 */
export function Reports({ api }: { api: Api }) {
  const [status, setStatus] = useState<'OPEN' | 'RESOLVED' | 'DISMISSED'>('OPEN');
  const [load, retry] = useLoad(
    () => api.get<{ reports: ReportItem[] }>(`/admin/reports?status=${status}`),
    [api, status],
  );
  return (
    <section>
      <h2>신고 큐</h2>
      <div className="tabs" role="tablist">
        {(['OPEN', 'RESOLVED', 'DISMISSED'] as const).map((s) => (
          <button key={s} role="tab" aria-selected={status === s} onClick={() => setStatus(s)}>
            {{ OPEN: '처리 대기', RESOLVED: '처리됨', DISMISSED: '기각' }[s]}
          </button>
        ))}
      </div>
      <Loaded load={load} retry={retry}>
        {({ reports }) =>
          reports.length === 0 ? (
            <Empty>{status === 'OPEN' ? '처리할 신고가 없어요. 🐐' : '목록이 비어 있어요.'}</Empty>
          ) : (
            <ul className="list">
              {reports.map((r) => (
                <ReportCard key={r.id} r={r} api={api} onDone={retry} />
              ))}
            </ul>
          )
        }
      </Loaded>
    </section>
  );
}

function ReportCard({ r, api, onDone }: { r: ReportItem; api: Api; onDone: () => void }) {
  const { busy, error, run } = useAction();
  const eat = async () => {
    const path = r.letter
      ? `/admin/letters/${r.letter.id}/eat`
      : r.rollingEntry
        ? `/admin/rolling-entries/${r.rollingEntry.id}/eat`
        : null;
    if (
      !path ||
      !confirm(
        '염소가 이 글을 먹게 할까요? 받는 사람에게 보이지 않게 되고, 쓴 사람에게 알림이 가요.',
      )
    )
      return;
    if (await run(() => api.post(path, { reason: r.reasonLabel }))) onDone();
  };
  const dismiss = async () => {
    if (await run(() => api.post(`/admin/reports/${r.id}/dismiss`))) onDone();
  };
  const content = r.letter ?? r.rollingEntry;
  return (
    <li className="card report" data-testid={`report-${r.id}`}>
      <header>
        <span className="badge">{TYPE_LABEL[r.targetType]}</span>
        <strong>{r.reasonLabel}</strong>
        {r.sameTargetOpen > 1 && (
          <span className="badge warn">같은 대상 신고 {r.sameTargetOpen}건</span>
        )}
        <span className="muted">{fmt(r.createdAt)}</span>
      </header>
      <p className="muted">
        신고: {r.reporter.nickname ?? '(알 수 없음)'} → 대상:{' '}
        {r.targetUser ? (
          <a href={`#/users/${r.targetUser.id}`}>{r.targetUser.nickname ?? r.targetUser.id}</a>
        ) : (
          '—'
        )}
        {r.targetUser && r.targetUser.status !== 'ACTIVE' && (
          <span className="badge">{statusLabel(r.targetUser.status)}</span>
        )}
      </p>
      {r.detail && <blockquote className="detail">신고 내용: {r.detail}</blockquote>}
      {content && (
        <div className="content">
          <span className="badge">{statusLabel(content.status)}</span>
          <p className="body">{content.body || '(원본 삭제됨)'}</p>
          {r.letter?.photoUrl && (
            <img src={r.letter.photoUrl} alt="신고된 편지 사진" className="thumb" />
          )}
          {r.letter?.etaAt && content.status === 'IN_TRANSIT' && (
            <p className="muted">
              도착 예정 {fmt(r.letter.etaAt)} — 그 전에 먹으면 받는 사람에게 가지 않아요.
            </p>
          )}
        </div>
      )}
      {r.status === 'OPEN' ? (
        <div className="actions">
          {content && content.status !== 'EATEN' && (
            <button className="danger" disabled={busy} onClick={eat}>
              🐐 먹기(삭제)
            </button>
          )}
          <button disabled={busy} onClick={dismiss}>
            기각
          </button>
          {r.targetUser && <a href={`#/users/${r.targetUser.id}`}>제재하러 가기 →</a>}
        </div>
      ) : (
        <p className="muted">
          {r.status === 'RESOLVED' ? '처리됨' : '기각'} · {r.resolvedBy ?? '자동'} ·{' '}
          {fmt(r.resolvedAt)}
        </p>
      )}
      {error && <p className="error-box">{error}</p>}
    </li>
  );
}
