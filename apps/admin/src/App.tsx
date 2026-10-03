import { useEffect, useState } from 'react';

type Health = { state: 'loading' } | { state: 'ok'; time: string } | { state: 'error' };

/** M0 뼈대: 서버 연결 상태만 보여준다. 로그인·대시보드는 M6에서. */
export function App({ fetcher = fetch }: { fetcher?: typeof fetch }) {
  const [health, setHealth] = useState<Health>({ state: 'loading' });

  useEffect(() => {
    let alive = true;
    fetcher('/api/health')
      .then(async (res) => {
        if (!res.ok) throw new Error(String(res.status));
        const body = (await res.json()) as { time: string };
        if (alive) setHealth({ state: 'ok', time: body.time });
      })
      .catch(() => alive && setHealth({ state: 'error' }));
    return () => {
      alive = false;
    };
  }, [fetcher]);

  return (
    <main className="shell">
      <h1>메에일 관리자</h1>
      <p className="status" data-state={health.state}>
        {health.state === 'loading' && '서버 상태 확인 중…'}
        {health.state === 'ok' && `서버 정상 · ${new Date(health.time).toLocaleString('ko-KR')}`}
        {health.state === 'error' && '서버에 연결할 수 없어요'}
      </p>
    </main>
  );
}
