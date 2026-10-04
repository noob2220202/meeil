import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { App } from './App';

type Handler = (body: unknown) => { status?: number; json: unknown };

/** 경로별 가짜 서버. 호출 기록을 남긴다. */
function fakeServer(routes: Record<string, Handler>) {
  const calls: { method: string; path: string; body: unknown; auth: string | null }[] = [];
  const fetcher = (async (url: string, init?: RequestInit) => {
    const path = url.replace(/^\/api/, '');
    const method = init?.method ?? 'GET';
    const body = init?.body ? JSON.parse(init.body as string) : undefined;
    const headers = (init?.headers ?? {}) as Record<string, string>;
    calls.push({ method, path, body, auth: headers.authorization ?? null });
    const h = routes[`${method} ${path}`] ?? routes[`${method} ${path.split('?')[0]}`];
    if (!h)
      return new Response(JSON.stringify({ error: { code: 'NOT_FOUND', message: '없음' } }), {
        status: 404,
      });
    const r = h(body);
    return new Response(JSON.stringify(r.json), { status: r.status ?? 200 });
  }) as unknown as typeof fetch;
  return { fetcher, calls };
}

const me = { id: 'a1', username: 'boss', role: 'ADMIN' };
const dashboard = {
  users: 120,
  newToday: 4,
  activeToday: 33,
  lettersToday: 57,
  inTransit: 80,
  openReports: 2,
  unreviewed: 5,
  eatenToday: 1,
  days: Array.from({ length: 7 }, (_, i) => ({ date: `2026-09-${27 + i}`, letters: i * 3 })),
};

beforeEach(() => {
  sessionStorage.clear();
  window.location.hash = '#/';
});
afterEach(cleanup);

describe('관리자 웹', () => {
  it('로그인: 틀리면 안내, 맞으면 대시보드', async () => {
    let ok = false;
    const { fetcher, calls } = fakeServer({
      'POST /admin/login': () =>
        ok
          ? { json: { token: 'T', admin: me } }
          : {
              status: 401,
              json: {
                error: {
                  code: 'ADMIN_LOGIN_FAILED',
                  message: '아이디, 비밀번호, 인증 코드를 확인해 주세요.',
                },
              },
            },
      'GET /admin/me': () => ({ json: me }),
      'GET /admin/dashboard': () => ({ json: dashboard }),
    });
    render(<App fetcher={fetcher} />);
    fireEvent.change(screen.getByLabelText('아이디'), { target: { value: 'boss' } });
    fireEvent.change(screen.getByLabelText('비밀번호'), { target: { value: 'pw' } });
    fireEvent.change(screen.getByLabelText('인증 앱 코드(6자리)'), {
      target: { value: '12a3456' },
    });
    expect((screen.getByLabelText('인증 앱 코드(6자리)') as HTMLInputElement).value).toBe('123456');
    fireEvent.click(screen.getByRole('button', { name: '로그인' }));
    expect(await screen.findByRole('alert')).toHaveProperty(
      'textContent',
      '아이디, 비밀번호, 인증 코드를 확인해 주세요.',
    );

    ok = true;
    fireEvent.click(screen.getByRole('button', { name: '로그인' }));
    expect(await screen.findByText('처리 대기 신고')).toBeTruthy();
    expect(screen.getByText('120')).toBeTruthy();
    expect(sessionStorage.getItem('meeil.admin.token')).toBe('T');
    expect(calls.find((c) => c.path === '/admin/dashboard')?.auth).toBe('Bearer T');
    expect(calls[0]?.body).toEqual({ username: 'boss', password: 'pw', totp: '123456' });
  });

  it('토큰이 만료되면(401) 로그인 화면으로', async () => {
    sessionStorage.setItem('meeil.admin.token', 'OLD');
    const { fetcher } = fakeServer({
      'GET /admin/me': () => ({
        status: 401,
        json: { error: { code: 'ADMIN_UNAUTHORIZED', message: '다시 로그인해 주세요.' } },
      }),
    });
    render(<App fetcher={fetcher} />);
    expect(await screen.findByRole('button', { name: '로그인' })).toBeTruthy();
    expect(sessionStorage.getItem('meeil.admin.token')).toBeNull();
  });

  it('신고 큐: 편지를 먹으면 목록이 새로 고쳐진다', async () => {
    sessionStorage.setItem('meeil.admin.token', 'T');
    window.location.hash = '#/reports';
    let eaten = false;
    const report = {
      id: 'r1',
      targetType: 'LETTER',
      reason: 'ABUSE',
      reasonLabel: '욕설·괴롭힘',
      detail: '나쁜 말',
      status: 'OPEN',
      createdAt: '2026-10-03T03:00:00Z',
      resolvedAt: null,
      resolvedBy: null,
      reporter: { id: 'u2', nickname: '신고자' },
      targetUser: {
        id: '0190f0f0-0000-7000-8000-000000000001',
        nickname: '나쁜이',
        status: 'ACTIVE',
      },
      letter: {
        id: 'l1',
        status: 'IN_TRANSIT',
        body: '못된 편지',
        etaAt: '2026-10-04T03:00:00Z',
        photoUrl: null,
      },
      rollingEntry: null,
      sameTargetOpen: 2,
    };
    const { fetcher, calls } = fakeServer({
      'GET /admin/me': () => ({ json: me }),
      'GET /admin/reports': () => ({ json: { reports: eaten ? [] : [report] } }),
      'POST /admin/letters/l1/eat': () => {
        eaten = true;
        return { json: { eaten: true } };
      },
    });
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    render(<App fetcher={fetcher} />);
    expect(await screen.findByText('못된 편지')).toBeTruthy();
    expect(screen.getByText('같은 대상 신고 2건')).toBeTruthy();
    expect(screen.getByText(/그 전에 먹으면 받는 사람에게 가지 않아요/)).toBeTruthy();
    await act(async () => fireEvent.click(screen.getByRole('button', { name: /먹기/ })));
    expect(await screen.findByText('처리할 신고가 없어요. 🐐')).toBeTruthy();
    expect(calls.find((c) => c.path === '/admin/letters/l1/eat')?.body).toEqual({
      reason: '욕설·괴롭힘',
    });
  });

  it('사진 검수: 확인 완료하면 미확인 목록에서 빠진다', async () => {
    sessionStorage.setItem('meeil.admin.token', 'T');
    window.location.hash = '#/photos';
    let reviewed = false;
    const photo = {
      id: 'p1',
      url: 'http://media.test/p1',
      width: 400,
      height: 300,
      createdAt: '2026-10-03T03:00:00Z',
      reviewedAt: null,
      reviewedBy: null,
      letter: {
        id: 'l1',
        mode: 'DIRECT',
        status: 'IN_TRANSIT',
        body: '바다 사진!',
        etaAt: null,
        deliveredAt: null,
        sender: { id: 'u1', nickname: '찍사' },
        recipient: { id: 'u2', nickname: '친구' },
      },
    };
    const { fetcher } = fakeServer({
      'GET /admin/me': () => ({ json: me }),
      'GET /admin/photos': () => ({ json: { photos: reviewed ? [] : [photo] } }),
      'POST /admin/photos/p1/review': () => {
        reviewed = true;
        return { json: { reviewed: true } };
      },
    });
    render(<App fetcher={fetcher} />);
    expect(await screen.findByAltText('찍사의 편지 사진')).toBeTruthy();
    await act(async () => fireEvent.click(screen.getByRole('button', { name: '✓ 확인 완료' })));
    await waitFor(() => expect(screen.getByText('확인할 사진이 없어요. 🐐')).toBeTruthy());
  });

  it('사용자 상세: 운영자는 영구 정지를 고를 수 없다', async () => {
    sessionStorage.setItem('meeil.admin.token', 'T');
    const uid = '0190f0f0-0000-7000-8000-000000000001';
    window.location.hash = `#/users/${uid}`;
    const { fetcher, calls } = fakeServer({
      'GET /admin/me': () => ({ json: { ...me, role: 'MODERATOR' } }),
      [`GET /admin/users/${uid}`]: () => ({
        json: {
          id: uid,
          nickname: '말썽꾼',
          status: 'ACTIVE',
          suspendedUntil: null,
          createdAt: '2026-10-01T00:00:00Z',
          lastActiveAt: '2026-10-03T00:00:00Z',
          pointsBalance: 12,
          lastRegionCode: '11110',
          ageVerified: true,
          counts: {
            sentLetters: 3,
            eatenLetters: 1,
            reportsReceived: 2,
            rollingEntries: 0,
            receivedLetters: 1,
          },
          sanctions: [],
        },
      }),
      [`POST /admin/users/${uid}/sanctions`]: () => ({ json: { status: 'SUSPENDED' } }),
    });
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    render(<App fetcher={fetcher} />);
    expect(await screen.findByText('말썽꾼')).toBeTruthy();
    expect((screen.getByRole('option', { name: /영구 정지/ }) as HTMLOptionElement).disabled).toBe(
      true,
    );
    fireEvent.change(screen.getByLabelText('제재 종류'), { target: { value: 'SUSPEND_7D' } });
    fireEvent.change(screen.getByLabelText('제재 사유'), { target: { value: '반복 욕설' } });
    await act(async () => fireEvent.click(screen.getByRole('button', { name: '적용' })));
    expect(calls.find((c) => c.method === 'POST')?.body).toEqual({
      type: 'SUSPEND_7D',
      reason: '반복 욕설',
    });
  });
});
