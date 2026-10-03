import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts', 'src/**/*.test.ts'],
    // DB 통합 테스트가 같은 DB를 쓰므로 파일 단위 병렬 실행을 끈다.
    fileParallelism: false,
  },
});
