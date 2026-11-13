<script lang="ts">
	// FantasyNewsView: who's out or on bye, the weeks ahead where byes leave a starting slot nobody can fill, an injury
	// report across the roster, and the latest news.
	import { type Team, type Player, type Calendar, type News, type CoverSlot, severity, lineupCover, needsCover } from './fantasy';
	let { team, byes, week, calendar, news, provider }: {
		team: Team; byes: Record<string, number>; week: number; calendar?: Calendar; news: Record<string, News[]>; provider: string;
	} = $props();

	const players = $derived([...team.lineup.flatMap((s) => (s.player ? [s.player] : [])), ...team.bench]);
	const onBye = (p: Player) => !!p.team && byes[p.team] === week;
	const sev = (p: Player) => severity(p.injury);

	/** "1 out (Jacory Croskey-Merritt) · 1 on bye (Sam LaPorta) · 12 healthy" */
	const summary = $derived.by(() => {
		const hurt = players.filter((p) => sev(p) >= 3);
		const questionable = players.filter((p) => sev(p) === 1 || sev(p) === 2);
		const bye = players.filter((p) => onBye(p) && sev(p) < 3);
		const names = (list: Player[]) => list.map((p) => p.name).join(', ');
		return [
			hurt.length && `${hurt.length} out (${names(hurt)})`,
			questionable.length && `${questionable.length} questionable (${names(questionable)})`,
			bye.length && `${bye.length} on bye (${names(bye)})`,
			`${Math.max(0, players.length - hurt.length - questionable.length - bye.length)} healthy`
		].filter(Boolean).join(' · ');
	});

	// Bye weeks: each week from now until the playoffs. Out misses this week only; IR and the like about four weeks.
	// shortcut: injured players' timelines come from status alone; news-based return dates would be better.
	type Plan = { week: number; cover: CoverSlot[]; teamsOnBye: string[] };
	const plans = $derived.by((): Plan[] => {
		const lastWeek = (calendar?.playoffWeekStart ?? 15) - 1;
		return Array.from({ length: Math.max(0, lastWeek - week + 1) }, (_, i) => week + i).map((w) => ({
			week: w,
			cover: lineupCover(team.lineup, team.bench, (p) => {
				if (p.team && byes[p.team] === w) return false;
				if (sev(p) >= 4) return w >= week + 4;
				return w !== week || sev(p) < 3;
			}),
			teamsOnBye: Object.keys(byes).filter((t) => byes[t] === w).sort()
		}));
	});
	function status(cover: CoverSlot[]): [string, string] {
		const holes = cover.filter((s) => !s.filledBy).length;
		if (holes) return [`${holes} hole${holes === 1 ? '' : 's'}`, '#ff453a'];
		return cover.some(needsCover) ? ['Covered', '#ffd60a'] : ['Clear', '#30d158'];
	}
	/** Starters who can't play (and empty slots); a starter who just moves to another slot isn't missing. */
	const missing = (cover: CoverSlot[]) =>
		cover.filter(needsCover).flatMap((s) => (!s.starter ? [`${s.label} slot empty`] : cover.some((c) => c.filledBy?.id === s.starter!.id) ? [] : [`${s.starter.name} (${s.label})`]));

	function tag(p: Player): [string, string] {
		if (onBye(p) && !p.injury) return ['Bye', '#8e8e93'];
		const s = sev(p);
		return s === 0 ? ['Healthy', '#30d158'] : s === 1 ? ['Q', '#ffd60a'] : s === 2 ? ['D', '#ff9f0a'] : [p.injury?.status ?? 'Out', '#ff453a'];
	}
	// Most serious first: injuries, then byes, then healthy; by name within each.
	const rank = (p: Player) => (p.injury ? sev(p) : onBye(p) ? 0 : -1);
	const report = $derived([...players].sort((a, b) => rank(b) - rank(a) || a.name.localeCompare(b.name)));

	/** In the desktop app a link would replace the app's own page, so stories open in the default browser instead. */
	async function openStory(e: MouseEvent, url: string) {
		if (!('__TAURI_INTERNALS__' in window)) return;
		e.preventDefault();
		(await import('@tauri-apps/plugin-opener')).openUrl(url);
	}

	const ago = (d: Date) => {
		const hours = Math.round((Date.now() - d.getTime()) / 3_600_000);
		return new Intl.RelativeTimeFormat([], { numeric: 'auto' }).format(hours < 24 ? -hours : -Math.round(hours / 24), hours < 24 ? 'hour' : 'day');
	};
	const latest = $derived(
		players.flatMap((p) => (news[p.id] ?? []).filter((n) => Date.now() - n.published.getTime() < 4 * 86_400_000).map((n) => ({ p, n }))).sort((a, b) => b.n.published.getTime() - a.n.published.getTime())
	);
</script>

{#snippet pill(text: string, color: string)}
	<span class="pill" style:--c={color}>{text}</span>
{/snippet}

<section class="sports-card">
	<h2>Roster News</h2>
	<p class="summary">{summary}</p>
	<p class="caption">Statuses come from {provider}. News is from ESPN’s fantasy feed (Rotowire).</p>
</section>

{#if plans.length}
	<section class="sports-card">
		<h2>Bye Weeks</h2>
		<p class="caption note">Clear: nobody missing. Covered: your bench fills every gap. Hole: a slot needs a pickup. Outlined = trade-deadline week.</p>
		<div class="weeks">
			{#each plans as plan}
				{@const [text, color] = status(plan.cover)}
				<div class="week" style:--c={color} class:deadline={plan.week === calendar?.tradeDeadlineWeek}>
					<b>Wk {plan.week}</b>
					<span><i></i>{text}</span>
				</div>
			{/each}
		</div>
		<table>
			<thead><tr><th>Week</th><th>Status</th><th>Who’s missing</th><th>Covered by</th></tr></thead>
			<tbody>
				{#each plans as plan}
					{@const [text, color] = status(plan.cover)}
					{@const changes = plan.cover.filter(needsCover)}
					<tr>
						<td>
							{plan.week}{plan.week === calendar?.tradeDeadlineWeek ? ' · Deadline' : ''}
							{#if plan.teamsOnBye.length}<small>Byes: {plan.teamsOnBye.join(', ')}</small>{/if}
						</td>
						<td><span class="status" style:--c={color}><i></i>{text}</span></td>
						<td>{#each missing(plan.cover) as m}<div>{m}</div>{:else}–{/each}</td>
						<td>
							{#each changes as s}
								<div class:hole={!s.filledBy}>{s.label}: {s.filledBy?.name ?? 'pickup needed'}</div>
							{:else}<span class="dim">–</span>{/each}
						</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</section>
{/if}

<section class="sports-card">
	<h2>Injury Report</h2>
	<p class="caption note">Every rostered player, most serious first.</p>
	{#each report as p, i (p.id)}
		{#if i > 0}<hr />{/if}
		{@const [text, color] = tag(p)}
		{@const item = news[p.id]?.[0]}
		<div class="report">
			<div class="body">
				<span><strong>{p.name}</strong> <span class="caption">{[p.team, p.position].filter(Boolean).join(' - ')}</span></span>
				{#if p.injury?.detail}<span class="caption">{p.injury.detail}</span>{/if}
				{#if item}
					<span class="headline">{item.headline}</span>
					<small>{item.source} · {ago(item.published)}</small>
				{/if}
			</div>
			{@render pill(text, color)}
		</div>
	{/each}
</section>

{#if latest.length}
	<section class="sports-card">
		<h2>Latest Roster News</h2>
		<p class="caption note">The last few days of news on your players.</p>
		{#each latest as { p, n }, i (n.id + p.id)}
			{#if i > 0}<hr />{/if}
			<div class="story">
				<span class="caption">{p.name} · {n.source} · {ago(n.published)}</span>
				{#if n.url}<a href={n.url} target="_blank" rel="noopener noreferrer" onclick={(e) => openStory(e, n.url!)}><strong>{n.headline}</strong></a>{:else}<strong>{n.headline}</strong>{/if}
				{#if n.story}<p class="caption clamp">{n.story}</p>{/if}
			</div>
		{/each}
	</section>
{/if}

<style>
	.summary {
		margin: 4px 0;
	}
	.caption {
		font-size: var(--caption);
		color: var(--secondary);
		margin: 0;
	}
	.note {
		margin-bottom: 8px;
	}
	small {
		display: block;
		font-size: var(--caption);
		color: var(--tertiary);
	}
	.dim {
		color: var(--secondary);
	}
	.weeks {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(76px, 1fr));
		gap: 8px;
		margin-bottom: 10px;
	}
	.week {
		display: flex;
		flex-direction: column;
		gap: 3px;
		padding: 8px;
		border-radius: 10px;
		background: color-mix(in srgb, var(--c) 8%, transparent);
		font-size: var(--caption);
	}
	.week.deadline {
		box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.7);
	}
	.week span, .status {
		display: flex;
		align-items: center;
		gap: 4px;
		color: var(--c);
	}
	.week i, .status i {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: var(--c);
	}
	table {
		width: 100%;
		border-collapse: collapse;
		font-size: var(--caption);
	}
	th {
		text-align: left;
		font-weight: 600;
		color: var(--secondary);
		padding: 6px 14px 6px 0;
	}
	td {
		vertical-align: top;
		padding: 7px 14px 7px 0;
		border-top: 1px solid var(--separator);
	}
	.hole {
		color: #ff453a;
	}
	.report {
		display: flex;
		align-items: flex-start;
		gap: 12px;
		padding: 8px 0;
	}
	.body {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 3px;
		font-size: var(--subheadline);
	}
	.headline {
		font-size: var(--caption);
	}
	.pill {
		padding: 1px 6px;
		border-radius: 999px;
		font-size: var(--caption);
		font-weight: 700;
		color: var(--c);
		background: color-mix(in srgb, var(--c) 18%, transparent);
	}
	.story {
		display: flex;
		flex-direction: column;
		gap: 3px;
		padding: 8px 0;
	}
	.story a:hover {
		text-decoration: underline;
	}
	.clamp {
		display: -webkit-box;
		-webkit-line-clamp: 4;
		line-clamp: 4;
		-webkit-box-orient: vertical;
		overflow: hidden;
	}
</style>
