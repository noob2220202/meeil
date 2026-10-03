import { useState, type FormEvent } from 'react';
import { fmt, type AdminMe, type Api, type NoticeItem } from '../api';
import { Empty, Loaded, useAction, useLoad } from '../ui';

export function Notices({ api, me }: { api: Api; me: AdminMe }) {
  const [load, retry] = useLoad(() => api.get<{ notices: NoticeItem[] }>('/admin/notices'), [api]);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [pinned, setPinned] = useState(false);
  const [push, setPush] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const { busy, error, run } = useAction();
  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (push && !confirm('알림을 켠 모든 사용자에게 푸시를 보낼까요?')) return;
    await run(async () => {
      const r = await api.post<{ pushed: number }>('/admin/notices', { title, body, pinned, push });
      setResult(push ? `게시했어요. 푸시 ${r.pushed}건 발송.` : '게시했어요.');
      setTitle('');
      setBody('');
      retry();
    });
  };
  return (
    <section>
      <h2>공지 · 푸시</h2>
      {me.role === 'ADMIN' ? (
        <form className="card" onSubmit={submit}>
          <input
            placeholder="제목"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            maxLength={60}
            required
            aria-label="공지 제목"
          />
          <textarea
            placeholder="내용"
            value={body}
            onChange={(e) => setBody(e.target.value)}
            rows={4}
            maxLength={2000}
            required
            aria-label="공지 내용"
          />
          <label className="check">
            <input type="checkbox" checked={pinned} onChange={(e) => setPinned(e.target.checked)} />{' '}
            맨 위에 고정
          </label>
          <label className="check">
            <input type="checkbox" checked={push} onChange={(e) => setPush(e.target.checked)} />{' '}
            푸시도 보내기
          </label>
          <button className="primary" disabled={busy}>
            게시
          </button>
          {result && <p className="ok-box">{result}</p>}
          {error && <p className="error-box">{error}</p>}
        </form>
      ) : (
        <p className="muted">공지 작성은 최고 관리자만 할 수 있어요.</p>
      )}
      <Loaded load={load} retry={retry}>
        {({ notices }) =>
          notices.length === 0 ? (
            <Empty>공지가 없어요.</Empty>
          ) : (
            <ul className="list">
              {notices.map((n) => (
                <li key={n.id} className="card">
                  <header>
                    {n.pinned && <span className="badge">고정</span>}
                    <strong>{n.title}</strong>
                    <span className="muted">
                      {n.publishedAt ? `게시 ${fmt(n.publishedAt)}` : '내림'} · {n.createdBy}
                    </span>
                  </header>
                  <p className="body">{n.body}</p>
                  {n.publishedAt && me.role === 'ADMIN' && (
                    <button
                      onClick={async () =>
                        (await run(() => api.post(`/admin/notices/${n.id}/unpublish`))) && retry()
                      }
                    >
                      내리기
                    </button>
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
