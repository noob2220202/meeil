import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, describe, expect, it } from 'vitest';
import { DirBackupStore, latestBackup, storeFromEnv } from './backup-cli.js';

const dirs: string[] = [];
afterAll(async () => {
  for (const d of dirs) await rm(d, { recursive: true, force: true });
});

describe('백업 보관소', () => {
  it('로컬 폴더: 올리고·받고·목록·최신·지우기', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'meeil-backup-'));
    dirs.push(dir);
    const s = new DirBackupStore(dir);
    expect(await s.list()).toEqual([]);
    expect(await latestBackup(s)).toBeNull();
    await s.put('db/meeil-20261003T1800Z.dump.enc', Buffer.from('a'));
    await s.put('db/meeil-20261004T1800Z.dump.enc', Buffer.from('b'));
    await s.put('db/notes.txt', Buffer.from('x'));
    expect(await latestBackup(s)).toBe('db/meeil-20261004T1800Z.dump.enc');
    expect((await s.get('db/meeil-20261003T1800Z.dump.enc')).toString()).toBe('a');
    await s.delete('db/meeil-20261004T1800Z.dump.enc');
    expect(await latestBackup(s)).toBe('db/meeil-20261003T1800Z.dump.enc');
  });

  it('폴더 밖으로 나가는 키는 거절', async () => {
    const s = new DirBackupStore('/tmp/meeil-backup-x');
    await expect(s.put('../../etc/passwd', Buffer.from('x'))).rejects.toThrow('잘못된 키');
  });

  it('R2 설정 검사: 빠진 값, 사진 버킷과 같은 버킷', () => {
    expect(() => storeFromEnv({})).toThrow('R2_ACCOUNT_ID');
    const r2 = {
      R2_ACCOUNT_ID: 'a',
      R2_ACCESS_KEY_ID: 'b',
      R2_SECRET_ACCESS_KEY: 'c',
      R2_BUCKET: 'photos',
    };
    expect(() => storeFromEnv({ ...r2, R2_BACKUP_BUCKET: 'photos' })).toThrow('달라야');
    expect(() => storeFromEnv({ ...r2, R2_BACKUP_BUCKET: 'backups' })).not.toThrow();
    expect(storeFromEnv({ BACKUP_DIR: '/tmp/x' })).toBeInstanceOf(DirBackupStore);
  });
});
