import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import fp from 'fastify-plugin';
import { SignJWT, jwtVerify } from 'jose';
import { AppError } from '../errors.js';
import type { AdminRole } from '../generated/prisma/client.js';

export const ADMIN_TTL_SEC = 8 * 60 * 60;
const ISSUER = 'meeil-admin';

declare module 'fastify' {
  interface FastifyInstance {
    adminTokens: AdminTokens;
    /** preHandler: 관리자 토큰 검증 → request.adminId, adminRole */
    authenticateAdmin: (req: FastifyRequest) => Promise<void>;
  }
  interface FastifyRequest {
    adminId: string;
    adminRole: AdminRole;
  }
}

/** 사용자 토큰과 키·발급자가 달라 서로 바꿔 쓸 수 없다 */
export class AdminTokens {
  private readonly key: Uint8Array;

  constructor(
    secret: string,
    private readonly now: () => Date,
  ) {
    this.key = new TextEncoder().encode(`admin:${secret}`);
  }

  async sign(adminId: string, role: AdminRole): Promise<string> {
    const iat = Math.floor(this.now().getTime() / 1000);
    return new SignJWT({ role })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(adminId)
      .setIssuer(ISSUER)
      .setIssuedAt(iat)
      .setExpirationTime(iat + ADMIN_TTL_SEC)
      .sign(this.key);
  }

  async verify(token: string): Promise<string> {
    try {
      const { payload } = await jwtVerify(token, this.key, {
        issuer: ISSUER,
        algorithms: ['HS256'],
        currentDate: this.now(),
      });
      if (!payload.sub) throw new Error('no sub');
      return payload.sub;
    } catch {
      throw new AppError(401, 'ADMIN_UNAUTHORIZED', '다시 로그인해 주세요.');
    }
  }
}

const plugin: FastifyPluginAsync<{ tokens: AdminTokens }> = async (app, { tokens }) => {
  app.decorate('adminTokens', tokens);
  app.decorateRequest('adminId', '');
  app.decorateRequest('adminRole', 'MODERATOR');
  app.decorate('authenticateAdmin', async (req: FastifyRequest) => {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      throw new AppError(401, 'ADMIN_UNAUTHORIZED', '다시 로그인해 주세요.');
    }
    const id = await tokens.verify(header.slice(7));
    const admin = await app.db.adminUser.findUnique({ where: { id } });
    if (!admin || admin.disabled) {
      throw new AppError(401, 'ADMIN_UNAUTHORIZED', '다시 로그인해 주세요.');
    }
    req.adminId = admin.id;
    req.adminRole = admin.role;
  });
};

export const adminAuthPlugin = fp(plugin, { name: 'admin-auth' });
