export function formatPrice(value: number): string {
  return value.toLocaleString("ko-KR") + "원";
}

export function formatTimeAgo(iso: string, now: Date = new Date()): string {
  const created = new Date(iso);
  const diffMs = now.getTime() - created.getTime();
  if (Number.isNaN(diffMs) || diffMs < 0) return "방금 전";

  const sec = Math.floor(diffMs / 1000);
  if (sec < 60) return "방금 전";
  const min = Math.floor(sec / 60);
  if (min < 60) return `${min}분 전`;
  const hour = Math.floor(min / 60);
  if (hour < 24) return `${hour}시간 전`;
  const day = Math.floor(hour / 24);
  return `${day}일 전`;
}

export function formatTime(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "-";
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  return `${hh}:${mm}`;
}

export function shortOrderNumber(id: string): string {
  // UUID에서 마지막 4자리만 추출하여 호출번호로 사용
  const cleaned = id.replace(/-/g, "");
  return cleaned.slice(-4).toUpperCase();
}
