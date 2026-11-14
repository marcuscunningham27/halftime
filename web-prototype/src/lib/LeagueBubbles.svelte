<script lang="ts">
	// The league picker on the welcome screen and in Settings: a bubble per league, the four big US leagues larger.
	// Bubbles float gently, lift on hover, and turn green with a check when picked.
	import { leagues, leagueLogo } from './espn';

	let { selected, onchange, compact = false }: { selected: string[]; onchange: (ids: string[]) => void; compact?: boolean } = $props();

	const major = new Set(['nfl', 'nba', 'mlb', 'nhl']);
	const rows = [leagues.filter((l) => major.has(l.id)), leagues.filter((l) => !major.has(l.id))];
	const toggle = (id: string) => onchange(selected.includes(id) ? selected.filter((x) => x !== id) : [...selected, id]);
</script>

<div class="bubbles" class:compact role="group" aria-label="Leagues">
	{#each rows as row, r}
		<div class="row">
			{#each row as l, i (l.id)}
				{@const on = selected.includes(l.id)}
				<button class="bubble" class:major={r === 0} class:on aria-pressed={on} title={l.name} style:--delay="{-(r * 4 + i) * 0.83}s" onclick={() => toggle(l.id)}>
					<span class="disc">
						<img src={leagueLogo(l)} alt="" draggable="false" />
						{#if on}
							<svg class="check" viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="10" fill="#30d158" /><path d="M5.5 10.3l3 3 6-6.4" fill="none" stroke="#0b0b0b" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" /></svg>
						{/if}
					</span>
					<span class="name">{l.abbreviation}</span>
				</button>
			{/each}
		</div>
	{/each}
</div>

<style>
	.bubbles {
		--big: 112px;
		--small: 78px;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 18px;
	}
	.bubbles.compact {
		--big: 76px;
		--small: 56px;
		gap: 12px;
	}
	.row {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: 18px 22px;
	}
	.compact .row {
		gap: 12px 14px;
	}
	/* The float lives on the button, the hover lift and press on the disc, so the two transforms don't fight. */
	.bubble {
		--size: var(--small);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
		padding: 0;
		background: none;
		animation: float 5s ease-in-out infinite;
		animation-delay: var(--delay);
	}
	.bubble.major {
		--size: var(--big);
	}
	.disc {
		position: relative;
		width: var(--size);
		height: var(--size);
		border-radius: 50%;
		display: grid;
		place-items: center;
		background: radial-gradient(circle at 35% 30%, rgba(255, 255, 255, 0.16), rgba(255, 255, 255, 0.04) 70%);
		box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.14), 0 6px 18px rgba(0, 0, 0, 0.35);
		backdrop-filter: blur(12px);
		transition: transform 0.25s cubic-bezier(0.34, 1.56, 0.64, 1), box-shadow 0.25s, background 0.25s;
	}
	.disc img {
		width: 52%;
		height: 52%;
		object-fit: contain;
		filter: drop-shadow(0 0 0.6px rgba(255, 255, 255, 0.9));
		transition: transform 0.25s cubic-bezier(0.34, 1.56, 0.64, 1);
	}
	.bubble:hover .disc,
	.bubble:focus-visible .disc {
		transform: scale(1.08);
		box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.3), 0 10px 26px rgba(0, 0, 0, 0.45);
	}
	.bubble:hover .disc img {
		transform: scale(1.06) rotate(-4deg);
	}
	.bubble:active .disc {
		transform: scale(0.95);
	}
	.bubble.on .disc {
		background: radial-gradient(circle at 35% 30%, rgba(48, 209, 88, 0.32), rgba(48, 209, 88, 0.08) 70%);
		box-shadow: inset 0 0 0 2px #30d158, 0 0 22px rgba(48, 209, 88, 0.35), 0 6px 18px rgba(0, 0, 0, 0.35);
	}
	.bubble:focus-visible {
		outline: none;
	}
	.bubble:focus-visible .disc {
		outline: 3px solid rgba(10, 132, 255, 0.7);
		outline-offset: 3px;
	}
	.check {
		position: absolute;
		top: 2%;
		right: 2%;
		width: 26%;
		height: 26%;
		max-width: 26px;
		max-height: 26px;
		animation: pop 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
	}
	.name {
		font-size: var(--subheadline);
		font-weight: 600;
		color: var(--secondary);
		transition: color 0.2s;
	}
	.major .name {
		font-size: var(--body);
	}
	.bubble.on .name,
	.bubble:hover .name {
		color: var(--label);
	}
	@keyframes float {
		0%, 100% { transform: translateY(0); }
		50% { transform: translateY(-6px); }
	}
	@keyframes pop {
		from { transform: scale(0); }
	}
	@media (prefers-reduced-motion: reduce) {
		.bubble, .check { animation: none; }
		.disc, .disc img { transition: none; }
	}
</style>
