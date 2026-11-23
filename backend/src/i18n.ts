// Languages of the platform. The app localizes its own texts and the API errors (by
// code); the backend localizes only what leaves without the app: push notifications.

export const LOCALES = ["it", "en"] as const;
export type Locale = typeof LOCALES[number];
export const DEFAULT_LOCALE: Locale = "en";

export type NotificationKind =
	"motion" | "tilt" | "power_lost" | "low_battery" | "offline" | "online" | "geofence_enter" | "geofence_exit" |
	"phone_battery" | "long_stop" | "battery_health" | "maintenance" | "firmware" | "monthly_summary";

export interface NotificationData {
	device: string;
	area?: string;
	/** phone_battery: % */
	battery?: number;
	/** long_stop: hours chosen by the owner */
	hours?: number;
	/** battery_health: mean resting voltage of the car battery */
	voltage?: number;
	/** maintenance: kind and title of the deadline, soon or passed, days and km left */
	maintenance?: string;
	title?: string;
	due?: "soon" | "due";
	days?: number;
	km?: number;
	/** firmware: new version, installed by the tracker itself (AUTO_UPDATE) or by the owner */
	version?: string;
	automatic?: boolean;
	/** monthly_summary: month YYYY-MM and its totals */
	month?: string;
	distanceKm?: number;
	trips?: number;
	cost?: number | null;
	time: string;
}

type PluralForms = Partial<Record<Intl.LDMLPluralRule, string>> & { other: string };

/** Singular or plural of a count, "#" replaced by the number (Intl.PluralRules of the language) */
export function plural (language: Locale, count: number, forms: PluralForms, number = String(count)): string {
	const rule = new Intl.PluralRules(language).select(count);
	return (forms[rule] ?? forms.other).replace("#", number);
}

const MAINTENANCE: Record<Locale, Record<string, string>> = {
	it: { service: "Tagliando", inspection: "Revisione", insurance: "Assicurazione", tax: "Bollo", tyres: "Cambio gomme", other: "Scadenza" },
	en: { service: "Service", inspection: "Inspection", insurance: "Insurance", tax: "Road tax", tyres: "Tyre change", other: "Deadline" }
};

function maintenanceText (language: Locale, data: NotificationData): { title: string; body: string } {
	const name = data.title || MAINTENANCE[language][data.maintenance ?? "other"] || MAINTENANCE[language].other!;
	const it = language === "it";
	const parts: string[] = [];
	if (data.days !== undefined) {
		const n = Math.abs(data.days);
		const days = plural(language, n, it ? { one: "# giorno", other: "# giorni" } : { one: "# day", other: "# days" });
		parts.push(data.days > 0
			? (it ? `tra ${days}` : `in ${days}`)
			: data.days === 0 ? (it ? "oggi" : "today") : (it ? `scaduta da ${days}` : `overdue by ${days}`));
	}
	if (data.km !== undefined) {
		const n = Math.abs(data.km).toLocaleString(it ? "it-IT" : "en-GB", { useGrouping: "always" });
		parts.push(data.km > 0 ? (it ? `tra ${n} km` : `in ${n} km`) : (it ? `superata di ${n} km` : `${n} km over`));
	}
	const title = data.due === "due" ? (it ? `Scadenza: ${name}` : `Due: ${name}`) : (it ? `Scadenza vicina: ${name}` : `Coming up: ${name}`);
	return { title, body: `${data.device}: ${parts.join(it ? " o " : " or ")}` };
}

const MONTHS: Record<Locale, string[]> = {
	it: ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"],
	en: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
};

function summaryText (language: Locale, data: NotificationData): { title: string; body: string } {
	const it = language === "it";
	const format = (value: number, digits = 0) =>
		value.toLocaleString(it ? "it-IT" : "en-GB", { minimumFractionDigits: digits, maximumFractionDigits: digits, useGrouping: "always" });
	const name = MONTHS[language][Number(data.month!.slice(5, 7)) - 1]!;
	const trips = plural(language, data.trips ?? 0, it ? { one: "# viaggio", other: "# viaggi" } : { one: "# trip", other: "# trips" }, format(data.trips ?? 0));
	const parts = [`${format(data.distanceKm ?? 0)} km`, trips];
	if (data.cost != null) parts.push(it ? `${format(data.cost, 2)} € di costi` : `€${format(data.cost, 2)} of costs`);
	return { title: it ? `Il tuo mese di ${name}` : `Your ${name}`, body: parts.join(" · ") };
}

type Texts = Record<NotificationKind, (data: NotificationData & { clock: string }) => { title: string; body: string }>;

const TEXTS: Record<Locale, Texts> = {
	it: {
		motion: ({ device, clock }) => ({ title: "Movimento rilevato", body: `${device}, ore ${clock}` }),
		tilt: ({ device, clock }) => ({ title: "Auto sollevata o inclinata", body: `${device}, ore ${clock}` }),
		power_lost: ({ device, clock }) => ({ title: "Alimentazione scollegata", body: `${device}, ore ${clock}` }),
		low_battery: ({ device, clock }) => ({ title: "Batteria dell'auto scarica", body: `${device}, ore ${clock}` }),
		offline: ({ device, clock }) => ({ title: "Tracker non raggiungibile", body: `${device}, ultimo contatto ore ${clock}` }),
		online: ({ device, clock }) => ({ title: "Tracker di nuovo raggiungibile", body: `${device}, ore ${clock}` }),
		geofence_enter: ({ device, area, clock }) => ({ title: `${device} è arrivato`, body: `Entrato in ${area}, ore ${clock}` }),
		geofence_exit: ({ device, area, clock }) => ({ title: `${device} è partito`, body: `Uscito da ${area}, ore ${clock}` }),
		phone_battery: ({ device, battery, clock }) => ({ title: `${device}: batteria al ${battery}%`, body: `La posizione potrebbe interrompersi presto, ore ${clock}` }),
		long_stop: ({ device, hours, clock }) => ({
			title: `${device} è fermo da più di ${plural("it", hours ?? 1, { one: "un'ora", other: "# ore" })}`,
			body: `Fermo dalle ${clock}, fuori dalle tue aree`
		}),
		battery_health: ({ device, voltage, clock }) => ({
			title: "Batteria dell'auto da controllare",
			body: `${device}: tensione a riposo media ${voltage?.toFixed(2).replace(".", ",")} V (ore ${clock})`
		}),
		maintenance: data => maintenanceText("it", data),
		firmware: ({ device, version, automatic }) => ({
			title: `Nuovo firmware ${version}`,
			body: automatic ? `${device} lo installerà da solo entro un giorno` : `Installalo su ${device} dalla pagina del dispositivo`
		}),
		monthly_summary: data => summaryText("it", data)
	},
	en: {
		motion: ({ device, clock }) => ({ title: "Motion detected", body: `${device}, at ${clock}` }),
		tilt: ({ device, clock }) => ({ title: "Car lifted or tilted", body: `${device}, at ${clock}` }),
		power_lost: ({ device, clock }) => ({ title: "Power disconnected", body: `${device}, at ${clock}` }),
		low_battery: ({ device, clock }) => ({ title: "Car battery low", body: `${device}, at ${clock}` }),
		offline: ({ device, clock }) => ({ title: "Tracker unreachable", body: `${device}, last contact at ${clock}` }),
		online: ({ device, clock }) => ({ title: "Tracker reachable again", body: `${device}, at ${clock}` }),
		geofence_enter: ({ device, area, clock }) => ({ title: `${device} has arrived`, body: `Entered ${area} at ${clock}` }),
		geofence_exit: ({ device, area, clock }) => ({ title: `${device} has left`, body: `Left ${area} at ${clock}` }),
		phone_battery: ({ device, battery, clock }) => ({ title: `${device}: battery at ${battery}%`, body: `Location sharing may stop soon, at ${clock}` }),
		long_stop: ({ device, hours, clock }) => ({
			title: `${device} has been stopped for over ${plural("en", hours ?? 1, { one: "an hour", other: "# hours" })}`,
			body: `Stopped since ${clock}, outside your areas`
		}),
		battery_health: ({ device, voltage, clock }) => ({
			title: "Car battery needs a check",
			body: `${device}: mean resting voltage ${voltage?.toFixed(2)} V (at ${clock})`
		}),
		maintenance: data => maintenanceText("en", data),
		firmware: ({ device, version, automatic }) => ({
			title: `New firmware ${version}`,
			body: automatic ? `${device} will install it by itself within a day` : `Install it on ${device} from the page of the device`
		}),
		monthly_summary: data => summaryText("en", data)
	}
};

export function isLocale (value: unknown): value is Locale {
	return typeof value === "string" && (LOCALES as readonly string[]).includes(value);
}

/** Text of a push notification in the language of the user */
export function notificationText (locale: string | null, kind: NotificationKind, data: NotificationData, timeZone: string): { title: string; body: string } {
	const language = isLocale(locale) ? locale : DEFAULT_LOCALE;
	const clock = new Date(data.time).toLocaleTimeString(language === "it" ? "it-IT" : "en-GB", { hour: "2-digit", minute: "2-digit", timeZone });
	return TEXTS[language][kind]({ ...data, clock });
}
