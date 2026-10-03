import { fmt, type AdminMe, type Api } from '../api';
import { Empty, Loaded, useAction, useLoad } from '../ui';

interface DeletionItem {
  id: string;
  nickname: string;
  contact: string | null;
  message: string | null;
  createdAt: string;
  processedAt: string | null;
  result: string | null;
  match: { id: string; nickname: string; createdAt: string; lastActiveAt: string } | null;
}

const RESULT: Record<string, string> = {
  DELETED: '삭제함',
  NOT_FOUND: '계정 없음',
  REJECTED: '거절',
};

/** 웹으로 들어온 계정 삭제 요청 (SPEC 8, 14). 7일 안에 처리한다. */
export function Deletions({ api, me }: { api: Api; me: AdminMe }) {
  const [load, retry] = useLoad(
    () => api.get<{ requests: DeletionItem[] }>('/admin/deletion-requests'),
    [api],
  );
  const { busy, error, run } = useAction();
  const act = async (id: string, action: 'DELETE' | 'REJECT') => {
    if (action === 'DELETE' && !confirm('이 계정을 탈퇴 처리할까요? 되돌릴 수 없어요.')) return;
    if (await run(() => api.post(`/admin/deletion-requests/${id}/process`, { action }))) retry();
  };
  return (
    <section>
      <h2>탈퇴 요청</h2>
      <p className="muted">
        앱을 쓸 수 없는 사람이 웹(/account/delete)으로 보낸 요청이에요. 7일 안에 처리하고, 결과는
        남긴 이메일로 알려 주세요(처리하면 이메일은 지워져요).
      </p>
      {error && <p className="error-box">{error}</p>}
      <Loaded load={load} retry={retry}>
        {({ requests }) =>
          requests.length === 0 ? (
            <Empty>탈퇴 요청이 없어요.</Empty>
          ) : (
            <ul className="list">
              {requests.map((r) => (
                <li key={r.id} className="card">
                  <header>
                    <strong>{r.nickname}</strong>
                    <span className="muted">요청 {fmt(r.createdAt)}</span>
                    {r.processedAt && (
                      <span className="badge">
                        {RESULT[r.result ?? ''] ?? r.result} · {fmt(r.processedAt)}
                      </span>
                    )}
                  </header>
                  {r.message && <p className="body">{r.message}</p>}
                  {r.contact && <p className="muted">연락처: {r.contact}</p>}
                  {!r.processedAt && (
                    <>
                      <p className="muted">
                        {r.match
                          ? `일치하는 계정: 가입 ${fmt(r.match.createdAt)}, 최근 접속 ${fmt(r.match.lastActiveAt)}`
                          : '이 닉네임의 계정을 찾지 못했어요.'}
                      </p>
                      {me.role === 'ADMIN' ? (
                        <div className="actions">
                          <button
                            className="danger"
                            disabled={busy}
                            onClick={() => act(r.id, 'DELETE')}
                          >
                            탈퇴 처리
                          </button>
                          <button disabled={busy} onClick={() => act(r.id, 'REJECT')}>
                            거절
                          </button>
                        </div>
                      ) : (
                        <p className="muted">처리는 최고 관리자만 할 수 있어요.</p>
                      )}
                    </>
                  )}
                </li>
              ))}
            </ul>
          )
        }
      </Loaded>
    </section>
  );
}
