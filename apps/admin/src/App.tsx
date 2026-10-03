import { useEffect, useMemo, useState } from 'react';
import { createApi, type AdminMe, type Api } from './api';
import { Audit } from './pages/Audit';
import { Dashboard } from './pages/Dashboard';
import { Login } from './pages/Login';
import { Notices } from './pages/Notices';
import { Photos } from './pages/Photos';
import { Reports } from './pages/Reports';
import { Rolling } from './pages/Rolling';
import { UserPage, Users } from './pages/Users';
import { Loaded, useLoad } from './ui';

const TOKEN_KEY = 'meeil.admin.token';

function useHash(): string {
  const [hash, setHash] = useState(() => window.location.hash || '#/');
  useEffect(() => {
    const on = () => setHash(window.location.hash || '#/');
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);
  return hash;
}

const NAV = [
  ['#/', '대시보드'],
  ['#/reports', '신고 큐'],
  ['#/photos', '사진 검수'],
  ['#/users', '사용자'],
  ['#/rolling', '롤링페이퍼'],
  ['#/notices', '공지·푸시'],
  ['#/audit', '감사 로그'],
] as const;

/** 관리자 웹 (SPEC 9.4). 토큰은 탭을 닫으면 사라지는 sessionStorage에만 둔다. */
export function App({ fetcher }: { fetcher?: typeof fetch }) {
  const [token, setToken] = useState<string | null>(() => sessionStorage.getItem(TOKEN_KEY));
  const logout = () => {
    sessionStorage.removeItem(TOKEN_KEY);
    setToken(null);
  };
  const api = useMemo(
    () => createApi({ token, onUnauthorized: logout, ...(fetcher ? { fetcher } : {}) }),
    [token, fetcher],
  );
  if (!token) {
    return (
      <Login
        {...(fetcher ? { fetcher } : {})}
        onLogin={(t) => {
          sessionStorage.setItem(TOKEN_KEY, t);
          setToken(t);
        }}
      />
    );
  }
  return <Shell api={api} onLogout={logout} />;
}

function Shell({ api, onLogout }: { api: Api; onLogout: () => void }) {
  const hash = useHash();
  const [me, retry] = useLoad(() => api.get<AdminMe>('/admin/me'), [api]);
  const path = hash.replace(/^#/, '') || '/';
  return (
    <div className="layout">
      <nav className="side">
        <p className="brand">🐐 메에일 관리자</p>
        {NAV.map(([href, label]) => (
          <a
            key={href}
            href={href}
            aria-current={
              (href === '#/' ? path === '/' : path.startsWith(href.slice(1))) ? 'page' : undefined
            }
          >
            {label}
          </a>
        ))}
        <div className="who">
          {me.state === 'ok' && (
            <span>
              {me.data.username} · {me.data.role === 'ADMIN' ? '최고 관리자' : '운영자'}
            </span>
          )}
          <button onClick={onLogout}>로그아웃</button>
        </div>
      </nav>
      <main className="content">
        <Loaded load={me} retry={retry}>
          {(m) => <Route path={path} api={api} me={m} />}
        </Loaded>
      </main>
    </div>
  );
}

function Route({ path, api, me }: { path: string; api: Api; me: AdminMe }) {
  const user = /^\/users\/([0-9a-f-]{36})$/.exec(path);
  if (user) return <UserPage api={api} id={user[1]!} me={me} />;
  switch (path) {
    case '/reports':
      return <Reports api={api} />;
    case '/photos':
      return <Photos api={api} />;
    case '/users':
      return <Users api={api} />;
    case '/rolling':
      return <Rolling api={api} me={me} />;
    case '/notices':
      return <Notices api={api} me={me} />;
    case '/audit':
      return me.role === 'ADMIN' ? <Audit api={api} /> : <p>최고 관리자만 볼 수 있어요.</p>;
    default:
      return <Dashboard api={api} />;
  }
}
