import type { FastifyInstance } from 'fastify';

/** JSON API 응답: 아무것도 불러오지 않는다 */
const API_CSP = "default-src 'none'; frame-ancestors 'none'; base-uri 'none'";
/** 공개 HTML(약관·계정 삭제): 인라인 스타일만 허용, 스크립트는 같은 출처 파일만 */
const HTML_CSP =
  "default-src 'none'; style-src 'unsafe-inline'; script-src 'self'; connect-src 'self'; " +
  "img-src 'self' data:; form-action 'self'; frame-ancestors 'none'; base-uri 'none'";

/** 모든 응답에 붙이는 보안 헤더(SPEC 14, docs/SECURITY.md). helmet 대신 필요한 것만 직접 단다. */
export function registerSecurityHeaders(app: FastifyInstance, opts: { hsts: boolean }): void {
  app.addHook('onSend', async (_req, reply, payload) => {
    const type = String(reply.getHeader('content-type') ?? '');
    reply.header('x-content-type-options', 'nosniff');
    reply.header('x-frame-options', 'DENY');
    reply.header('referrer-policy', 'no-referrer');
    reply.header('cross-origin-opener-policy', 'same-origin');
    reply.header('cross-origin-resource-policy', 'same-site');
    reply.header('permissions-policy', 'geolocation=(), camera=(), microphone=()');
    reply.header('content-security-policy', type.startsWith('text/html') ? HTML_CSP : API_CSP);
    if (opts.hsts) reply.header('strict-transport-security', 'max-age=31536000; includeSubDomains');
    if (!reply.hasHeader('cache-control') && type.startsWith('application/json')) {
      reply.header('cache-control', 'no-store');
    }
    reply.removeHeader('x-powered-by');
    return payload;
  });
}
