import type { Api, Dashboard as D } from '../api';
import { Loaded, useLoad } from '../ui';

export function Dashboard({ api }: { api: Api }) {
  const [load, retry] = useLoad(() => api.get<D>('/admin/dashboard'), [api]);
  return (
    <section>
      <h2>대시보드</h2>
      <Loaded load={load} retry={retry}>
        {(d) => {
          const max = Math.max(1, ...d.days.map((x) => x.letters));
          return (
            <>
              <div className="stats">
                <Stat label="가입자" value={d.users} sub={`오늘 +${d.newToday}`} />
                <Stat label="오늘 접속" value={d.activeToday} />
                <Stat label="오늘 편지" value={d.lettersToday} sub={`이동 중 ${d.inTransit}`} />
                <Stat
                  label="처리 대기 신고"
                  value={d.openReports}
                  href="#/reports"
                  warn={d.openReports > 0}
                />
                <Stat
                  label="미확인 사진"
                  value={d.unreviewed}
                  href="#/photos"
                  warn={d.unreviewed > 0}
                />
                <Stat label="오늘 먹힌 편지" value={d.eatenToday} />
              </div>
              <h3>최근 7일 편지 수</h3>
              <div className="bars" role="img" aria-label="최근 7일 일별 편지 수">
                {d.days.map((x) => (
                  <div key={x.date} className="bar">
                    <span className="bar-value">{x.letters}</span>
                    <div className="bar-fill" style={{ height: `${(x.letters / max) * 100}%` }} />
                    <span className="bar-label">{x.date.slice(5)}</span>
                  </div>
                ))}
              </div>
            </>
          );
        }}
      </Loaded>
    </section>
  );
}

function Stat({
  label,
  value,
  sub,
  href,
  warn,
}: {
  label: string;
  value: number;
  sub?: string;
  href?: string;
  warn?: boolean;
}) {
  const body = (
    <>
      <span className="stat-label">{label}</span>
      <strong className="stat-value">{value.toLocaleString('ko-KR')}</strong>
      {sub && <span className="stat-sub">{sub}</span>}
    </>
  );
  return href ? (
    <a className={`stat ${warn ? 'warn' : ''}`} href={href}>
      {body}
    </a>
  ) : (
    <div className="stat">{body}</div>
  );
}
