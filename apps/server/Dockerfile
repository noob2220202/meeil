# 빌드 컨텍스트: 저장소 루트
FROM node:22-alpine AS build
WORKDIR /repo
RUN corepack enable
# prisma.config.ts가 요구하는 값. 빌드 단계에서만 쓰는 더미이며 DB에 접속하지 않는다.
ENV DATABASE_URL=postgresql://build:build@localhost/build
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json eslint.config.base.js ./
COPY apps/server/package.json apps/server/
COPY apps/server/prisma apps/server/prisma
COPY apps/server/prisma.config.ts apps/server/
RUN pnpm install --frozen-lockfile --filter @meeil/server...
COPY apps/server apps/server
RUN pnpm --filter @meeil/server run db:generate \
  && pnpm --filter @meeil/server run build \
  && pnpm deploy --filter @meeil/server --prod --legacy /out \
  && cp -r apps/server/dist apps/server/prisma apps/server/prisma.config.ts /out/

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
ENV LEGAL_DIR=/app/legal
COPY --from=build /out /app
COPY docs/legal /app/legal
EXPOSE 3000
# 기동 시 마이그레이션을 적용한다.
CMD ["sh", "-c", "node node_modules/prisma/build/index.js migrate deploy && node dist/server.js"]
