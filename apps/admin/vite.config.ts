import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

// 운영에서는 Caddy가 /admin 경로로 정적 파일을 서빙한다 (SPEC 11.3)
export default defineConfig({
  base: '/admin/',
  plugins: [react()],
  server: {
    proxy: { '/api': { target: 'http://localhost:3000', rewrite: (p) => p.replace(/^\/api/, '') } },
  },
  test: { environment: 'jsdom' },
});
