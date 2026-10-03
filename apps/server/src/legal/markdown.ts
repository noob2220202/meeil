// 약관 문서용 아주 작은 마크다운 → HTML(제목·문단·목록·굵게·링크·표 없음)
const esc = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function inline(s: string): string {
  return esc(s)
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\[(.+?)\]\((https?:\/\/[^\s)]+|\/[^\s)]*)\)/g, '<a href="$2">$1</a>');
}

export function markdownToHtml(md: string): string {
  const out: string[] = [];
  let list: 'ul' | 'ol' | null = null;
  let para: string[] = [];
  const flushPara = () => {
    if (para.length) out.push(`<p>${para.map(inline).join('<br>')}</p>`);
    para = [];
  };
  const closeList = () => {
    if (list) out.push(`</${list}>`);
    list = null;
  };
  for (const raw of md.split('\n')) {
    const line = raw.trimEnd();
    const h = /^(#{1,4})\s+(.*)$/.exec(line);
    const ul = /^\s*[-*·]\s+(.*)$/.exec(line);
    const ol = /^\s*\d+\.\s+(.*)$/.exec(line);
    if (h) {
      flushPara();
      closeList();
      const level = h[1]!.length;
      out.push(`<h${level}>${inline(h[2]!)}</h${level}>`);
    } else if (ul || ol) {
      flushPara();
      const kind = ul ? 'ul' : 'ol';
      if (list !== kind) {
        closeList();
        out.push(`<${kind}>`);
        list = kind;
      }
      out.push(`<li>${inline((ul ?? ol)![1]!)}</li>`);
    } else if (line.trim() === '') {
      flushPara();
      closeList();
    } else {
      closeList();
      para.push(line.trim());
    }
  }
  flushPara();
  closeList();
  return out.join('\n');
}

/** 메에일 웹 페이지 틀(크림 배경, 읽기 좋은 폭) */
export function page(title: string, body: string): string {
  return `<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)} · 메에일</title>
<style>
body{margin:0;background:#fff8ec;color:#5a4636;font-family:'Pretendard','Apple SD Gothic Neo','Noto Sans KR',system-ui,sans-serif;line-height:1.7}
main{max-width:720px;margin:0 auto;padding:24px 16px 64px}
h1{font-size:26px}h2{font-size:19px;margin-top:28px}h3{font-size:16px}
a{color:#3f6fb0}.card{background:#fff;border:2px solid #7a5c48;border-radius:16px;padding:16px;margin:16px 0}
label{display:block;margin:10px 0 4px}input,textarea{width:100%;box-sizing:border-box;border:1.5px solid #7a5c48;border-radius:10px;padding:8px;font:inherit}
button{margin-top:12px;background:#ffc9d6;border:2px solid #7a5c48;border-radius:12px;padding:10px 18px;font:inherit;font-weight:700;cursor:pointer}
.muted{color:#8c7a6b;font-size:14px}.ok{background:#e3f6ec;border-color:#2e9c78}
</style></head><body><main>${body}</main></body></html>`;
}
