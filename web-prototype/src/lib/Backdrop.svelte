<script lang="ts">
	// The Swift app's waving MeshGradient, approximated with drifting radial folds of lighter and darker shades.
	// Folds change brightness only, so the colour stays true (Home's green stays iOS's #2D6526).
	import { brightness, readable } from './espn';
	let { color: raw, flat = false }: { color: string; flat?: boolean } = $props();
	const depth = $derived(flat ? 0.65 : 1.25);
	// Pale team colours (white, sky blue, gold) are darkened until white text reads on the lightest fold.
	const color = $derived(readable(raw, 1 + 0.18 * depth));
	const light = $derived(brightness(color, 1 + 0.18 * depth));
	const dark = $derived(brightness(color, 1 - 0.28 * depth));
	const fade = $derived(flat ? 0.18 : 0.65);
</script>

<div class="backdrop" style:--base={color} style:--light={light} style:--dark={dark} style:--fade={fade} aria-hidden="true">
	<div class="folds"></div>
	<div class="shade"></div>
</div>

<style>
	.backdrop {
		position: fixed;
		inset: 0;
		z-index: -1;
		background: var(--base);
		overflow: hidden;
	}
	.folds {
		position: absolute;
		inset: -30%;
		background:
			radial-gradient(40% 30% at 20% 25%, var(--light), transparent 70%),
			radial-gradient(35% 40% at 75% 20%, var(--dark), transparent 70%),
			radial-gradient(45% 30% at 60% 60%, var(--light), transparent 70%),
			radial-gradient(40% 35% at 25% 75%, var(--dark), transparent 70%),
			radial-gradient(30% 30% at 85% 80%, var(--light), transparent 70%);
		animation: wave 26s ease-in-out infinite alternate;
	}
	.shade {
		position: absolute;
		inset: 0;
		background: linear-gradient(to bottom, transparent, rgba(0, 0, 0, calc(var(--fade) * 0.25)) 50%, rgba(0, 0, 0, var(--fade)));
	}
	@keyframes wave {
		0% { transform: translate(0, 0) rotate(0deg) scale(1); }
		33% { transform: translate(4%, -3%) rotate(3deg) scale(1.05); }
		66% { transform: translate(-3%, 4%) rotate(-2deg) scale(1.02); }
		100% { transform: translate(2%, 2%) rotate(1deg) scale(1.06); }
	}
	@media (prefers-reduced-motion: reduce) {
		.folds { animation: none; }
	}
</style>
