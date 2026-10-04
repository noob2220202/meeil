import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { ApiError } from './api';

export type Load<T> =
  { state: 'loading' } | { state: 'error'; message: string } | { state: 'ok'; data: T };

/** 불러오기 + 다시 불러오기 */
export function useLoad<T>(fn: () => Promise<T>, deps: unknown[]): [Load<T>, () => void] {
  const [s, set] = useState<Load<T>>({ state: 'loading' });
  const [tick, setTick] = useState(0);
  const run = useCallback(fn, deps);
  useEffect(() => {
    let alive = true;
    set((prev) => (prev.state === 'ok' ? prev : { state: 'loading' }));
    run()
      .then((data) => alive && set({ state: 'ok', data }))
      .catch(
        (e: unknown) =>
          alive &&
          set({
            state: 'error',
            message: e instanceof ApiError ? e.message : '불러오지 못했어요.',
          }),
      );
    return () => {
      alive = false;
    };
  }, [run, tick]);
  return [s, () => setTick((t) => t + 1)];
}

export function Loaded<T>({
  load,
  retry,
  children,
}: {
  load: Load<T>;
  retry: () => void;
  children: (data: T) => ReactNode;
}) {
  if (load.state === 'loading') return <p className="muted">불러오는 중…</p>;
  if (load.state === 'error')
    return (
      <div className="error-box" role="alert">
        {load.message} <button onClick={retry}>다시 시도</button>
      </div>
    );
  return <>{children(load.data)}</>;
}

export function Empty({ children }: { children: ReactNode }) {
  return <p className="empty">{children}</p>;
}

/** 버튼 동작: 진행 중 표시와 오류 메시지 */
export function useAction() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const run = async (f: () => Promise<unknown>) => {
    setBusy(true);
    setError(null);
    try {
      await f();
      return true;
    } catch (e) {
      setError(e instanceof ApiError ? e.message : '실패했어요.');
      return false;
    } finally {
      setBusy(false);
    }
  };
  return { busy, error, run };
}
