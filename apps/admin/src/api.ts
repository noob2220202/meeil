// 관리자 API 클라이언트. 개발은 Vite 프록시, 운영은 Caddy가 /api/*를 접두사를 떼고 서버로 넘긴다
// (정적 /admin/과 API /admin/*가 겹치지 않게). docs/ADMIN.md 참고.
export const API_BASE: string = (import.meta.env.VITE_API_BASE as string | undefined) ?? '/api';

export class ApiError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

export interface Api {
  get<T>(path: string): Promise<T>;
  post<T>(path: string, body?: unknown): Promise<T>;
}

export function createApi(opts: {
  token: string | null;
  fetcher?: typeof fetch;
  base?: string;
  onUnauthorized?: () => void;
}): Api {
  const fetcher = opts.fetcher ?? fetch;
  const base = opts.base ?? API_BASE;
  async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
    let res: Response;
    try {
      res = await fetcher(`${base}${path}`, {
        method,
        headers: {
          ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
          ...(opts.token ? { authorization: `Bearer ${opts.token}` } : {}),
        },
        ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
      });
    } catch {
      throw new ApiError('NETWORK', '서버에 연결할 수 없어요.', 0);
    }
    const json = (await res.json().catch(() => ({}))) as {
      error?: { code: string; message: string };
    };
    if (!res.ok) {
      if (res.status === 401 && opts.token) opts.onUnauthorized?.();
      throw new ApiError(
        json.error?.code ?? 'ERROR',
        json.error?.message ?? `요청 실패 (${res.status})`,
        res.status,
      );
    }
    return json as T;
  }
  return {
    get: (p) => request('GET', p),
    post: (p, b) => request('POST', p, b ?? {}),
  };
}

// ───────── 응답 타입 ─────────

export interface AdminMe {
  id: string;
  username: string;
  role: 'ADMIN' | 'MODERATOR';
}

export interface Dashboard {
  users: number;
  newToday: number;
  activeToday: number;
  lettersToday: number;
  inTransit: number;
  openReports: number;
  unreviewed: number;
  eatenToday: number;
  days: { date: string; letters: number }[];
}

export interface PersonRef {
  id: string;
  nickname: string | null;
}

export interface ReportItem {
  id: string;
  targetType: 'LETTER' | 'ROLLING_ENTRY' | 'USER';
  reason: string;
  reasonLabel: string;
  detail: string | null;
  status: 'OPEN' | 'RESOLVED' | 'DISMISSED';
  createdAt: string;
  resolvedAt: string | null;
  resolvedBy: string | null;
  reporter: PersonRef;
  targetUser: (PersonRef & { status: string }) | null;
  letter: {
    id: string;
    status: string;
    body: string;
    etaAt: string | null;
    photoUrl: string | null;
  } | null;
  rollingEntry: { id: string; status: string; body: string; paperId: string } | null;
  sameTargetOpen: number;
}

export interface PhotoItem {
  id: string;
  url: string;
  width: number;
  height: number;
  createdAt: string;
  reviewedAt: string | null;
  reviewedBy: string | null;
  letter: {
    id: string;
    mode: string;
    status: string;
    body: string;
    etaAt: string | null;
    deliveredAt: string | null;
    sender: PersonRef;
    recipient: PersonRef;
  } | null;
}

export interface UserRow {
  id: string;
  nickname: string | null;
  status: string;
  suspendedUntil: string | null;
  createdAt: string;
  lastActiveAt: string;
  isOfficial: boolean;
  reportsReceived: number;
  lettersSent: number;
}

export interface UserDetail {
  id: string;
  nickname: string | null;
  status: string;
  suspendedUntil: string | null;
  createdAt: string;
  lastActiveAt: string;
  pointsBalance: number;
  lastRegionCode: string | null;
  ageVerified: boolean;
  counts: Record<string, number>;
  sanctions: { id: string; type: string; reason: string; admin: string; createdAt: string }[];
}

export interface NoticeItem {
  id: string;
  title: string;
  body: string;
  pinned: boolean;
  publishedAt: string | null;
  createdBy: string;
  createdAt: string;
}

export interface TopicItem {
  level: 'NATION' | 'PROVINCE' | 'CITY';
  scopeCode: string;
  periodStart: string;
  topic: string;
}

export interface AuditItem {
  id: string;
  admin: string;
  action: string;
  targetType: string | null;
  targetId: string | null;
  detail: unknown;
  createdAt: string;
}

export const fmt = (iso: string | null | undefined) =>
  iso
    ? new Date(iso).toLocaleString('ko-KR', {
        timeZone: 'Asia/Seoul',
        month: 'numeric',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '—';

/** 편지·글·사용자 상태 → 한국어 */
export const statusLabel = (s: string): string =>
  ({
    HANDED: '맡김',
    IN_TRANSIT: '배달 중',
    DELIVERED: '도착',
    READ: '읽음',
    EATEN: '먹힘',
    VISIBLE: '게시 중',
    ACTIVE: '정상',
    SUSPENDED: '정지',
    BANNED: '영구 정지',
    DELETED: '탈퇴',
  })[s] ?? s;
