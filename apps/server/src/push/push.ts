// 푸시 (SPEC 11.2: FCM HTTP v1). 서비스 계정이 없으면 기록만 하는 구현을 쓴다.
import { SignJWT, importPKCS8 } from 'jose';
import type { Db } from '../db.js';

export interface PushMessage {
  title: string;
  body: string;
  /** 앱이 눌렀을 때 이동할 곳 등 */
  data?: Record<string, string>;
}

export interface Pusher {
  /** 성공적으로 보낸 기기 수 */
  sendToUser(userId: string, msg: PushMessage): Promise<number>;
}

/** 개발·테스트: 보낸 메시지를 메모리에 쌓는다 */
export class MemoryPusher implements Pusher {
  readonly sent: { userId: string; msg: PushMessage }[] = [];

  async sendToUser(userId: string, msg: PushMessage): Promise<number> {
    this.sent.push({ userId, msg });
    return 1;
  }
}

interface FcmConfig {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

export class FcmPusher implements Pusher {
  private token: { value: string; exp: number } | null = null;

  constructor(
    private readonly db: Db,
    private readonly cfg: FcmConfig,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  private async accessToken(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (this.token && this.token.exp - 60 > now) return this.token.value;
    const key = await importPKCS8(this.cfg.privateKey.replace(/\\n/g, '\n'), 'RS256');
    const assertion = await new SignJWT({
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
    })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
      .setIssuer(this.cfg.clientEmail)
      .setAudience('https://oauth2.googleapis.com/token')
      .setIssuedAt(now)
      .setExpirationTime(now + 3600)
      .sign(key);
    const res = await this.fetchImpl('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }),
    });
    if (!res.ok) throw new Error(`FCM 토큰 발급 실패 ${res.status}`);
    const body = (await res.json()) as { access_token: string; expires_in: number };
    this.token = { value: body.access_token, exp: now + body.expires_in };
    return body.access_token;
  }

  async sendToUser(userId: string, msg: PushMessage): Promise<number> {
    const tokens = await this.db.fcmToken.findMany({ where: { userId }, select: { token: true } });
    if (tokens.length === 0) return 0;
    const bearer = await this.accessToken();
    let ok = 0;
    for (const { token } of tokens) {
      const res = await this.fetchImpl(
        `https://fcm.googleapis.com/v1/projects/${this.cfg.projectId}/messages:send`,
        {
          method: 'POST',
          headers: { authorization: `Bearer ${bearer}`, 'content-type': 'application/json' },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: msg.title, body: msg.body },
              data: msg.data ?? {},
              android: { priority: 'high', notification: { channel_id: 'letters' } },
            },
          }),
        },
      );
      if (res.ok) {
        ok++;
      } else if (res.status === 404 || res.status === 400) {
        // UNREGISTERED·INVALID_ARGUMENT: 앱이 지워졌거나 토큰이 바뀜 → 정리
        await this.db.fcmToken.deleteMany({ where: { token } });
      }
    }
    return ok;
  }
}

/** FCM 키가 없을 때(개발 서버 등): 로그로만 남긴다 */
export class LogPusher implements Pusher {
  constructor(private readonly log: (msg: string) => void) {}

  async sendToUser(userId: string, msg: PushMessage): Promise<number> {
    this.log(`[push] ${userId}: ${msg.title} — ${msg.body}`);
    return 0;
  }
}
