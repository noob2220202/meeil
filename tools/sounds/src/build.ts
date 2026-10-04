// pnpm --filter @meeil/tools-sounds build:sounds
// 효과음을 합성해 assets-src/sounds/ 와 apps/mobile/assets/sounds/ 에 WAV로 쓴다.
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SOUNDS } from './sounds.js';
import { wav } from './synth.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '../../..');
const outs = [join(root, 'assets-src/sounds'), join(root, 'apps/mobile/assets/sounds')];
for (const dir of outs) mkdirSync(dir, { recursive: true });

for (const [name, make] of Object.entries(SOUNDS)) {
  const file = wav(make());
  for (const dir of outs) writeFileSync(join(dir, `${name}.wav`), file);
  console.log(`${name}.wav  ${(file.length / 1024).toFixed(1)}KB`);
}
