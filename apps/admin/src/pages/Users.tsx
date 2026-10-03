import { useState, type FormEvent } from 'react';
import { fmt, type AdminMe, type Api, type UserDetail, type UserRow } from '../api';
import { Empty, Loaded, useAction, useLoad } from '../ui';

const STATUS = {
  ACTIVE: '정상',
  SUSPENDED: '정지',
  BANNED: '영구 정지',
  DELETED: '탈퇴',
} as Record<string, string>;
const SANCTION = {
  WARNING: '경고',
  SUSPEND_7D: '7일 정지',
  BAN: '영구 정지',
  LIFT: '해제',
} as Record<string, string>;

export function Users({ api }: { api: Api }) {
  const [q, setQ] = useState('');
  const [query, setQuery] = useState('');
  const [load, retry] = useLoad(
    () => api.get<{ users: UserRow[] }>(`/admin/users?q=${encodeURIComponent(query)}`),
    [api, query],
  );
  return (
    <section>
      <h2>사용자</h2>
      <form
        className="search"
        onSubmit={(e) => {
          e.preventDefault();
          setQuery(q.trim());
        }}
      >
        <input
          placeholder="닉네임 또는 사용자 ID"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          aria-label="사용자 검색"
        />
        <button>검색</button>
      </form>
      <Loaded load={load} retry={retry}>
        {({ users }) =>
          users.length === 0 ? (
            <Empty>찾는 사용자가 없어요.</Empty>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>닉네임</th>
                  <th>상태</th>
                  <th>받은 신고</th>
                  <th>보낸 편지</th>
                  <th>최근 접속</th>
                </tr>
              </thead>
              <tbody>
                {users.map((u) => (
                  <tr key={u.id}>
                    <td>
                      <a href={`#/users/${u.id}`}>{u.nickname ?? '(가입 중)'}</a>
                      {u.isOfficial && <span className="badge">공식</span>}
                    </td>
                    <td>{STATUS[u.status] ?? u.status}</td>
                    <td className={u.reportsReceived > 0 ? 'warn-text' : ''}>
                      {u.reportsReceived}
                    </td>
                    <td>{u.lettersSent}</td>
                    <td>{fmt(u.lastActiveAt)}</td>
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

export function UserPage({ api, id, me }: { api: Api; id: string; me: AdminMe }) {
  const [load, retry] = useLoad(() => api.get<UserDetail>(`/admin/users/${id}`), [api, id]);
  const [type, setType] = useState('WARNING');
  const [reason, setReason] = useState('');
  const { busy, error, run } = useAction();
  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!confirm(`${SANCTION[type]} 처리할까요?`)) return;
    if (await run(() => api.post(`/admin/users/${id}/sanctions`, { type, reason }))) {
      setReason('');
      retry();
    }
  };
  return (
    <section>
      <a href="#/users">← 사용자 목록</a>
      <Loaded load={load} retry={retry}>
        {(u) => (
          <>
            <h2>
              {u.nickname} <span className="badge">{STATUS[u.status] ?? u.status}</span>
            </h2>
            <dl className="facts">
              <dt>가입</dt>
              <dd>{fmt(u.createdAt)}</dd>
              <dt>최근 접속</dt>
              <dd>{fmt(u.lastActiveAt)}</dd>
              {u.suspendedUntil && (
                <>
                  <dt>정지 해제</dt>
                  <dd>{fmt(u.suspendedUntil)}</dd>
                </>
              )}
              <dt>포인트</dt>
              <dd>{u.pointsBalance}P</dd>
              <dt>나이 확인</dt>
              <dd>{u.ageVerified ? '만 14세 이상 확인' : '미입력'}</dd>
              <dt>기록</dt>
              <dd>
                보낸 편지 {u.counts.sentLetters} · 먹힌 편지 {u.counts.eatenLetters} · 받은 신고{' '}
                {u.counts.reportsReceived} · 두루마리 {u.counts.rollingEntries}
              </dd>
            </dl>
            <h3>제재</h3>
            <form className="card sanction" onSubmit={submit}>
              <select value={type} onChange={(e) => setType(e.target.value)} aria-label="제재 종류">
                <option value="WARNING">경고</option>
                <option value="SUSPEND_7D">7일 정지</option>
                <option value="BAN" disabled={me.role !== 'ADMIN'}>
                  영구 정지{me.role !== 'ADMIN' ? ' (최고 관리자)' : ''}
                </option>
                <option value="LIFT" disabled={me.role !== 'ADMIN'}>
                  해제{me.role !== 'ADMIN' ? ' (최고 관리자)' : ''}
                </option>
              </select>
              <input
                placeholder="사유(사용자에게 알림으로 가요)"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                required
                aria-label="제재 사유"
              />
              <button className="danger" disabled={busy}>
                적용
              </button>
              {error && <p className="error-box">{error}</p>}
            </form>
            {u.sanctions.length === 0 ? (
              <Empty>제재 기록이 없어요.</Empty>
            ) : (
              <ul className="list compact">
                {u.sanctions.map((s) => (
                  <li key={s.id}>
                    <span className="badge">{SANCTION[s.type] ?? s.type}</span> {s.reason}{' '}
                    <span className="muted">
                      · {s.admin} · {fmt(s.createdAt)}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </>
        )}
      </Loaded>
    </section>
  );
}
