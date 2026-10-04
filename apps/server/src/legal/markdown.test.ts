import { describe, expect, it } from 'vitest';
import { markdownToHtml, page } from './markdown.js';

describe('약관 마크다운 → HTML', () => {
  it('제목·목록·굵게·링크', () => {
    const html = markdownToHtml('# 제목\n\n- **하나**\n- [약관](/legal/terms)\n\n문단');
    expect(html).toContain('<h1>제목</h1>');
    expect(html).toContain('<li><strong>하나</strong></li>');
    expect(html).toContain('<a href="/legal/terms">약관</a>');
    expect(html).toContain('<p>문단</p>');
  });

  it('HTML은 이스케이프하고, javascript: 링크는 링크로 만들지 않는다', () => {
    const html = markdownToHtml('<script>alert(1)</script>\n\n[눌러](javascript:alert(1))');
    expect(html).not.toContain('<script>');
    expect(html).toContain('&lt;script&gt;');
    expect(html).not.toContain('href="javascript:');
    expect(page('<b>', html)).toContain('<title>&lt;b&gt; · 메에일</title>');
  });
});
