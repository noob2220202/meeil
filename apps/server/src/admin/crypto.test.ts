import { describe, expect, it } from 'vitest';
import {
  base32Decode,
  base32Encode,
  hashPassword,
  seal,
  totpCode,
  unseal,
  verifyPassword,
  verifyTotp,
} from './crypto.js';

describe('관리자 보안 도우미', () => {
  it('TOTP는 RFC 6238 표준 값과 같다', () => {
    const secret = base32Encode(Buffer.from('12345678901234567890'));
    // RFC 6238 부록 B(SHA1, 8자리)의 끝 6자리
    expect(totpCode(secret, 59_000)).toBe('287082');
    expect(totpCode(secret, 1111111109_000)).toBe('081804');
    expect(totpCode(secret, 1234567890_000)).toBe('005924');
    expect(verifyTotp(secret, '287082', 59_000 + 30_000)).toBe(true);
    expect(verifyTotp(secret, '287082', 59_000 + 90_000)).toBe(false);
    expect(verifyTotp(secret, 'abc', 59_000)).toBe(false);
    expect(base32Decode(secret).toString()).toBe('12345678901234567890');
  });

  it('비밀번호 해시는 매번 다르고 검증된다', async () => {
    const a = await hashPassword('s3cret-pass');
    const b = await hashPassword('s3cret-pass');
    expect(a).not.toBe(b);
    expect(await verifyPassword('s3cret-pass', a)).toBe(true);
    expect(await verifyPassword('wrong', a)).toBe(false);
    expect(await verifyPassword('x', 'garbage')).toBe(false);
  });

  it('시크릿 암호화: 다른 키나 변조는 풀리지 않는다', () => {
    const s = seal('JBSWY3DPEHPK3PXP', 'k'.repeat(32));
    expect(unseal(s, 'k'.repeat(32))).toBe('JBSWY3DPEHPK3PXP');
    expect(() => unseal(s, 'x'.repeat(32))).toThrow();
    const parts = s.split('.');
    parts[2] = Buffer.from('tampered').toString('base64url');
    expect(() => unseal(parts.join('.'), 'k'.repeat(32))).toThrow();
  });
});
