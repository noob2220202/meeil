import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { AppError, parse } from '../errors.js';
import { markdownToHtml, page } from '../legal/markdown.js';

const DOCS = { privacy: '개인정보처리방침', terms: '이용약관' } as const;
const Doc = z.object({ doc: z.enum(['privacy', 'terms']) });
const DeletionBody = z.object({
  nickname: z.string().trim().min(1, '닉네임을 적어 주세요.').max(40),
  contact: z
    .string()
    .trim()
    .max(120)
    .refine((s) => s === '' || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s), '이메일 형식을 확인해 주세요.')
    .optional(),
  message: z.string().trim().max(500).optional(),
});

/**
 * 공개 웹 페이지: 개인정보처리방침·이용약관(스토어 등록 URL), 계정 삭제 안내·요청(SPEC 8, 14).
 * 앱을 지웠거나 쓸 수 없는 사람도 브라우저에서 삭제를 요청할 수 있다.
 */
export const webRoutes: FastifyPluginAsync<{ legalDir: string; rateLimit: boolean }> = async (
  app,
  { legalDir, rateLimit },
) => {
  app.get('/legal/:doc', async (req, reply) => {
    const { doc } = parse(Doc, req.params);
    let md: string;
    try {
      md = await readFile(join(legalDir, `${doc}.md`), 'utf8');
    } catch {
      throw new AppError(404, 'NOT_FOUND', '문서를 찾을 수 없어요.');
    }
    return reply.type('text/html; charset=utf-8').send(page(DOCS[doc], markdownToHtml(md)));
  });

  app.get('/account/delete', async (_req, reply) =>
    reply.type('text/html; charset=utf-8').send(
      page(
        '계정 삭제',
        `<h1>🐐 메에일 계정 삭제</h1>
<div class="card"><h2>앱에서 바로 지우기(가장 빨라요)</h2>
<ol><li>메에일 앱 → <strong>내 정보</strong> → <strong>설정 · 차단 목록</strong></li>
<li>맨 아래 <strong>탈퇴하기</strong> → 닉네임을 한 번 더 적고 확인</li></ol>
<p class="muted">즉시 지워져요. 다시 가입하면 새 계정이 돼요.</p></div>
<div class="card"><h2>앱을 쓸 수 없다면 요청하기</h2>
<p>닉네임을 적어 보내 주시면 운영자가 확인 후 7일 안에 지워요. 결과를 받고 싶으면 이메일을 남겨 주세요(처리 후 바로 지워요).</p>
<form id="f"><label for="n">닉네임</label><input id="n" name="nickname" maxlength="40" required>
<label for="c">이메일(선택)</label><input id="c" name="contact" type="email" maxlength="120">
<label for="m">남길 말(선택)</label><textarea id="m" name="message" maxlength="500" rows="3"></textarea>
<button>삭제 요청 보내기</button></form><p id="r" role="status"></p></div>
<h2>지워지는 것</h2>
<ul><li>닉네임, 생년월일, 로그인 연결 정보, 알림 토큰, 방문한 시 기록, 포인트·출석·업적</li>
<li>내가 보낸 편지와 사진, 두루마리 글</li>
<li>내가 받은 편지(내 편지함에서)</li></ul>
<h2>잠시 남는 것</h2>
<ul><li>신고된 편지·글은 확인을 위해 탈퇴 후 30일 보관한 뒤 지워요.</li></ul>
<p class="muted"><a href="/legal/privacy">개인정보처리방침</a> · <a href="/legal/terms">이용약관</a></p>
<script>
document.getElementById('f').addEventListener('submit', async (e) => {
  e.preventDefault();
  const r = document.getElementById('r');
  const body = Object.fromEntries(new FormData(e.target));
  try {
    const res = await fetch('/account/delete-request', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
    const j = await res.json();
    r.textContent = res.ok ? '요청을 받았어요. 7일 안에 처리할게요.' : (j.error && j.error.message) || '보내지 못했어요.';
    if (res.ok) e.target.reset();
  } catch { r.textContent = '보내지 못했어요. 잠시 뒤 다시 해 주세요.'; }
});
</script>`,
      ),
    ),
  );

  app.post(
    '/account/delete-request',
    rateLimit ? { config: { rateLimit: { max: 5, timeWindow: '1 hour' } } } : {},
    async (req, reply) => {
      const b = parse(DeletionBody, req.body);
      await app.db.deletionRequest.create({
        data: {
          nickname: b.nickname,
          contact: b.contact || null,
          message: b.message || null,
        },
      });
      return reply.status(201).send({ ok: true });
    },
  );
};
