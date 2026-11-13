<script lang="ts">
	// FantasySeasonView: your starters' actual points against projection over the completed weeks, where the gap comes
	// from (by position and by player), and the league standings.
	import { type SeasonTrend, type Standing, type WeekResult, record } from './fantasy';
	let { trend, standings }: { trend: SeasonTrend; standings: Standing[] } = $props();

	const number = (v: number) => v.toFixed(1);
	const signed = (v: number) => (v >= 0 ? '+' : '−') + number(Math.abs(v));
	const gapPerWeek = $derived(trend.actualPerWeek - trend.projectedPerWeek);
	const leak = $derived(trend.gapByPosition[0]);
	/** "Actual points are running +3.9 per week against projection. QB beats projection most (+7.3 per start); RB is the biggest leak (−2.5)." */
	const summary = $derived.by(() => {
		let text = `Actual points are running ${signed(gapPerWeek)} per week against projection.`;
		const best = trend.gapByPosition.at(-1), worst = trend.gapByPosition[0];
		if (best && worst && best.position !== worst.position)
			text += ` ${best.position} beats projection most (${signed(best.gap)} per start); ${worst.position} is the biggest leak (${signed(worst.gap)}).`;
		return text;
	});

	// The chart: half a week of room each side, values padded so labels fit.
	const W = 640, H = 260, pad = { l: 36, r: 12, t: 30, b: 26 };
	const weeks = $derived(trend.weeks);
	const values = $derived(weeks.flatMap((w) => [w.actual, w.projected]));
	const lo = $derived(Math.floor(Math.min(...values, 0) / 20) * 20);
	const hi = $derived(Math.ceil(Math.max(...values, 20) / 20) * 20);
	const last = $derived(weeks.at(-1)?.week ?? 1);
	const x = (week: number) => pad.l + ((week - 0.5) / last) * (W - pad.l - pad.r);
	const y = (v: number) => pad.t + (1 - (v - lo) / (hi - lo || 1)) * (H - pad.t - pad.b);
	const line = (pick: (w: WeekResult) => number) => weeks.map((w, i) => `${i ? 'L' : 'M'}${x(w.week)},${y(pick(w))}`).join(' ');
	const ticks = $derived(Array.from({ length: Math.round((hi - lo) / 20) + 1 }, (_, i) => lo + i * 20));
	let hovered = $state<WeekResult | undefined>();
	function hover(e: PointerEvent) {
		const svg = e.currentTarget as SVGSVGElement;
		const px = ((e.clientX - svg.getBoundingClientRect().left) / svg.clientWidth) * W;
		hovered = weeks.reduce((best, w) => (Math.abs(x(w.week) - px) < Math.abs(x(best.week) - px) ? w : best), weeks[0]);
	}
	const maxPoints = $derived(Math.max(...standings.map((s) => s.pointsFor), 1));
</script>

{#snippet tile(title: string, value: string, caption: string, color = 'var(--label)')}
	<div class="tile">
		<span class="tile-title">{title}</span>
		<span class="tile-value" style:color>{value}</span>
		<span class="caption">{caption}</span>
	</div>
{/snippet}

{#snippet bars(rows: { label: string; value: number }[])}
	{@const scale = Math.max(...rows.map((r) => Math.abs(r.value)), 0.1)}
	<div class="bars">
		{#each rows as row}
			<div class="bar-row" role="img" aria-label="{row.label} {signed(row.value)}">
				<span class="bar-label">{row.label}</span>
				<span class="track">
					<i class="zero"></i>
					<i class="fill" class:up={row.value >= 0} style:width="max(2px, {(Math.abs(row.value) / scale) * 50}%)"></i>
				</span>
				<span class="bar-value">{signed(row.value)}</span>
			</div>
		{/each}
	</div>
{/snippet}

{#if weeks.length === 0}
	<div class="empty-state">No Completed Weeks. Season numbers appear once a week has been played.</div>
{:else}
	<section class="sports-card"><h2>Season Trend</h2><p class="summary">{summary}</p></section>
	<div class="tiles">
		{@render tile('Actual per week', number(trend.actualPerWeek), 'Completed weeks, starters only')}
		{@render tile('Projected per week', number(trend.projectedPerWeek), 'Same weeks')}
		{@render tile('Gap per week', signed(gapPerWeek), 'Actual minus projected', gapPerWeek >= 0 ? '#30d158' : '#ff453a')}
		{#if leak && leak.gap < 0}
			{@render tile('Biggest leak', leak.position, `${signed(leak.gap)} per start vs projection`, '#ff453a')}
		{:else}
			{@render tile('Biggest leak', 'None', 'Every position at or above projection')}
		{/if}
	</div>

	<section class="sports-card">
		<h2>Weekly Points: Projected vs Actual</h2>
		<div class="legend"><span><i style:background="#8e8e93"></i>Projected</span><span><i style:background="#30d158"></i>Actual</span></div>
		<svg class="chart" viewBox="0 0 {W} {H}" role="img" aria-label="Weekly points chart" onpointermove={hover} onpointerleave={() => (hovered = undefined)}>
			{#each ticks as t}
				<line x1={pad.l} x2={W - pad.r} y1={y(t)} y2={y(t)} stroke="rgba(255,255,255,0.08)" />
				<text class="axis" x={pad.l - 6} y={y(t)} text-anchor="end" dominant-baseline="central">{t}</text>
			{/each}
			{#each weeks as w}<text class="axis" x={x(w.week)} y={H - 8} text-anchor="middle">Wk {w.week}</text>{/each}
			{#if hovered}<line x1={x(hovered.week)} x2={x(hovered.week)} y1={pad.t - 6} y2={H - pad.b} stroke="rgba(255,255,255,0.5)" />{/if}
			<path d={line((w) => w.projected)} fill="none" stroke="#8e8e93" stroke-width="1.5" />
			<path d={line((w) => w.actual)} fill="none" stroke="#30d158" stroke-width="2.5" />
			{#each weeks as w}
				<circle cx={x(w.week)} cy={y(w.projected)} r="2.8" fill="#8e8e93" />
				<circle cx={x(w.week)} cy={y(w.actual)} r="3.8" fill="#30d158" />
				{#if w !== hovered}
					<text class="point" x={x(w.week)} y={y(w.actual) + (w.actual >= w.projected ? -9 : 15)} text-anchor="middle">{number(w.actual)}</text>
				{/if}
			{/each}
		</svg>
		{#if hovered}
			<!-- "Week 3 · Actual 67.7 · Projected 102.5 · −34.8" -->
			<div class="callout" style:left="{(x(hovered.week) / W) * 100}%">
				<b>Week {hovered.week}</b>
				<span>Actual {number(hovered.actual)} · Projected {number(hovered.projected)}</span>
				<b style:color={hovered.actual >= hovered.projected ? '#30d158' : '#ff453a'}>{signed(hovered.actual - hovered.projected)}</b>
			</div>
		{/if}
	</section>

	<div class="pair">
		<section class="sports-card">
			<h2>Average Gap by Position</h2>
			<p class="caption note">Actual minus projected, per start. Right of zero beats projection.</p>
			{@render bars(trend.gapByPosition.map((g) => ({ label: g.position, value: g.gap })))}
		</section>
		<section class="sports-card">
			<h2>Total Gap by Starter</h2>
			<p class="caption note">Points above or below projection across all starts.</p>
			{@render bars(trend.gapByStarter.map((g) => ({ label: g.name, value: g.gap })))}
		</section>
	</div>

	{#if standings.length}
		<section class="sports-card">
			<h2>League Standings</h2>
			<p class="caption note">By record, then points for. Your row is highlighted.</p>
			<div class="standing head"><span class="rank">Rank</span><span class="team">Team</span><span class="rec">Record</span><span class="pf">Points For</span></div>
			{#each standings as s, i (s.id)}
				<!-- Your row floats as a green-tinted glass capsule. -->
				<div class="standing" class:mine={s.isMine}>
					<span class="rank">{i + 1}</span>
					<span class="team">{s.teamName}</span>
					<span class="rec">{record(s)}</span>
					<span class="pf"><i style:width="{(s.pointsFor / maxPoints) * 100}%"></i><b>{number(s.pointsFor)}</b></span>
				</div>
			{/each}
		</section>
	{/if}
{/if}

<style>
	.summary {
		margin: 4px 0;
		user-select: text;
		-webkit-user-select: text;
	}
	.tiles {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: 12px;
	}
	.tile {
		display: flex;
		flex-direction: column;
		gap: 6px;
		padding: 14px;
		border-radius: 18px;
		background: rgba(0, 0, 0, 0.38);
		box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.1);
	}
	.tile-title {
		font-size: var(--caption);
		font-weight: 600;
		text-transform: uppercase;
		color: var(--secondary);
	}
	.tile-value {
		font: 700 28px/1 'Chakra Petch', sans-serif;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.caption {
		font-size: var(--caption);
		color: var(--secondary);
	}
	.note {
		margin: 0 0 8px;
	}
	.sports-card {
		position: relative;
	}
	.legend {
		display: flex;
		gap: 14px;
		font-size: var(--caption);
		color: var(--secondary);
		margin: 4px 0;
	}
	.legend span {
		display: flex;
		align-items: center;
		gap: 5px;
	}
	.legend i {
		width: 8px;
		height: 8px;
		border-radius: 50%;
	}
	.chart {
		display: block;
		width: 100%;
		height: auto;
	}
	.axis {
		font-size: 10px;
		fill: var(--secondary);
	}
	.point {
		font-size: 10px;
		font-weight: 600;
		fill: var(--label);
	}
	.callout {
		position: absolute;
		top: 64px;
		transform: translateX(-50%);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		padding: 5px 8px;
		border-radius: 8px;
		background: rgba(0, 0, 0, 0.75);
		font-size: var(--caption);
		white-space: nowrap;
		pointer-events: none;
	}
	.pair {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 12px;
		align-items: start;
	}
	.bars {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.bar-row {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: var(--caption);
	}
	.bar-label {
		width: 110px;
		text-align: right;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.track {
		position: relative;
		flex: 1;
		height: 14px;
	}
	.zero {
		position: absolute;
		left: 50%;
		top: 0;
		bottom: 0;
		width: 1px;
		background: rgba(255, 255, 255, 0.2);
	}
	/* Red bars grow left of zero, green ones right. */
	.fill {
		position: absolute;
		top: 0;
		bottom: 0;
		right: 50%;
		border-radius: 3px;
		background: #ff453a;
	}
	.fill.up {
		right: auto;
		left: 50%;
		background: #30d158;
	}
	.bar-value {
		width: 44px;
		text-align: right;
		color: var(--secondary);
	}
	.standing {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 7px 10px;
		border-radius: 999px;
		font-size: var(--subheadline);
	}
	.standing.head {
		font-size: var(--caption);
		font-weight: 600;
		color: var(--secondary);
		padding-block: 6px;
	}
	.standing.mine {
		font-weight: 700;
		background: rgba(48, 209, 88, 0.22);
		box-shadow: inset 0 0 0 0.5px rgba(255, 255, 255, 0.25), inset 0 1px 0 rgba(255, 255, 255, 0.15);
		backdrop-filter: blur(12px);
		-webkit-backdrop-filter: blur(12px);
	}
	.rank {
		width: 36px;
	}
	.team {
		flex: 1;
		min-width: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.rec {
		width: 56px;
	}
	.pf {
		position: relative;
		width: 220px;
	}
	.pf i {
		position: absolute;
		inset: 0 auto 0 0;
		border-radius: 999px;
		background: rgba(255, 255, 255, 0.1);
	}
	.pf b {
		position: relative;
		font-weight: inherit;
		padding: 2px 6px;
	}
	@media (max-width: 700px) {
		.tiles { grid-template-columns: 1fr 1fr; }
		.pair { grid-template-columns: 1fr; }
		.pf { width: 120px; }
	}
</style>
