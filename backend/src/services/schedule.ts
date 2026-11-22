import { z } from "zod";

// Hours of the week in which an arrival area notifies ("tell me if the car leaves the
// garage between 23:00 and 6:00"), in the time zone of the platform (TIMEZONE).

const clock = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);

export const scheduleSchema = z.strictObject({
	/** ISO days of the week, Monday = 1; a window across midnight belongs to its start day */
	days: z.array(z.number().int().min(1).max(7)).min(1).max(7).transform(days => [...new Set(days)].sort()),
	from: clock,
	to: clock
});
export type Schedule = z.infer<typeof scheduleSchema>;

const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** Day of the week (Monday = 1) and minutes since midnight of an instant in a time zone */
export function localTime (at: Date, timeZone: string): { day: number; minutes: number } {
	const parts = new Intl.DateTimeFormat("en-GB", { timeZone, weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
		.formatToParts(at);
	const part = (type: string) => parts.find(item => item.type === type)!.value;
	return { day: WEEKDAYS.indexOf(part("weekday")) + 1, minutes: Number(part("hour")) * 60 + Number(part("minute")) };
}

const minutesOf = (value: string) => Number(value.slice(0, 2)) * 60 + Number(value.slice(3, 5));

/** Whether an instant falls in the schedule (always without one) */
export function inSchedule (schedule: Schedule | null, at: Date, timeZone: string): boolean {
	if (!schedule) return true;
	const { day, minutes } = localTime(at, timeZone);
	const from = minutesOf(schedule.from);
	const to = minutesOf(schedule.to);
	if (from === to) return schedule.days.includes(day);
	if (from < to) return schedule.days.includes(day) && minutes >= from && minutes < to;
	const previous = day === 1 ? 7 : day - 1;
	return (schedule.days.includes(day) && minutes >= from) || (schedule.days.includes(previous) && minutes < to);
}
