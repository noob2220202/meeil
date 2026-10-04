import { fmt, type Api, type AuditItem } from '../api';
import { Empty, Loaded, useLoad } from '../ui';

export function Audit({ api }: { api: Api }) {
  const [load, retry] = useLoad(() => api.get<{ logs: AuditItem[] }>('/admin/audit'), [api]);
  return (
    <section>
      <h2>감사 로그</h2>
      <Loaded load={load} retry={retry}>
        {({ logs }) =>
          logs.length === 0 ? (
            <Empty>기록이 없어요.</Empty>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>시각</th>
                  <th>관리자</th>
                  <th>동작</th>
                  <th>대상</th>
                  <th>내용</th>
                </tr>
              </thead>
              <tbody>
                {logs.map((l) => (
                  <tr key={l.id}>
                    <td>{fmt(l.createdAt)}</td>
                    <td>{l.admin}</td>
                    <td>{l.action}</td>
                    <td>
                      {l.targetType ? `${l.targetType} ${l.targetId?.slice(0, 8) ?? ''}` : '—'}
                    </td>
                    <td className="muted">{l.detail ? JSON.stringify(l.detail) : ''}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )
        }
      </Loaded>
    </section>
  );
}
