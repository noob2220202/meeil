-- CreateTable
CREATE TABLE "rolling_topics" (
    "level" "RollingLevel" NOT NULL,
    "periodStart" TIMESTAMP(3) NOT NULL,
    "scopeCode" TEXT NOT NULL,
    "topic" VARCHAR(60) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "rolling_topics_pkey" PRIMARY KEY ("level","periodStart","scopeCode")
);

-- CreateIndex
CREATE INDEX "reports_reporterId_createdAt_idx" ON "reports"("reporterId", "createdAt");

-- CreateIndex
CREATE INDEX "reports_letterId_idx" ON "reports"("letterId");

-- CreateIndex
CREATE INDEX "reports_rollingEntryId_idx" ON "reports"("rollingEntryId");

-- CreateIndex
CREATE INDEX "reports_targetUserId_idx" ON "reports"("targetUserId");

