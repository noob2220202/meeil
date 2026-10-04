-- CreateEnum
CREATE TYPE "UserStatus" AS ENUM ('ACTIVE', 'SUSPENDED', 'BANNED', 'DELETED');

-- CreateEnum
CREATE TYPE "AuthProvider" AS ENUM ('KAKAO', 'GOOGLE');

-- CreateEnum
CREATE TYPE "GoatKind" AS ENUM ('DELIVERY', 'ROLLING_NATION', 'ROLLING_PROVINCE', 'ROLLING_CITY');

-- CreateEnum
CREATE TYPE "LetterMode" AS ENUM ('DIRECT', 'RANDOM', 'REPLY');

-- CreateEnum
CREATE TYPE "RandomScope" AS ENUM ('NATION', 'PROVINCE', 'CITY');

-- CreateEnum
CREATE TYPE "LetterStatus" AS ENUM ('HANDED', 'IN_TRANSIT', 'DELIVERED', 'READ', 'EATEN');

-- CreateEnum
CREATE TYPE "RollingLevel" AS ENUM ('NATION', 'PROVINCE', 'CITY');

-- CreateEnum
CREATE TYPE "RollingEntryStatus" AS ENUM ('VISIBLE', 'EATEN');

-- CreateEnum
CREATE TYPE "LedgerReason" AS ENUM ('SIGNUP_BONUS', 'ATTENDANCE', 'ATTENDANCE_STREAK', 'AD_REWARD', 'ACHIEVEMENT', 'LETTER_SEND', 'LETTER_REFUND', 'ADMIN_ADJUST');

-- CreateEnum
CREATE TYPE "ReportTargetType" AS ENUM ('LETTER', 'ROLLING_ENTRY', 'USER');

-- CreateEnum
CREATE TYPE "ReportStatus" AS ENUM ('OPEN', 'RESOLVED', 'DISMISSED');

-- CreateEnum
CREATE TYPE "SanctionType" AS ENUM ('WARNING', 'SUSPEND_7D', 'BAN', 'LIFT');

-- CreateEnum
CREATE TYPE "AdminRole" AS ENUM ('ADMIN', 'MODERATOR');

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "nickname" TEXT,
    "nicknameChangedAt" TIMESTAMP(3),
    "birthDate" DATE,
    "status" "UserStatus" NOT NULL DEFAULT 'ACTIVE',
    "suspendedUntil" TIMESTAMP(3),
    "termsAgreedAt" TIMESTAMP(3),
    "privacyAgreedAt" TIMESTAMP(3),
    "homeRegionCode" TEXT,
    "lastRegionCode" TEXT,
    "lastRegionReportedAt" TIMESTAMP(3),
    "randomReceive" BOOLEAN NOT NULL DEFAULT true,
    "notifyEnabled" BOOLEAN NOT NULL DEFAULT true,
    "pointsBalance" INTEGER NOT NULL DEFAULT 0,
    "titleAchievementId" TEXT,
    "isOfficial" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastActiveAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deletedAt" TIMESTAMP(3),

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "auth_identities" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "provider" "AuthProvider" NOT NULL,
    "providerUserId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "auth_identities_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refresh_tokens" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "familyId" UUID NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "provinces" (
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "shortName" TEXT NOT NULL,
    "version" TEXT NOT NULL,

    CONSTRAINT "provinces_pkey" PRIMARY KEY ("code")
);

-- CreateTable
CREATE TABLE "regions" (
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "fullName" TEXT NOT NULL,
    "provinceCode" TEXT NOT NULL,
    "lon" DOUBLE PRECISION NOT NULL,
    "lat" DOUBLE PRECISION NOT NULL,
    "neighbors" TEXT[],
    "version" TEXT NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "regions_pkey" PRIMARY KEY ("code")
);

-- CreateTable
CREATE TABLE "user_region_reports" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "regionCode" TEXT NOT NULL,
    "reportedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "accepted" BOOLEAN NOT NULL,
    "rejectReason" TEXT,

    CONSTRAINT "user_region_reports_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "region_visits" (
    "userId" UUID NOT NULL,
    "regionCode" TEXT NOT NULL,

    CONSTRAINT "region_visits_pkey" PRIMARY KEY ("userId","regionCode")
);

-- CreateTable
CREATE TABLE "goats" (
    "id" TEXT NOT NULL,
    "kind" "GoatKind" NOT NULL,
    "name" TEXT NOT NULL,
    "scopeCode" TEXT,
    "speedKmh" DOUBLE PRECISION NOT NULL,
    "stayMinMin" INTEGER NOT NULL,
    "stayMaxMin" INTEGER NOT NULL,
    "hatColor" TEXT NOT NULL,
    "bagColor" TEXT NOT NULL,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "active" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "goats_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "goat_schedule_stops" (
    "id" UUID NOT NULL,
    "goatId" TEXT NOT NULL,
    "regionCode" TEXT NOT NULL,
    "seq" INTEGER NOT NULL,
    "arriveAt" TIMESTAMP(3) NOT NULL,
    "departAt" TIMESTAMP(3) NOT NULL,
    "express" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "goat_schedule_stops_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "letters" (
    "id" UUID NOT NULL,
    "mode" "LetterMode" NOT NULL,
    "senderId" UUID NOT NULL,
    "recipientId" UUID NOT NULL,
    "replyToId" UUID,
    "randomScope" "RandomScope",
    "randomScopeCode" TEXT,
    "originRegionCode" TEXT NOT NULL,
    "destRegionCode" TEXT NOT NULL,
    "body" VARCHAR(200) NOT NULL,
    "stationeryId" TEXT NOT NULL,
    "stickers" JSONB NOT NULL DEFAULT '[]',
    "status" "LetterStatus" NOT NULL DEFAULT 'HANDED',
    "goatId" TEXT,
    "express" BOOLEAN NOT NULL DEFAULT false,
    "handedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "etaAt" TIMESTAMP(3),
    "deliveredAt" TIMESTAMP(3),
    "readAt" TIMESTAMP(3),
    "eatenAt" TIMESTAMP(3),
    "eatenReason" TEXT,
    "hiddenForRecipient" BOOLEAN NOT NULL DEFAULT false,
    "senderTrashedAt" TIMESTAMP(3),
    "senderPurgedAt" TIMESTAMP(3),
    "recipientTrashedAt" TIMESTAMP(3),
    "recipientPurgedAt" TIMESTAMP(3),

    CONSTRAINT "letters_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "letter_photos" (
    "id" UUID NOT NULL,
    "letterId" UUID NOT NULL,
    "storageKey" TEXT NOT NULL,
    "width" INTEGER NOT NULL,
    "height" INTEGER NOT NULL,
    "bytes" INTEGER NOT NULL,
    "reviewedAt" TIMESTAMP(3),
    "reviewedById" UUID,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "letter_photos_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "rolling_papers" (
    "id" UUID NOT NULL,
    "level" "RollingLevel" NOT NULL,
    "scopeCode" TEXT NOT NULL,
    "periodStart" TIMESTAMP(3) NOT NULL,
    "periodEnd" TIMESTAMP(3) NOT NULL,
    "topic" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "rolling_papers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "rolling_entries" (
    "id" UUID NOT NULL,
    "paperId" UUID NOT NULL,
    "authorId" UUID NOT NULL,
    "body" VARCHAR(200) NOT NULL,
    "stickers" JSONB NOT NULL DEFAULT '[]',
    "status" "RollingEntryStatus" NOT NULL DEFAULT 'VISIBLE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "eatenAt" TIMESTAMP(3),

    CONSTRAINT "rolling_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "points_ledger" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "delta" INTEGER NOT NULL,
    "balanceAfter" INTEGER NOT NULL,
    "reason" "LedgerReason" NOT NULL,
    "refId" TEXT,
    "idempotencyKey" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "points_ledger_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "attendance" (
    "userId" UUID NOT NULL,
    "date" DATE NOT NULL,
    "streak" INTEGER NOT NULL,

    CONSTRAINT "attendance_pkey" PRIMARY KEY ("userId","date")
);

-- CreateTable
CREATE TABLE "achievements" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "rewardPoints" INTEGER NOT NULL DEFAULT 0,
    "titleText" TEXT,
    "unlocksStationeryId" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "achievements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_achievements" (
    "userId" UUID NOT NULL,
    "achievementId" TEXT NOT NULL,
    "achievedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_achievements_pkey" PRIMARY KEY ("userId","achievementId")
);

-- CreateTable
CREATE TABLE "stationery" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "unlockHint" TEXT NOT NULL,
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "stationery_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_stationery" (
    "userId" UUID NOT NULL,
    "stationeryId" TEXT NOT NULL,
    "unlockedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_stationery_pkey" PRIMARY KEY ("userId","stationeryId")
);

-- CreateTable
CREATE TABLE "reports" (
    "id" UUID NOT NULL,
    "reporterId" UUID NOT NULL,
    "targetType" "ReportTargetType" NOT NULL,
    "letterId" UUID,
    "rollingEntryId" UUID,
    "targetUserId" UUID,
    "reason" TEXT NOT NULL,
    "detail" VARCHAR(500),
    "status" "ReportStatus" NOT NULL DEFAULT 'OPEN',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMP(3),
    "resolvedById" UUID,

    CONSTRAINT "reports_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "blocks" (
    "blockerId" UUID NOT NULL,
    "blockedId" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "blocks_pkey" PRIMARY KEY ("blockerId","blockedId")
);

-- CreateTable
CREATE TABLE "sanctions" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "type" "SanctionType" NOT NULL,
    "reason" TEXT NOT NULL,
    "adminId" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sanctions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "fcm_tokens" (
    "token" TEXT NOT NULL,
    "userId" UUID NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "fcm_tokens_pkey" PRIMARY KEY ("token")
);

-- CreateTable
CREATE TABLE "admin_users" (
    "id" UUID NOT NULL,
    "username" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "totpSecret" TEXT,
    "role" "AdminRole" NOT NULL DEFAULT 'MODERATOR',
    "disabled" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastLoginAt" TIMESTAMP(3),

    CONSTRAINT "admin_users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_logs" (
    "id" UUID NOT NULL,
    "adminId" UUID NOT NULL,
    "action" TEXT NOT NULL,
    "targetType" TEXT,
    "targetId" TEXT,
    "detail" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notices" (
    "id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "pinned" BOOLEAN NOT NULL DEFAULT false,
    "publishedAt" TIMESTAMP(3),
    "createdById" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notices_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_nickname_key" ON "users"("nickname");

-- CreateIndex
CREATE INDEX "users_lastRegionCode_randomReceive_lastActiveAt_idx" ON "users"("lastRegionCode", "randomReceive", "lastActiveAt");

-- CreateIndex
CREATE INDEX "auth_identities_userId_idx" ON "auth_identities"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "auth_identities_provider_providerUserId_key" ON "auth_identities"("provider", "providerUserId");

-- CreateIndex
CREATE UNIQUE INDEX "refresh_tokens_tokenHash_key" ON "refresh_tokens"("tokenHash");

-- CreateIndex
CREATE INDEX "refresh_tokens_userId_idx" ON "refresh_tokens"("userId");

-- CreateIndex
CREATE INDEX "refresh_tokens_familyId_idx" ON "refresh_tokens"("familyId");

-- CreateIndex
CREATE INDEX "regions_provinceCode_idx" ON "regions"("provinceCode");

-- CreateIndex
CREATE INDEX "user_region_reports_userId_reportedAt_idx" ON "user_region_reports"("userId", "reportedAt");

-- CreateIndex
CREATE INDEX "goats_kind_idx" ON "goats"("kind");

-- CreateIndex
CREATE INDEX "goat_schedule_stops_goatId_arriveAt_idx" ON "goat_schedule_stops"("goatId", "arriveAt");

-- CreateIndex
CREATE INDEX "goat_schedule_stops_regionCode_arriveAt_idx" ON "goat_schedule_stops"("regionCode", "arriveAt");

-- CreateIndex
CREATE UNIQUE INDEX "goat_schedule_stops_goatId_seq_key" ON "goat_schedule_stops"("goatId", "seq");

-- CreateIndex
CREATE INDEX "letters_recipientId_status_deliveredAt_idx" ON "letters"("recipientId", "status", "deliveredAt");

-- CreateIndex
CREATE INDEX "letters_senderId_handedAt_idx" ON "letters"("senderId", "handedAt");

-- CreateIndex
CREATE INDEX "letters_status_etaAt_idx" ON "letters"("status", "etaAt");

-- CreateIndex
CREATE UNIQUE INDEX "letter_photos_letterId_key" ON "letter_photos"("letterId");

-- CreateIndex
CREATE INDEX "letter_photos_reviewedAt_createdAt_idx" ON "letter_photos"("reviewedAt", "createdAt");

-- CreateIndex
CREATE INDEX "rolling_papers_level_periodEnd_idx" ON "rolling_papers"("level", "periodEnd");

-- CreateIndex
CREATE UNIQUE INDEX "rolling_papers_level_scopeCode_periodStart_key" ON "rolling_papers"("level", "scopeCode", "periodStart");

-- CreateIndex
CREATE UNIQUE INDEX "rolling_entries_paperId_authorId_key" ON "rolling_entries"("paperId", "authorId");

-- CreateIndex
CREATE UNIQUE INDEX "points_ledger_idempotencyKey_key" ON "points_ledger"("idempotencyKey");

-- CreateIndex
CREATE INDEX "points_ledger_userId_createdAt_idx" ON "points_ledger"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "reports_status_createdAt_idx" ON "reports"("status", "createdAt");

-- CreateIndex
CREATE INDEX "blocks_blockedId_idx" ON "blocks"("blockedId");

-- CreateIndex
CREATE INDEX "sanctions_userId_createdAt_idx" ON "sanctions"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "fcm_tokens_userId_idx" ON "fcm_tokens"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "admin_users_username_key" ON "admin_users"("username");

-- CreateIndex
CREATE INDEX "audit_logs_createdAt_idx" ON "audit_logs"("createdAt");

-- CreateIndex
CREATE INDEX "notices_publishedAt_idx" ON "notices"("publishedAt");

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_homeRegionCode_fkey" FOREIGN KEY ("homeRegionCode") REFERENCES "regions"("code") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_lastRegionCode_fkey" FOREIGN KEY ("lastRegionCode") REFERENCES "regions"("code") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_titleAchievementId_fkey" FOREIGN KEY ("titleAchievementId") REFERENCES "achievements"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "auth_identities" ADD CONSTRAINT "auth_identities_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "regions" ADD CONSTRAINT "regions_provinceCode_fkey" FOREIGN KEY ("provinceCode") REFERENCES "provinces"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_region_reports" ADD CONSTRAINT "user_region_reports_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_region_reports" ADD CONSTRAINT "user_region_reports_regionCode_fkey" FOREIGN KEY ("regionCode") REFERENCES "regions"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "region_visits" ADD CONSTRAINT "region_visits_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "region_visits" ADD CONSTRAINT "region_visits_regionCode_fkey" FOREIGN KEY ("regionCode") REFERENCES "regions"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goat_schedule_stops" ADD CONSTRAINT "goat_schedule_stops_goatId_fkey" FOREIGN KEY ("goatId") REFERENCES "goats"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goat_schedule_stops" ADD CONSTRAINT "goat_schedule_stops_regionCode_fkey" FOREIGN KEY ("regionCode") REFERENCES "regions"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "letters" ADD CONSTRAINT "letters_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "letters" ADD CONSTRAINT "letters_recipientId_fkey" FOREIGN KEY ("recipientId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "letters" ADD CONSTRAINT "letters_replyToId_fkey" FOREIGN KEY ("replyToId") REFERENCES "letters"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "letters" ADD CONSTRAINT "letters_goatId_fkey" FOREIGN KEY ("goatId") REFERENCES "goats"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "letters" ADD CONSTRAINT "letters_stationeryId_fkey" FOREIGN KEY ("stationeryId") REFERENCES "stationery"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "letter_photos" ADD CONSTRAINT "letter_photos_letterId_fkey" FOREIGN KEY ("letterId") REFERENCES "letters"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "letter_photos" ADD CONSTRAINT "letter_photos_reviewedById_fkey" FOREIGN KEY ("reviewedById") REFERENCES "admin_users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "rolling_entries" ADD CONSTRAINT "rolling_entries_paperId_fkey" FOREIGN KEY ("paperId") REFERENCES "rolling_papers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "rolling_entries" ADD CONSTRAINT "rolling_entries_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "points_ledger" ADD CONSTRAINT "points_ledger_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "attendance" ADD CONSTRAINT "attendance_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "achievements" ADD CONSTRAINT "achievements_unlocksStationeryId_fkey" FOREIGN KEY ("unlocksStationeryId") REFERENCES "stationery"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_achievements" ADD CONSTRAINT "user_achievements_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_achievements" ADD CONSTRAINT "user_achievements_achievementId_fkey" FOREIGN KEY ("achievementId") REFERENCES "achievements"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_stationery" ADD CONSTRAINT "user_stationery_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_stationery" ADD CONSTRAINT "user_stationery_stationeryId_fkey" FOREIGN KEY ("stationeryId") REFERENCES "stationery"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_reporterId_fkey" FOREIGN KEY ("reporterId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_letterId_fkey" FOREIGN KEY ("letterId") REFERENCES "letters"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_rollingEntryId_fkey" FOREIGN KEY ("rollingEntryId") REFERENCES "rolling_entries"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_targetUserId_fkey" FOREIGN KEY ("targetUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_resolvedById_fkey" FOREIGN KEY ("resolvedById") REFERENCES "admin_users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "blocks" ADD CONSTRAINT "blocks_blockerId_fkey" FOREIGN KEY ("blockerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "blocks" ADD CONSTRAINT "blocks_blockedId_fkey" FOREIGN KEY ("blockedId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sanctions" ADD CONSTRAINT "sanctions_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sanctions" ADD CONSTRAINT "sanctions_adminId_fkey" FOREIGN KEY ("adminId") REFERENCES "admin_users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "fcm_tokens" ADD CONSTRAINT "fcm_tokens_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_adminId_fkey" FOREIGN KEY ("adminId") REFERENCES "admin_users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notices" ADD CONSTRAINT "notices_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "admin_users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
