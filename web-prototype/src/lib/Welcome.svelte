<script lang="ts">
	// First launch: pick the leagues for the sidebar and Home. Shown until a choice is saved (settings.shownLeagues).
	import LeagueBubbles from './LeagueBubbles.svelte';
	import { leagues } from './espn';
	import { settings, saveSettings } from './settings.svelte';

	let picked = $state<string[]>([]);
	const save = (ids: string[]) => {
		settings.shownLeagues = ids;
		saveSettings();
	};
</script>

<div class="welcome" role="dialog" aria-modal="true" aria-labelledby="welcome-title" data-tauri-drag-region>
	<div class="content" data-tauri-drag-region>
		<img class="icon" src="/icon-dark.png" alt="" width="72" height="72" />
		<h1 id="welcome-title">Welcome to Halftime</h1>
		<p class="lede">Pick the leagues you care about. They'll fill your sidebar and Home; you can change them any time in Settings.</p>
		<LeagueBubbles selected={picked} onchange={(ids) => (picked = ids)} />
		<div class="actions">
			<button class="continue" disabled={!picked.length} onclick={() => save(picked)}>
				{picked.length ? `Continue with ${picked.length} ${picked.length === 1 ? 'league' : 'leagues'}` : 'Pick at least one league'}
			</button>
			<button class="all" onclick={() => save(leagues.map((l) => l.id))}>Show all leagues</button>
		</div>
	</div>
</div>

<style>
	.welcome {
		position: fixed;
		inset: 0;
		z-index: 50;
		display: grid;
		place-items: center;
		overflow-y: auto;
		/* Solid, so the app behind doesn't compete with the bubbles; a faint green glow from the top. */
		background: radial-gradient(ellipse at 50% 0%, rgba(48, 209, 88, 0.16), transparent 60%), #0e0f11;
		animation: fade 0.4s ease-out;
	}
	.content {
		max-width: 640px;
		padding: 48px 24px;
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
	}
	.icon {
		border-radius: 18px;
		margin-bottom: 14px;
	}
	h1 {
		margin: 0;
		font-size: 30px;
		font-weight: 700;
		letter-spacing: -0.01em;
	}
	.lede {
		margin: 8px 0 34px;
		max-width: 440px;
		color: var(--secondary);
		font-size: var(--body);
		line-height: 1.45;
	}
	.actions {
		margin-top: 38px;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 12px;
	}
	.continue {
		min-width: 260px;
		padding: 12px 26px;
		border-radius: 999px;
		background: #30d158;
		color: #0b0b0b;
		font-size: var(--body);
		font-weight: 700;
		transition: transform 0.15s, opacity 0.2s, background 0.2s;
	}
	.continue:hover:not(:disabled) {
		transform: scale(1.03);
	}
	.continue:disabled {
		background: rgba(255, 255, 255, 0.12);
		color: var(--secondary);
		cursor: default;
	}
	.all {
		color: var(--secondary);
		font-size: var(--subheadline);
	}
	.all:hover {
		color: var(--label);
		text-decoration: underline;
	}
	@keyframes fade {
		from { opacity: 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.welcome { animation: none; }
	}
</style>
