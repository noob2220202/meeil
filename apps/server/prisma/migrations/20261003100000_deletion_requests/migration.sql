-- CreateTable
CREATE TABLE "deletion_requests" (
    "id" UUID NOT NULL,
    "nickname" VARCHAR(40) NOT NULL,
    "contact" VARCHAR(120),
    "message" VARCHAR(500),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "processedAt" TIMESTAMP(3),
    "result" TEXT,
    "processedById" UUID,

    CONSTRAINT "deletion_requests_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "deletion_requests_processedAt_createdAt_idx" ON "deletion_requests"("processedAt", "createdAt");

