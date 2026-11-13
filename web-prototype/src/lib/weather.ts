// Weather at the venue, as OpenMeteo.swift: free and keyless. The Swift app finds the venue with Apple's MapKit;
// here Open-Meteo's own geocoder does it, which also gives the venue's time zone.
import { getJSON } from './platform';

export type Place = { latitude: number; longitude: number; timeZone?: string };
export type Weather = { celsius: number; code: number; windKmh?: number; rainChance?: number };

/** The venue's city, preferring the result in its state when ESPN gives one ("NJ" matches New Jersey's initials). */
export async function locate(city: string, state?: string): Promise<Place | undefined> {
	const d = await getJSON(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(city)}&count=10`);
	const results: any[] = d.results ?? [];
	const initials = (s: string) => s.split(/\s+/).map((w) => w[0]).join('').toUpperCase();
	const r = results.find((r) => state && r.admin1 && (r.admin1 === state || initials(r.admin1) === state.toUpperCase())) ?? results[0];
	return r && { latitude: r.latitude, longitude: r.longitude, timeZone: r.timezone };
}

/** The forecast (or recent history) for the hour nearest the start. */
export async function weather(place: Place, at: Date): Promise<Weather | undefined> {
	const day = at.toISOString().slice(0, 10);
	const q = `latitude=${place.latitude}&longitude=${place.longitude}&hourly=temperature_2m,weather_code,wind_speed_10m,precipitation_probability&start_date=${day}&end_date=${day}&timezone=GMT`;
	const h = (await getJSON(`https://api.open-meteo.com/v1/forecast?${q}`)).hourly;
	if (!h?.time?.length) return;
	const times: number[] = h.time.map((t: string) => Date.parse(`${t}:00Z`));
	const i = times.reduce((best, t, j) => (Math.abs(t - at.getTime()) < Math.abs(times[best] - at.getTime()) ? j : best), 0);
	if (h.temperature_2m[i] == null || h.weather_code[i] == null) return;
	return { celsius: h.temperature_2m[i], code: h.weather_code[i], windKmh: h.wind_speed_10m?.[i] ?? undefined, rainChance: h.precipitation_probability?.[i] ?? undefined };
}

/** Plain-English summary of the WMO code, with an icon standing in for the SF Symbol. */
export function describe(code: number): [string, string] {
	if (code === 0) return ['Clear', '☀️'];
	if (code <= 2) return ['Partly cloudy', '⛅️'];
	if (code === 3) return ['Overcast', '☁️'];
	if (code === 45 || code === 48) return ['Fog', '🌫️'];
	if (code >= 51 && code <= 57) return ['Drizzle', '🌦️'];
	if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return ['Rain', '🌧️'];
	if ((code >= 71 && code <= 77) || code === 85 || code === 86) return ['Snow', '🌨️'];
	if (code >= 95) return ['Thunderstorms', '⛈️'];
	return ['Partly cloudy', '⛅️'];
}
