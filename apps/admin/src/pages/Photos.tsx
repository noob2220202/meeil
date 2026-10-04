import { useState } from 'react';
import { fmt, statusLabel, type Api, type PhotoItem } from '../api';
import { Empty, Loaded, useAction, useLoad } from '../ui';

/** 사진 검수 피드(최신순): 확인 완료 / 먹기 (SPEC 9.2) */
export function Photos({ api }: { api: Api }) {
  const [filter, setFilter] = useState<'unreviewed' | 'all'>('unreviewed');
  const [load, retry] = useLoad(
    () => api.get<{ photos: PhotoItem[] }>(`/admin/photos?filter=${filter}`),
    [api, filter],
  );
  return (
    <section>
      <h2>사진 검수</h2>
      <div className="tabs" role="tablist">
        <button
          role="tab"
          aria-selected={filter === 'unreviewed'}
          onClick={() => setFilter('unreviewed')}
        >
          미확인
        </button>
        <button role="tab" aria-selected={filter === 'all'} onClick={() => setFilter('all')}>
          전체
        </button>
      </div>
      <Loaded load={load} retry={retry}>
        {({ photos }) =>
          photos.length === 0 ? (
            <Empty>확인할 사진이 없어요. 🐐</Empty>
          ) : (
            <div className="photo-grid">
              {photos.map((p) => (
                <PhotoCard key={p.id} p={p} api={api} onDone={retry} />
              ))}
            </div>
          )
        }
      </Loaded>
    </section>
  );
}

function PhotoCard({ p, api, onDone }: { p: PhotoItem; api: Api; onDone: () => void }) {
  const { busy, error, run } = useAction();
  const l = p.letter;
  return (
    <figure className="card photo" data-testid={`photo-${p.id}`}>
      <img src={p.url} alt={`${l?.sender.nickname ?? ''}의 편지 사진`} loading="lazy" />
      <figcaption>
        <p>
          <strong>{l?.sender.nickname}</strong> → {l?.recipient.nickname}{' '}
          <span className="badge">{l ? statusLabel(l.status) : ''}</span>
        </p>
        <p className="body">{l?.body}</p>
        <p className="muted">
          올림 {fmt(p.createdAt)}
          {l?.status === 'IN_TRANSIT' && ` · 도착 ${fmt(l.etaAt)}`}
          {p.reviewedAt && ` · 확인 ${p.reviewedBy} ${fmt(p.reviewedAt)}`}
        </p>
        <div className="actions">
          {!p.reviewedAt && (
            <button
              className="primary"
              disabled={busy}
              onClick={async () =>
                (await run(() => api.post(`/admin/photos/${p.id}/review`))) && onDone()
              }
            >
              ✓ 확인 완료
            </button>
          )}
          {l && l.status !== 'EATEN' && (
            <button
              className="danger"
              disabled={busy}
              onClick={async () => {
                if (!confirm('염소가 이 편지를 먹게 할까요?')) return;
                if (
                  await run(() =>
                    api.post(`/admin/letters/${l.id}/eat`, { reason: '부적절한 사진' }),
                  )
                )
                  onDone();
              }}
            >
              🐐 먹기
            </button>
          )}
        </div>
        {error && <p className="error-box">{error}</p>}
      </figcaption>
    </figure>
  );
}
