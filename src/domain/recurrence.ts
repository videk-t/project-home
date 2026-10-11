export type RecurrenceType = 'none' | 'daily' | 'weekly' | 'monthly' | 'interval';
export type RecurrenceAnchor = 'scheduled' | 'completion';
export type RecurrenceConfig = { interval?: number; unit?: 'days' | 'weeks' | 'months' };

const addMonths = (date: Date, months: number) => { const copy = new Date(date); const day = copy.getUTCDate(); copy.setUTCDate(1); copy.setUTCMonth(copy.getUTCMonth() + months); copy.setUTCDate(Math.min(day, new Date(Date.UTC(copy.getUTCFullYear(), copy.getUTCMonth() + 1, 0)).getUTCDate())); return copy; };
export function nextDueAt(scheduledDueAt: Date, completedAt: Date, type: RecurrenceType, anchor: RecurrenceAnchor, config: RecurrenceConfig = {}): Date | null {
  if (type === 'none') return null;
  const basis = anchor === 'completion' ? completedAt : scheduledDueAt;
  const interval = config.interval ?? 1;
  if (interval < 1) throw new Error('Interval must be positive');
  if (type === 'daily') return new Date(basis.getTime() + interval * 86_400_000);
  if (type === 'weekly') return new Date(basis.getTime() + interval * 7 * 86_400_000);
  if (type === 'monthly') return addMonths(basis, interval);
  if (type === 'interval') { const unit = config.unit ?? 'days'; return unit === 'months' ? addMonths(basis, interval) : new Date(basis.getTime() + interval * (unit === 'weeks' ? 7 : 1) * 86_400_000); }
  return null;
}
export function nextRotationIndex(current: number, memberCount: number) { if (!Number.isInteger(current) || memberCount < 1) throw new Error('Rotation needs at least one member'); return (current + 1) % memberCount; }
export function snoozeUntil(now: Date, option: 'hour' | 'tonight' | 'tomorrow'): Date { const target = new Date(now); if (option === 'hour') return new Date(now.getTime() + 3_600_000); if (option === 'tonight') { target.setHours(19, 0, 0, 0); if (target <= now) target.setDate(target.getDate() + 1); return target; } target.setDate(target.getDate() + 1); target.setHours(9, 0, 0, 0); return target; }
