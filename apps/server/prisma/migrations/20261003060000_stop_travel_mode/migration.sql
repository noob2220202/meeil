-- CreateEnum
CREATE TYPE "TravelMode" AS ENUM ('WALK', 'SEA');

-- AlterTable
ALTER TABLE "goat_schedule_stops" ADD COLUMN     "travelMode" "TravelMode" NOT NULL DEFAULT 'WALK';

