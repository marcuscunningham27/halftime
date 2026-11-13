<script lang="ts">
	// MenuBarPopover.swift: today's live and upcoming games for what you follow, as glass cards, plus Open Halftime and
	// Settings. A borderless window under the menu-bar icon (above the tray on Windows); the main window's poller
	// sends it the games, so it fetches nothing itself.
	import { emitTo, listen } from '@tauri-apps/api/event';
	import { getCurrentWindow, LogicalSize } from '@tauri-apps/api/window';
	import { headlineStatus, isLosing, type Game, type Competitor } from '$lib/espn';

	let games = $state<Game[]>([]);
	let nothing = $state(false);
	let panel: HTMLElement;

	$effect(() => {
		const win = getCurrentWindow();
		const stops = [
			// Dates arrive as strings over the event bridge.
			listen<{ games: Game[]; nothing: boolean }>('tray-games', ({ payload }) => {
				games = payload.games.map((g) => ({ ...g, startDate: new Date(g.startDate) }));
				nothing = payload.nothing;
			}),
			// Clicking anywhere else closes it, as a menu-bar panel does.
			win.onFocusChanged(({ payload: focused }) => {
				if (!focused) win.hide().then(() => emitTo('main', 'tray-hidden'));
			})
		];
		emitTo('main', 'tray-ready');
		return () => stops.forEach((s) => s.then((stop) => stop()));
	});

	// The window is as tall as the cards, up to the scroll cap.
	$effect(() => {
		const observer = new ResizeObserver(() => getCurrentWindow().setSize(new LogicalSize(360, Math.ceil(panel.offsetHeight))));
		observer.observe(panel);
		return () => observer.disconnect();
	});

	const open = async (path?: string) => {
		await getCurrentWindow().hide();
		emitTo('main', 'tray-open', path ?? null);
	};
	const gameLink = (g: Game) => `/game?league=${g.league.id}&id=${g.id}&day=${new Date(g.startDate).setHours(0, 0, 0, 0)}`;
</script>

<svelte:head><title>Halftime</title></svelte:head>

{#snippet line(g: Game, c: Competitor)}
	<span class="line" class:dim={isLosing(g, c)}>
		<img src={c.team.logo} alt="" width="22" height="22" />
		<b>{c.team.abbreviation}</b>
		<span class="secondary name">{c.team.shortName}</span>
		{#if g.status === 'scheduled'}<span class="secondary small">{c.record ?? ''}</span>{:else}<span class="score">{c.score ?? ''}</span>{/if}
	</span>
{/snippet}

<div class="panel" bind:this={panel}>
	<h1>Today</h1>
	{#if nothing}
		<div class="empty">
			<svg viewBox="0 0 20 20" width="28" height="28" aria-hidden="true"><path d="M10 2.5l2.2 4.6 5 .6-3.7 3.5 1 5L10 13.8 5.5 16.2l1-5L2.8 7.7l5-.6z" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round" /></svg>
			<strong>Nothing Followed Yet</strong>
			<span class="secondary">Star a team or league in Halftime to see its games here.</span>
		</div>
	{:else if games.length === 0}
		<div class="empty">
			<img src="/tray-template.png" alt="" width="40" class="court" />
			<strong>No Live or Upcoming Games</strong>
		</div>
	{:else}
		<div class="list">
			{#each games as g (g.id)}
				<button class="card glass" onclick={() => open(gameLink(g))}>
					<span class="teams">{@render line(g, g.away)}{@render line(g, g.home)}</span>
					<span class="status">{#if g.status === 'live'}<span class="dot"></span>{/if}{headlineStatus(g)}</span>
				</button>
			{/each}
		</div>
	{/if}
	<div class="actions">
		<button class="glass wide" onclick={() => open()}>
			<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><rect x="1.5" y="2.5" width="13" height="11" rx="2" fill="none" stroke="currentColor" stroke-width="1.3" /><path d="M1.5 5.5h13" stroke="currentColor" stroke-width="1.3" /></svg>
			Open Halftime
		</button>
		<button class="glass gear" aria-label="Settings" onclick={() => open('/settings')}>
			<svg viewBox="0 0 20 20" width="16" height="16" aria-hidden="true"><path d="M10 6.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7zm7 4.6v-2.2l-2-.4a5 5 0 0 0-.6-1.4l1.1-1.7-1.5-1.5-1.7 1.1a5 5 0 0 0-1.4-.6L10.5 2h-2.2l-.4 2a5 5 0 0 0-1.4.6L4.8 3.5 3.3 5l1.1 1.7a5 5 0 0 0-.6 1.4L2 8.9v2.2l2 .4c.1.5.3 1 .6 1.4l-1.1 1.7 1.5 1.5 1.7-1.1c.4.3.9.5 1.4.6l.4 2h2.2l.4-2c.5-.1 1-.3 1.4-.6l1.7 1.1 1.5-1.5-1.1-1.7c.3-.4.5-.9.6-1.4z" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round" /></svg>
		</button>
	</div>
</div>

<style>
	/* The window's own frosted background (windowEffects) shows through. */
	:global(html), :global(body) {
		background: transparent !important;
	}
	.panel {
		width: 360px;
		box-sizing: border-box;
		padding: 16px;
		display: flex;
		flex-direction: column;
		gap: 12px;
	}
	h1 {
		margin: 0;
		font-size: var(--headline);
	}
	.list {
		max-height: 432px;
		overflow-y: auto;
		display: flex;
		flex-direction: column;
		gap: 8px;
		scrollbar-width: none;
	}
	.card {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 8px 12px;
		border-radius: 14px;
		text-align: left;
	}
	.teams {
		display: flex;
		flex-direction: column;
		gap: 6px;
		min-width: 0;
	}
	.line {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.line b {
		width: 36px;
	}
	.name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.score {
		margin-left: 4px;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.dim b, .dim .score {
		color: var(--secondary);
	}
	.secondary {
		color: var(--secondary);
	}
	.small {
		font-size: var(--caption);
	}
	.status {
		flex: none;
		display: flex;
		align-items: center;
		gap: 5px;
		font-size: var(--subheadline);
		font-weight: 600;
	}
	.dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: #ff453a;
	}
	.empty {
		height: 150px;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 6px;
		text-align: center;
		color: var(--label);
	}
	.court {
		filter: invert(1) opacity(0.5);
	}
	.actions {
		display: flex;
		gap: 8px;
	}
	.actions button {
		height: 34px;
		border-radius: 999px;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
	}
	.wide {
		flex: 1;
	}
	.gear {
		width: 48px;
	}
</style>
