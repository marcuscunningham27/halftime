<script lang="ts">
	// ProbabilityView: ESPN's win chance through the game, or its chance of covering the market spread or going over
	// the total. The away side reads from the top, each side's lead shaded in its colour; hover reads any moment.
	// shortcut: the market line only; the Swift app's own-line re-pricing (Probability.homeCover / over) isn't ported.
	import GlassPicker from '../GlassPicker.svelte';
	import { type Game, type Play, type Overview, probabilities, probabilityChart, ordinal, periodLabel, hex, type ChartPoint, type ProbabilityPoint } from '../espn';
	let { game, plays, overview }: { game: Game; plays: Play[]; overview: Overview } = $props();

	let points = $state<ProbabilityPoint[]>([]);
	// Reload whenever the play list grows, so a live chart keeps up.
	$effect(() => {
		plays.length;
		probabilities(game).then((p) => (points = p)).catch(() => {});
	});
	const chart = $derived(probabilityChart(points, plays, game.league));

	const modes = ['Win Probability', 'Cover Probability'] as const;
	const markets = ['Spread', 'Total'] as const;
	let mode = $state<(typeof modes)[number]>('Win Probability');
	let market = $state<(typeof markets)[number]>('Spread');
	const hasCover = $derived(chart.some((c) => c.homeCover !== undefined) && overview.odds?.homeSpread !== undefined);
	const isTotal = $derived(mode === 'Cover Probability' && market === 'Total');
	/** Values plotted from the top: away win, away cover, or over. */
	const series = $derived(
		chart.flatMap((c): { c: ChartPoint; v: number }[] => {
			if (mode === 'Win Probability' || !hasCover) return [{ c, v: 1 - c.homeWin }];
			const v = market === 'Spread' ? (c.homeCover === undefined ? undefined : 1 - c.homeCover) : c.over;
			return v === undefined ? [] : [{ c, v }];
		})
	);

	const W = 600, H = 220;
	const maxX = $derived(Math.max(1, series.at(-1)?.c.progress ?? 1));
	const x = (p: number) => (p / maxX) * W;
	const y = (v: number) => (1 - v) * H;
	const line = $derived(series.map((s, i) => `${i ? 'L' : 'M'}${x(s.c.progress)},${y(s.v)}`).join(' '));
	/** The area between the line and 50%, clipped to above (top side ahead) or below (bottom side ahead). */
	const area = $derived(series.length ? `M${x(series[0].c.progress)},${y(0.5)} ${series.map((s) => `L${x(s.c.progress)},${y(s.v)}`).join(' ')} L${x(series.at(-1)!.c.progress)},${y(0.5)} Z` : '');
	const n = $derived(game.league.regulationPeriods);
	let hovered = $state<{ c: ChartPoint; v: number } | undefined>();
	function hover(e: PointerEvent) {
		const svg = e.currentTarget as SVGSVGElement;
		const px = ((e.clientX - svg.getBoundingClientRect().left) / svg.clientWidth) * W;
		hovered = series.reduce((best, s) => (Math.abs(x(s.c.progress) - px) < Math.abs(x(best.c.progress) - px) ? s : best), series[0]);
	}
	// While hovering, everything reads the moment under the pointer instead of the latest.
	const current = $derived(hovered?.v ?? series.at(-1)?.v ?? 0.5);
	const topColor = $derived(isTotal ? '#30d158' : hex(game.away.team.color));
	const pct = (v: number) => `${Math.round(v * 100)}%`;
	const when = (c: ChartPoint) =>
		`${game.league.periodStyle === 'innings' ? `Inning ${c.period}` : c.period <= n ? ordinal(c.period) : periodLabel(game.league, c.period)} ${c.clock}`;
	const line_ = (top: boolean) => {
		const spread = overview.odds?.homeSpread, total = overview.odds?.overUnder;
		if (market === 'Total') return total === undefined ? undefined : String(total);
		if (spread === undefined) return;
		const l = top ? -spread : spread; // the away line is the home line flipped
		return l > 0 ? `+${l}` : l === 0 ? 'PK' : `−${-l}`;
	};
</script>

{#snippet sideRow(top: boolean, value: number)}
	{@const team = top ? game.away.team : game.home.team}
	<div class="side-row">
		{#if isTotal}<strong>{top ? '▲ Over' : '▼ Under'}</strong>{:else}<img src={team.logo} alt="" width="28" height="28" /><strong>{team.abbreviation}</strong>{/if}
		<span class="grow"></span>
		{#if mode === 'Cover Probability' && line_(top)}<span class="line-tag">{line_(top)}</span>{/if}
		<span class="big">{pct(value)}</span>
	</div>
{/snippet}

{#if chart.length}
	<section class="sports-card">
		<h2>Probabilities</h2>
		{#if hasCover}<div class="center"><GlassPicker options={[...modes]} bind:selected={mode} /></div>{/if}
		{#if mode === 'Cover Probability' && hasCover}<div class="center"><GlassPicker options={[...markets]} bind:selected={market} /></div>{/if}
		{@render sideRow(true, current)}
		<div class="plot">
			<svg viewBox="0 0 {W} {H}" preserveAspectRatio="none" role="img" aria-label="{mode}: {game.away.team.abbreviation} {pct(current)}" onpointermove={hover} onpointerleave={() => (hovered = undefined)}>
				<defs>
					<clipPath id="above"><rect width={W} height={y(0.5)} /></clipPath>
					<clipPath id="below"><rect y={y(0.5)} width={W} height={H - y(0.5)} /></clipPath>
				</defs>
				{#each Array.from({ length: n - 1 }, (_, i) => (i + 1) / n) as b}
					<line x1={x(b)} x2={x(b)} y1="0" y2={H} class="grid" />
				{/each}
				<line x1="0" x2={W} y1={y(0.5)} y2={y(0.5)} stroke="rgba(255,255,255,0.35)" vector-effect="non-scaling-stroke" />
				<path d={area} fill={topColor} fill-opacity="0.35" clip-path="url(#above)" />
				<path d={area} fill={hex(game.home.team.color)} fill-opacity="0.35" clip-path="url(#below)" />
				<path d={line} fill="none" stroke="rgba(255,255,255,0.85)" stroke-width="1.5" vector-effect="non-scaling-stroke" />
				{#if hovered}<line x1={x(hovered.c.progress)} x2={x(hovered.c.progress)} y1="0" y2={H} stroke="rgba(255,255,255,0.7)" vector-effect="non-scaling-stroke" />{/if}
			</svg>
			<div class="labels">
				{#each Array.from({ length: n }, (_, i) => i) as i}<span style:left="{(((i + 0.5) / n) / maxX) * 100}%">{ordinal(i + 1)}</span>{/each}
			</div>
			{#if hovered}
				<!-- "2nd 5:32 · WSH 10–13 SF" with the hovered chance. -->
				<div class="callout" style:left="{(x(hovered.c.progress) / W) * 100}%">
					<b>{when(hovered.c)}</b>
					<span>{isTotal ? 'Over' : game.away.team.abbreviation} {pct(hovered.v)} · {isTotal ? 'Under' : game.home.team.abbreviation} {pct(1 - hovered.v)}</span>
					<small>{game.away.team.abbreviation} {hovered.c.awayScore}–{hovered.c.homeScore} {game.home.team.abbreviation}</small>
				</div>
			{/if}
		</div>
		{@render sideRow(false, 1 - current)}
		{#if mode === 'Cover Probability'}<p class="footnote">ESPN's probabilities at the {overview.odds?.books.join(', ') || 'market'} line.</p>{/if}
	</section>
{/if}

<style>
	.center {
		display: flex;
		justify-content: center;
		margin-bottom: 8px;
	}
	.side-row {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 4px 0;
	}
	.grow {
		flex: 1;
	}
	.big {
		font: 700 30px/1 'Chakra Petch', sans-serif;
	}
	.line-tag {
		padding: 3px 8px;
		border-radius: 6px;
		background: rgba(255, 255, 255, 0.12);
		font-size: var(--subheadline);
	}
	.plot {
		position: relative;
		margin: 34px 0 22px;
	}
	.plot svg {
		display: block;
		width: 100%;
		height: 220px;
	}
	.grid {
		stroke: rgba(255, 255, 255, 0.2);
		stroke-dasharray: 2 3;
		vector-effect: non-scaling-stroke;
	}
	.labels span {
		position: absolute;
		bottom: -18px;
		transform: translateX(-50%);
		font-size: var(--caption);
		color: var(--secondary);
	}
	.callout {
		position: absolute;
		top: -34px;
		transform: translate(-50%, -50%);
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
	.callout small {
		color: var(--secondary);
	}
	.footnote {
		margin: 4px 0 0;
		font-size: var(--caption);
		color: var(--tertiary);
	}
</style>
