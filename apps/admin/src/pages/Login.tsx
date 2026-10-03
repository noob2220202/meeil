import { useState, type FormEvent } from 'react';
import { createApi, type AdminMe } from '../api';
import { useAction } from '../ui';

export function Login({
  fetcher,
  onLogin,
}: {
  fetcher?: typeof fetch;
  onLogin: (token: string, me: AdminMe) => void;
}) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [totp, setTotp] = useState('');
  const { busy, error, run } = useAction();

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    await run(async () => {
      const r = await createApi({ token: null, ...(fetcher ? { fetcher } : {}) }).post<{
        token: string;
        admin: AdminMe;
      }>('/admin/login', { username, password, totp });
      onLogin(r.token, r.admin);
    });
  };

  return (
    <main className="login">
      <form onSubmit={submit} className="card">
        <h1>🐐 메에일 관리자</h1>
        <label>
          아이디
          <input
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            autoComplete="username"
            required
          />
        </label>
        <label>
          비밀번호
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
            required
          />
        </label>
        <label>
          인증 앱 코드(6자리)
          <input
            value={totp}
            onChange={(e) => setTotp(e.target.value.replace(/\D/g, '').slice(0, 6))}
            inputMode="numeric"
            autoComplete="one-time-code"
            required
          />
        </label>
        {error && (
          <p className="error-box" role="alert">
            {error}
          </p>
        )}
        <button className="primary" disabled={busy}>
          {busy ? '확인 중…' : '로그인'}
        </button>
      </form>
    </main>
  );
}
