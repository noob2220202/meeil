import type { z } from 'zod';

/** 클라이언트에 그대로 전달되는 오류. message는 사용자에게 보여줄 한국어 문구. */
export class AppError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export const unauthorized = (message = '다시 로그인해 주세요.') =>
  new AppError(401, 'UNAUTHORIZED', message);

/** zod로 검증하고 실패하면 400 VALIDATION */
export function parse<T extends z.ZodType>(schema: T, data: unknown): z.infer<T> {
  const r = schema.safeParse(data);
  if (!r.success) {
    const first = r.error.issues[0];
    throw new AppError(400, 'VALIDATION', first?.message ?? '입력값을 확인해 주세요.');
  }
  return r.data;
}
