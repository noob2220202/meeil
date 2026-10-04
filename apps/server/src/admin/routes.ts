// 관리자 API (SPEC 9.4). 모든 변경은 감사 로그에 남긴다.
import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Db } from '../db.js';
import { AppError, parse } from '../errors.js';
import type { Prisma, RollingLevel } from '../generated/prisma/client.js';
import { kstDayRange } from '../letters/rules.js';
import type { EatService } from '../moderation/eat.js';
import { REPORT_REASONS } from '../moderation/reports.js';
import type { Pusher } from '../push/push.js';
import { periodOf } from '../rolling/service.js';
import type { Storage } from '../storage/storage.js';
import { unseal, verifyPassword, verifyTotp } from './crypto.js';
import type { AccountService } from '../account/delete.js';
import { nicknameKey } from '../domain/nickname.js';

const DAY = 24 * 60 * 60 * 1000;

export interface AdminDeps {
  eat: EatService;
  storage: Storage;
  pusher: Pusher;
  now: () => Date;
  /** TOTP 시크릿 암호화 키 */
  secretKey: string;
  /** 요청 제한(테스트에서 끈다) */
  rateLimit: boolean;
  account: AccountService;
}

const Login = z.object({
  username: z.string().min(1).max(40),
  password: z.string().min(1).max(200),
  totp: z.string().regex(/^\d{6}$/, '인증 코드 6자리를 입력해 주세요.'),
});
const Id = z.object({ id: z.string().uuid() });
const Cursor = z.object({ cursor: z.string().uuid().optional() });
const Reason = z.object({ reason: z.string().trim().min(1).max(200).default('부적절한 내용') });
const ReportsQuery = Cursor.extend({
  status: z.enum(['OPEN', 'RESOLVED', 'DISMISSED']).default('OPEN'),
});
const PhotosQuery = Cursor.extend({ filter: z.enum(['unreviewed', 'all']).default('unreviewed') });
const UsersQuery = z.object({ q: z.string().trim().max(40).default('') });
const SanctionBody = z.object({
  type: z.enum(['WARNING', 'SUSPEND_7D', 'BAN', 'LIFT']),
  reason: z.string().trim().min(1).max(300),
});
const NoticeBody = z.object({
  title: z.string().trim().min(1).max(60),
  body: z.string().trim().min(1).max(2000),
  pinned: z.boolean().default(false),
  publish: z.boolean().default(true),
  push: z.boolean().default(false),
});
const TopicBody = z.object({
  level: z.enum(['NATION', 'PROVINCE', 'CITY']),
  /** 'KR', 도 코드, 시 코드, 또는 '*'(그 레벨 전체) */
  scopeCode: z.string().regex(/^(KR|\*|\d{2}|\d{5})$/),
  when: z.enum(['current', 'next']).default('current'),
  topic: z.string().trim().min(1).max(60),
});
const OfficialEntry = z.object({
  level: z.enum(['NATION', 'PROVINCE', 'CITY']),
  scopeCode: z.string().regex(/^(KR|\d{2}|\d{5})$/),
  body: z.string().trim().min(1).max(200),
});

async function audit(
  db: Db,
  req: FastifyRequest,
  action: string,
  targetType?: string,
  targetId?: string,
  detail?: Prisma.InputJsonValue,
) {
  await db.auditLog.create({
    data: {
      adminId: req.adminId,
      action,
      targetType: targetType ?? null,
      targetId: targetId ?? null,
      ...(detail !== undefined ? { detail } : {}),
    },
  });
}

function requireAdmin(req: FastifyRequest) {
  if (req.adminRole !== 'ADMIN') {
    throw new AppError(403, 'ADMIN_ONLY', '최고 관리자만 할 수 있어요.');
  }
}

/** 운영 공식 계정(염소 우체국). 환영 글을 남길 때 쓴다. */
export async function officialUser(db: Db) {
  const found = await db.user.findFirst({ where: { isOfficial: true } });
  if (found) return found;
  const at = new Date();
  return db.user.create({
    data: {
      nickname: '메에일 우체국',
      nicknameKey: '메에일 우체국',
      isOfficial: true,
      termsAgreedAt: at,
      privacyAgreedAt: at,
      birthDate: new Date('2000-01-01T00:00:00Z'),
      randomReceive: false,
      notifyEnabled: false,
    },
  });
}

export const adminRoutes: FastifyPluginAsync<AdminDeps> = async (app, deps) => {
  const { db } = app;
  const { eat, storage, pusher, now } = deps;

  app.post(
    '/admin/login',
    deps.rateLimit ? { config: { rateLimit: { max: 10, timeWindow: '5 minutes' } } } : {},
    async (req) => {
      const { username, password, totp } = parse(Login, req.body);
      const fail = () =>
        new AppError(401, 'ADMIN_LOGIN_FAILED', '아이디, 비밀번호, 인증 코드를 확인해 주세요.');
      const admin = await db.adminUser.findUnique({ where: { username } });
      if (!admin || admin.disabled || !admin.totpSecret) throw fail();
      if (!(await verifyPassword(password, admin.passwordHash))) throw fail();
      if (!verifyTotp(unseal(admin.totpSecret, deps.secretKey), totp, now().getTime()))
        throw fail();
      await db.adminUser.update({ where: { id: admin.id }, data: { lastLoginAt: now() } });
      await db.auditLog.create({ data: { adminId: admin.id, action: 'LOGIN' } });
      return {
        token: await app.adminTokens.sign(admin.id, admin.role),
        admin: { id: admin.id, username: admin.username, role: admin.role },
      };
    },
  );

  await app.register(async (r) => {
    r.addHook('preHandler', app.authenticateAdmin);

    r.get('/admin/me', async (req) => {
      const a = await db.adminUser.findUniqueOrThrow({ where: { id: req.adminId } });
      return { id: a.id, username: a.username, role: a.role };
    });

    r.get('/admin/dashboard', async () => {
      const { start } = kstDayRange(now());
      const signedUp = { nickname: { not: null }, isOfficial: false };
      const [
        users,
        newToday,
        activeToday,
        lettersToday,
        inTransit,
        openReports,
        unreviewed,
        eatenToday,
      ] = await Promise.all([
        db.user.count({ where: signedUp }),
        db.user.count({ where: { ...signedUp, createdAt: { gte: start } } }),
        db.user.count({ where: { ...signedUp, lastActiveAt: { gte: start } } }),
        db.letter.count({ where: { handedAt: { gte: start } } }),
        db.letter.count({ where: { status: 'IN_TRANSIT' } }),
        db.report.count({ where: { status: 'OPEN' } }),
        db.letterPhoto.count({ where: { letterId: { not: null }, reviewedAt: null } }),
        db.letter.count({ where: { eatenAt: { gte: start } } }),
      ]);
      // 최근 7일 일별 편지 수(KST)
      const days: { date: string; letters: number }[] = [];
      for (let i = 6; i >= 0; i--) {
        const s = new Date(start.getTime() - i * DAY);
        const n = await db.letter.count({
          where: { handedAt: { gte: s, lt: new Date(s.getTime() + DAY) } },
        });
        days.push({
          date: new Date(s.getTime() + 9 * 3600_000).toISOString().slice(0, 10),
          letters: n,
        });
      }
      return {
        users,
        newToday,
        activeToday,
        lettersToday,
        inTransit,
        openReports,
        unreviewed,
        eatenToday,
        days,
      };
    });

    // ───────── 신고 큐 ─────────

    r.get('/admin/reports', async (req) => {
      const { status, cursor } = parse(ReportsQuery, req.query);
      const rows = await db.report.findMany({
        where: { status },
        orderBy: [{ createdAt: status === 'OPEN' ? 'asc' : 'desc' }, { id: 'asc' }],
        take: 31,
        ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
        include: {
          reporter: { select: { id: true, nickname: true } },
          targetUser: { select: { id: true, nickname: true, status: true } },
          letter: { include: { photo: true } },
          rollingEntry: true,
          resolvedBy: { select: { username: true } },
        },
      });
      const page = rows.slice(0, 30);
      return {
        reports: await Promise.all(
          page.map(async (x) => ({
            id: x.id,
            targetType: x.targetType,
            reason: x.reason,
            reasonLabel: REPORT_REASONS[x.reason as keyof typeof REPORT_REASONS] ?? x.reason,
            detail: x.detail,
            status: x.status,
            createdAt: x.createdAt.toISOString(),
            resolvedAt: x.resolvedAt?.toISOString() ?? null,
            resolvedBy: x.resolvedBy?.username ?? null,
            reporter: x.reporter,
            targetUser: x.targetUser,
            letter: x.letter
              ? {
                  id: x.letter.id,
                  status: x.letter.status,
                  body: x.letter.body,
                  etaAt: x.letter.etaAt?.toISOString() ?? null,
                  photoUrl: x.letter.photo
                    ? await storage.signedUrl(x.letter.photo.storageKey)
                    : null,
                }
              : null,
            rollingEntry: x.rollingEntry
              ? {
                  id: x.rollingEntry.id,
                  status: x.rollingEntry.status,
                  body: x.rollingEntry.body,
                  paperId: x.rollingEntry.paperId,
                }
              : null,
            sameTargetOpen: await db.report.count({
              where: {
                status: 'OPEN',
                targetType: x.targetType,
                ...(x.letterId
                  ? { letterId: x.letterId }
                  : x.rollingEntryId
                    ? { rollingEntryId: x.rollingEntryId }
                    : { targetUserId: x.targetUserId }),
              },
            }),
          })),
        ),
        nextCursor: rows.length > 30 ? page[page.length - 1]!.id : null,
      };
    });

    r.post('/admin/reports/:id/dismiss', async (req) => {
      const { id } = parse(Id, req.params);
      const x = await db.report.findUnique({ where: { id } });
      if (!x) throw new AppError(404, 'REPORT_NOT_FOUND', '신고를 찾을 수 없어요.');
      await db.report.update({
        where: { id },
        data: { status: 'DISMISSED', resolvedAt: now(), resolvedById: req.adminId },
      });
      await audit(db, req, 'REPORT_DISMISS', 'REPORT', id);
      return { id, status: 'DISMISSED' };
    });

    // ───────── 사진 검수 피드 ─────────

    r.get('/admin/photos', async (req) => {
      const { filter, cursor } = parse(PhotosQuery, req.query);
      const rows = await db.letterPhoto.findMany({
        where: {
          letterId: { not: null },
          ...(filter === 'unreviewed' ? { reviewedAt: null } : {}),
        },
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        take: 25,
        ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
        include: {
          reviewedBy: { select: { username: true } },
          letter: {
            include: {
              sender: { select: { id: true, nickname: true } },
              recipient: { select: { id: true, nickname: true } },
            },
          },
        },
      });
      const page = rows.slice(0, 24);
      return {
        photos: await Promise.all(
          page.map(async (p) => ({
            id: p.id,
            url: await storage.signedUrl(p.storageKey),
            width: p.width,
            height: p.height,
            createdAt: p.createdAt.toISOString(),
            reviewedAt: p.reviewedAt?.toISOString() ?? null,
            reviewedBy: p.reviewedBy?.username ?? null,
            letter: p.letter && {
              id: p.letter.id,
              mode: p.letter.mode,
              status: p.letter.status,
              body: p.letter.body,
              etaAt: p.letter.etaAt?.toISOString() ?? null,
              deliveredAt: p.letter.deliveredAt?.toISOString() ?? null,
              sender: p.letter.sender,
              recipient: p.letter.recipient,
            },
          })),
        ),
        nextCursor: rows.length > 24 ? page[page.length - 1]!.id : null,
      };
    });

    r.post('/admin/photos/:id/review', async (req) => {
      const { id } = parse(Id, req.params);
      const { count } = await db.letterPhoto.updateMany({
        where: { id, reviewedAt: null },
        data: { reviewedAt: now(), reviewedById: req.adminId },
      });
      if (count > 0) await audit(db, req, 'PHOTO_REVIEW', 'PHOTO', id);
      return { id, reviewed: true };
    });

    // ───────── 먹기(삭제) · 특급 배달 ─────────

    r.post('/admin/letters/:id/eat', async (req) => {
      const { id } = parse(Id, req.params);
      const { reason } = parse(Reason, req.body ?? {});
      const result = await eat.eatLetter(id, reason);
      if (result.eaten) {
        await db.report.updateMany({
          where: { letterId: id, resolvedById: null, status: 'RESOLVED' },
          data: { resolvedById: req.adminId },
        });
        await db.letterPhoto.updateMany({
          where: { letterId: id, reviewedAt: null },
          data: { reviewedAt: now(), reviewedById: req.adminId },
        });
        await audit(db, req, 'LETTER_EAT', 'LETTER', id, { reason });
      }
      return { id, ...result };
    });

    r.post('/admin/rolling-entries/:id/eat', async (req) => {
      const { id } = parse(Id, req.params);
      const result = await eat.eatRollingEntry(id);
      if (result.eaten) {
        await db.report.updateMany({
          where: { rollingEntryId: id, resolvedById: null, status: 'RESOLVED' },
          data: { resolvedById: req.adminId },
        });
        await audit(db, req, 'ROLLING_ENTRY_EAT', 'ROLLING_ENTRY', id);
      }
      return { id, ...result };
    });

    /** 특급 배달 수동 발동: 이동 중인 편지를 1분 뒤 도착으로 */
    r.post('/admin/letters/:id/express', async (req) => {
      requireAdmin(req);
      const { id } = parse(Id, req.params);
      const at = new Date(now().getTime() + 60_000);
      const { count } = await db.letter.updateMany({
        where: { id, status: 'IN_TRANSIT' },
        data: { etaAt: at, express: true },
      });
      if (count === 0)
        throw new AppError(409, 'NOT_IN_TRANSIT', '이동 중인 편지만 특급으로 보낼 수 있어요.');
      await audit(db, req, 'LETTER_EXPRESS', 'LETTER', id);
      return { id, etaAt: at.toISOString() };
    });

    // ───────── 사용자 · 제재 ─────────

    r.get('/admin/users', async (req) => {
      const { q } = parse(UsersQuery, req.query);
      const rows = await db.user.findMany({
        where: q
          ? {
              OR: [
                { nicknameKey: { contains: q.toLowerCase() } },
                ...(z.string().uuid().safeParse(q).success ? [{ id: q }] : []),
              ],
            }
          : { nickname: { not: null } },
        orderBy: { createdAt: 'desc' },
        take: 50,
        select: {
          id: true,
          nickname: true,
          status: true,
          suspendedUntil: true,
          createdAt: true,
          lastActiveAt: true,
          isOfficial: true,
          _count: { select: { reportsReceived: true, sentLetters: true } },
        },
      });
      return {
        users: rows.map((u) => ({
          id: u.id,
          nickname: u.nickname,
          status: u.status,
          suspendedUntil: u.suspendedUntil?.toISOString() ?? null,
          createdAt: u.createdAt.toISOString(),
          lastActiveAt: u.lastActiveAt.toISOString(),
          isOfficial: u.isOfficial,
          reportsReceived: u._count.reportsReceived,
          lettersSent: u._count.sentLetters,
        })),
      };
    });

    /** 사용자 상세. 생년월일·소셜 ID는 관리자에게도 보이지 않는다(나이 확인 여부만). */
    r.get('/admin/users/:id', async (req) => {
      const { id } = parse(Id, req.params);
      const u = await db.user.findUnique({
        where: { id },
        include: {
          sanctions: {
            orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
            include: { admin: { select: { username: true } } },
          },
          _count: {
            select: {
              reportsReceived: true,
              sentLetters: true,
              receivedLetters: true,
              rollingEntries: true,
            },
          },
        },
      });
      if (!u) throw new AppError(404, 'USER_NOT_FOUND', '사용자를 찾을 수 없어요.');
      const eaten = await db.letter.count({ where: { senderId: id, status: 'EATEN' } });
      return {
        id: u.id,
        nickname: u.nickname,
        status: u.status,
        suspendedUntil: u.suspendedUntil?.toISOString() ?? null,
        createdAt: u.createdAt.toISOString(),
        lastActiveAt: u.lastActiveAt.toISOString(),
        pointsBalance: u.pointsBalance,
        lastRegionCode: u.lastRegionCode,
        ageVerified: u.birthDate !== null,
        counts: { ...u._count, eatenLetters: eaten },
        sanctions: u.sanctions.map((s) => ({
          id: s.id,
          type: s.type,
          reason: s.reason,
          admin: s.admin.username,
          createdAt: s.createdAt.toISOString(),
        })),
      };
    });

    /** 제재: 경고 → 7일 정지 → 영구 정지, 해제 */
    r.post('/admin/users/:id/sanctions', async (req) => {
      const { id } = parse(Id, req.params);
      const { type, reason } = parse(SanctionBody, req.body);
      if (type === 'BAN' || type === 'LIFT') requireAdmin(req);
      const u = await db.user.findUnique({ where: { id } });
      if (!u) throw new AppError(404, 'USER_NOT_FOUND', '사용자를 찾을 수 없어요.');
      if (u.isOfficial)
        throw new AppError(400, 'OFFICIAL_ACCOUNT', '공식 계정은 제재할 수 없어요.');
      const at = now();
      const data: Prisma.UserUpdateInput =
        type === 'SUSPEND_7D'
          ? { status: 'SUSPENDED', suspendedUntil: new Date(at.getTime() + 7 * DAY) }
          : type === 'BAN'
            ? { status: 'BANNED' }
            : type === 'LIFT'
              ? { status: 'ACTIVE', suspendedUntil: null }
              : {};
      await db.$transaction([
        db.sanction.create({
          data: { userId: id, type, reason, adminId: req.adminId, createdAt: at },
        }),
        db.user.update({ where: { id }, data }),
        ...(type === 'BAN'
          ? [
              db.refreshToken.updateMany({
                where: { userId: id, revokedAt: null },
                data: { revokedAt: at },
              }),
            ]
          : []),
      ]);
      const msg = {
        WARNING: { title: '운영 정책 안내', body: `운영 정책 위반으로 경고를 받았어요: ${reason}` },
        SUSPEND_7D: {
          title: '이용 정지 안내',
          body: `7일 동안 편지와 두루마리 쓰기가 멈춰요: ${reason}`,
        },
        BAN: null,
        LIFT: { title: '이용 제한 해제', body: '다시 편지를 보낼 수 있어요. 반가워요!' },
      }[type];
      if (msg) await pusher.sendToUser(id, { ...msg, data: { type: 'sanction' } }).catch(() => 0);
      await audit(db, req, `SANCTION_${type}`, 'USER', id, { reason });
      const after = await db.user.findUniqueOrThrow({ where: { id } });
      return {
        id,
        status: after.status,
        suspendedUntil: after.suspendedUntil?.toISOString() ?? null,
      };
    });

    // ───────── 공지 · 푸시 ─────────

    r.get('/admin/notices', async () => {
      const rows = await db.notice.findMany({
        orderBy: { createdAt: 'desc' },
        take: 100,
        include: { createdBy: { select: { username: true } } },
      });
      return {
        notices: rows.map((n) => ({
          id: n.id,
          title: n.title,
          body: n.body,
          pinned: n.pinned,
          publishedAt: n.publishedAt?.toISOString() ?? null,
          createdBy: n.createdBy.username,
          createdAt: n.createdAt.toISOString(),
        })),
      };
    });

    r.post('/admin/notices', async (req, reply) => {
      requireAdmin(req);
      const b = parse(NoticeBody, req.body);
      const n = await db.notice.create({
        data: {
          title: b.title,
          body: b.body,
          pinned: b.pinned,
          publishedAt: b.publish ? now() : null,
          createdById: req.adminId,
        },
      });
      let pushed = 0;
      if (b.publish && b.push) {
        // 알림을 켠 사용자에게만
        const users = await db.user.findMany({
          where: {
            notifyEnabled: true,
            status: { in: ['ACTIVE', 'SUSPENDED'] },
            fcmTokens: { some: {} },
          },
          select: { id: true },
        });
        for (const u of users) {
          pushed += await pusher
            .sendToUser(u.id, {
              title: b.title,
              body: b.body.slice(0, 100),
              data: { type: 'notice', noticeId: n.id },
            })
            .catch(() => 0);
        }
      }
      await audit(db, req, 'NOTICE_CREATE', 'NOTICE', n.id, { push: b.push, pushed });
      return reply.status(201).send({ id: n.id, pushed });
    });

    r.post('/admin/notices/:id/unpublish', async (req) => {
      requireAdmin(req);
      const { id } = parse(Id, req.params);
      await db.notice.update({ where: { id }, data: { publishedAt: null } });
      await audit(db, req, 'NOTICE_UNPUBLISH', 'NOTICE', id);
      return { id, published: false };
    });

    // ───────── 롤링페이퍼 ─────────

    r.get('/admin/rolling/topics', async () => {
      const rows = await db.rollingTopic.findMany({
        where: { periodStart: { gte: new Date(now().getTime() - 8 * DAY) } },
        orderBy: [{ periodStart: 'desc' }, { level: 'asc' }],
      });
      return {
        topics: rows.map((t) => ({
          level: t.level,
          scopeCode: t.scopeCode,
          periodStart: t.periodStart.toISOString(),
          topic: t.topic,
        })),
        periods: Object.fromEntries(
          (['NATION', 'PROVINCE', 'CITY'] as const).map((l) => {
            const p = periodOf(l, now());
            return [l, { current: p.start.toISOString(), next: p.end.toISOString() }];
          }),
        ),
      };
    });

    r.post('/admin/rolling/topics', async (req) => {
      const b = parse(TopicBody, req.body);
      const cur = periodOf(b.level, now());
      const periodStart = b.when === 'current' ? cur.start : periodOf(b.level, cur.end).start;
      const scopeCode = b.level === 'NATION' && b.scopeCode !== '*' ? 'KR' : b.scopeCode;
      await db.rollingTopic.upsert({
        where: { level_periodStart_scopeCode: { level: b.level, periodStart, scopeCode } },
        create: { level: b.level, periodStart, scopeCode, topic: b.topic },
        update: { topic: b.topic },
      });
      await audit(db, req, 'ROLLING_TOPIC', 'ROLLING', `${b.level}:${scopeCode}`, {
        topic: b.topic,
        periodStart: periodStart.toISOString(),
      });
      return { level: b.level, scopeCode, periodStart: periodStart.toISOString(), topic: b.topic };
    });

    /** 공식 계정(메에일 우체국)으로 이번 장에 환영 글(SPEC 6, 15) */
    r.post('/admin/rolling/official-entry', async (req, reply) => {
      requireAdmin(req);
      const b = parse(OfficialEntry, req.body);
      const level = b.level as RollingLevel;
      const scopeCode = level === 'NATION' ? 'KR' : b.scopeCode;
      const { start, end } = periodOf(level, now());
      const paper = await db.rollingPaper.upsert({
        where: { level_scopeCode_periodStart: { level, scopeCode, periodStart: start } },
        create: { level, scopeCode, periodStart: start, periodEnd: end },
        update: {},
      });
      const official = await officialUser(db);
      const e = await db.rollingEntry.upsert({
        where: { paperId_authorId: { paperId: paper.id, authorId: official.id } },
        create: { paperId: paper.id, authorId: official.id, body: b.body, createdAt: now() },
        update: { body: b.body },
      });
      await audit(db, req, 'ROLLING_OFFICIAL_ENTRY', 'ROLLING_ENTRY', e.id);
      return reply.status(201).send({ id: e.id, paperId: paper.id });
    });

    // ───────── 웹 탈퇴 요청 ─────────

    r.get('/admin/deletion-requests', async () => {
      const rows = await db.deletionRequest.findMany({
        orderBy: [{ processedAt: { sort: 'desc', nulls: 'first' } }, { createdAt: 'asc' }],
        take: 100,
      });
      return {
        requests: await Promise.all(
          rows.map(async (x) => {
            const u = x.processedAt
              ? null
              : await db.user.findFirst({
                  where: { nicknameKey: nicknameKey(x.nickname) },
                  select: { id: true, nickname: true, createdAt: true, lastActiveAt: true },
                });
            return {
              id: x.id,
              nickname: x.nickname,
              hasContact: x.contact !== null,
              contact: x.contact,
              message: x.message,
              createdAt: x.createdAt.toISOString(),
              processedAt: x.processedAt?.toISOString() ?? null,
              result: x.result,
              match: u
                ? {
                    id: u.id,
                    nickname: u.nickname,
                    createdAt: u.createdAt.toISOString(),
                    lastActiveAt: u.lastActiveAt.toISOString(),
                  }
                : null,
            };
          }),
        ),
      };
    });

    /** 요청 처리: DELETE면 그 닉네임 계정을 탈퇴 처리. 어느 쪽이든 연락처는 지운다. */
    r.post('/admin/deletion-requests/:id/process', async (req) => {
      requireAdmin(req);
      const { id } = parse(Id, req.params);
      const { action } = parse(z.object({ action: z.enum(['DELETE', 'REJECT']) }), req.body);
      const x = await db.deletionRequest.findUnique({ where: { id } });
      if (!x) throw new AppError(404, 'REQUEST_NOT_FOUND', '요청을 찾을 수 없어요.');
      if (x.processedAt) throw new AppError(409, 'ALREADY_PROCESSED', '이미 처리한 요청이에요.');
      let result = 'REJECTED';
      if (action === 'DELETE') {
        const u = await db.user.findFirst({
          where: { nicknameKey: nicknameKey(x.nickname), isOfficial: false },
        });
        if (u) {
          await deps.account.deleteAccount(u.id);
          result = 'DELETED';
        } else {
          result = 'NOT_FOUND';
        }
      }
      await db.deletionRequest.update({
        where: { id },
        data: { processedAt: now(), processedById: req.adminId, result, contact: null },
      });
      await audit(db, req, 'DELETION_REQUEST', 'DELETION_REQUEST', id, { result });
      return { id, result };
    });

    // ───────── 감사 로그 ─────────

    r.get('/admin/audit', async (req) => {
      requireAdmin(req);
      const { cursor } = parse(Cursor, req.query);
      const rows = await db.auditLog.findMany({
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        take: 51,
        ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
        include: { admin: { select: { username: true } } },
      });
      const page = rows.slice(0, 50);
      return {
        logs: page.map((l) => ({
          id: l.id,
          admin: l.admin.username,
          action: l.action,
          targetType: l.targetType,
          targetId: l.targetId,
          detail: l.detail,
          createdAt: l.createdAt.toISOString(),
        })),
        nextCursor: rows.length > 50 ? page[page.length - 1]!.id : null,
      };
    });
  });
};
