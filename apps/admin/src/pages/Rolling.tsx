import { useState, type FormEvent } from 'react';
import { fmt, type AdminMe, type Api, type TopicItem } from '../api';
import { Empty, Loaded, useAction, useLoad } from '../ui';

const LEVEL = { NATION: '전국', PROVINCE: '도', CITY: '시' } as const;

export function Rolling({ api, me }: { api: Api; me: AdminMe }) {
  const [load, retry] = useLoad(
    () =>
      api.get<{ topics: TopicItem[]; periods: Record<string, { current: string; next: string }> }>(
        '/admin/rolling/topics',
      ),
    [api],
  );
  const [level, setLevel] = useState<keyof typeof LEVEL>('NATION');
  const [scope, setScope] = useState('*');
  const [when, setWhen] = useState<'current' | 'next'>('current');
  const [topic, setTopic] = useState('');
  const [welcome, setWelcome] = useState('');
  const [msg, setMsg] = useState<string | null>(null);
  const { busy, error, run } = useAction();

  const saveTopic = async (e: FormEvent) => {
    e.preventDefault();
    await run(async () => {
      await api.post('/admin/rolling/topics', {
        level,
        scopeCode: level === 'NATION' ? 'KR' : scope,
        when,
        topic,
      });
      setMsg('주제를 저장했어요.');
      setTopic('');
      retry();
    });
  };
  const postWelcome = async (e: FormEvent) => {
    e.preventDefault();
    await run(async () => {
      await api.post('/admin/rolling/official-entry', {
        level,
        scopeCode: level === 'NATION' ? 'KR' : scope,
        body: welcome,
      });
      setMsg('메에일 우체국 이름으로 환영 글을 남겼어요.');
      setWelcome('');
    });
  };

  return (
    <section>
      <h2>롤링페이퍼</h2>
      <form className="card" onSubmit={saveTopic}>
        <h3>주제 정하기</h3>
        <div className="row">
          <select
            value={level}
            onChange={(e) => setLevel(e.target.value as keyof typeof LEVEL)}
            aria-label="레벨"
          >
            {Object.entries(LEVEL).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
          {level !== 'NATION' && (
            <input
              value={scope}
              onChange={(e) => setScope(e.target.value)}
              placeholder="* 또는 지역 코드"
              aria-label="지역 코드"
              pattern="\*|\d{2}|\d{5}"
              title="* (전체) 또는 도 2자리 / 시 5자리 코드"
            />
          )}
          <select
            value={when}
            onChange={(e) => setWhen(e.target.value as 'current' | 'next')}
            aria-label="적용할 장"
          >
            <option value="current">이번 장</option>
            <option value="next">다음 장</option>
          </select>
        </div>
        <input
          value={topic}
          onChange={(e) => setTopic(e.target.value)}
          placeholder="주제(60자)"
          maxLength={60}
          required
          aria-label="주제"
        />
        <button className="primary" disabled={busy}>
          저장
        </button>
      </form>
      {me.role === 'ADMIN' && (
        <form className="card" onSubmit={postWelcome}>
          <h3>공식 계정 환영 글</h3>
          <p className="muted">
            위에서 고른 레벨·지역의 이번 장에 "메에일 우체국" 이름으로 남겨요(다시 쓰면 고쳐져요).
          </p>
          <textarea
            value={welcome}
            onChange={(e) => setWelcome(e.target.value)}
            maxLength={200}
            rows={2}
            required
            aria-label="환영 글"
          />
          <button disabled={busy || (level !== 'NATION' && scope === '*')}>남기기</button>
        </form>
      )}
      {msg && <p className="ok-box">{msg}</p>}
      {error && <p className="error-box">{error}</p>}
      <h3>최근 주제</h3>
      <Loaded load={load} retry={retry}>
        {({ topics }) =>
          topics.length === 0 ? (
            <Empty>정한 주제가 없어요. 주제가 없으면 자유 주제예요.</Empty>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>레벨</th>
                  <th>지역</th>
                  <th>장 시작</th>
                  <th>주제</th>
                </tr>
              </thead>
              <tbody>
                {topics.map((t) => (
                  <tr key={`${t.level}-${t.scopeCode}-${t.periodStart}`}>
                    <td>{LEVEL[t.level]}</td>
                    <td>{t.scopeCode === '*' ? '전체' : t.scopeCode}</td>
                    <td>{fmt(t.periodStart)}</td>
                    <td>{t.topic}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )
        }
      </Loaded>
    </section>
  );
}
