-- AlterTable
ALTER TABLE "letter_photos" ADD COLUMN     "uploaderId" UUID NOT NULL,
ALTER COLUMN "letterId" DROP NOT NULL;

-- AlterTable
ALTER TABLE "letters" ADD COLUMN     "clientRequestId" TEXT,
ADD COLUMN     "pickupGoatId" TEXT;

-- CreateIndex
CREATE INDEX "letter_photos_uploaderId_createdAt_idx" ON "letter_photos"("uploaderId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "letters_senderId_clientRequestId_key" ON "letters"("senderId", "clientRequestId");

-- AddForeignKey
ALTER TABLE "letter_photos" ADD CONSTRAINT "letter_photos_uploaderId_fkey" FOREIGN KEY ("uploaderId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

