-- AlterTable
ALTER TABLE "users" ADD COLUMN     "nicknameKey" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "users_nicknameKey_key" ON "users"("nicknameKey");

