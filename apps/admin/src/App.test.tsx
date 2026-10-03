import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { App } from './App';

describe('App', () => {
  it('서버 정상 상태를 표시한다', async () => {
    const fetcher = (async () =>
      new Response(JSON.stringify({ ok: true, time: '2026-10-03T00:00:00Z' }))) as typeof fetch;
    render(<App fetcher={fetcher} />);
    expect(await screen.findByText(/서버 정상/)).toBeTruthy();
  });

  it('연결 실패 시 오류 상태를 표시한다', async () => {
    const fetcher = (async () => new Response('', { status: 500 })) as typeof fetch;
    render(<App fetcher={fetcher} />);
    expect(await screen.findByText('서버에 연결할 수 없어요')).toBeTruthy();
  });
});
