# Tree Seed Spread Simulation: Experiment Report

## 1. Overview

We simulate how trees colonize a two-dimensional landscape over discrete time steps. The landscape is a rectangular grid: each cell is either empty or occupied by one tree. Starting from **k randomly placed founder clusters** of varying size, trees spread outward cycle by cycle according to a simple dispersal rule. Over 12 cycles on a 1200 × 1200 grid with `k = 4`, the population grows from 199 founders to 60 075 trees.

The computational goal is to measure how much faster this simulation runs when the grid update is parallelized across CPU cores. Two Chapel programs implement the same model:

- **`tree2.chpl`** — serial baseline using `for` loops
- **`tree_parallel.chpl`** — shared-memory parallel version using `forall`, atomic writes, and parallel reduction

Both are compiled with `chpl --fast` and compared on the Digital Research Alliance of Canada's **Fir** cluster.

## 2. Simulation Model

### The landscape

The landscape is a flat `rows × cols` grid of cells, indexed like a map. At any moment, each cell holds one of two states:

| Value | Meaning |
|------:|---------|
| 0 | empty — no tree |
| 1 | occupied — one tree |

The grid has fixed boundaries: trees cannot spread beyond its edges. In the benchmark run, the grid is 1200 × 1200 cells (1.44 million sites).

### Dispersal rule

Time advances in **cycles**. Within each cycle, every tree that existed at the *start* of the cycle is evaluated independently and simultaneously. A tree can produce at most one new tree per cycle, and only under two conditions:

1. **Neighbourhood presence** — at least one *other* tree (not itself) lies within a circular dispersal radius `r` centred on that tree.
2. **Room to land** — at least one empty cell exists within that same circle.

If both conditions hold, the tree disperses one seed to a single empty cell chosen **uniformly at random** from all empty cells in the circle. The dispersal neighbourhood is a disk (cells satisfying `di² + dj² ≤ r²`), not a square.

Trees that do not disperse, and trees that were present before the cycle, survive into the next cycle. Seedlings produced during a cycle **cannot** disperse until the following cycle. All decisions in a cycle are based on the landscape at the cycle's start, so the update is **synchronous**: the model reads from one grid and writes to a second, then swaps them.

### Initialization

Before the first cycle, `k` founder clusters are placed on the landscape. For each cluster:

1. A **size** is drawn uniformly from `[minTreesPerCluster, maxTreesPerCluster]` (10–100 in the benchmark run).
2. A **centre** is drawn uniformly from valid interior grid coordinates (keeping the cluster's local planting box inside the boundaries).
3. That many trees are placed by rejection sampling within a small box around the centre.

Cluster locations and sizes are therefore random but **reproducible** from the random seed. The parameter `k` is configurable at run time; the benchmark uses `k = 4` for both the serial (`tree2.chpl`) and parallel (`tree_parallel.chpl`) executables.

### Reproducibility

Two independent random-number streams separate founder placement from seed dispersal. In the parallel version, one random value is pre-assigned to every grid cell each cycle so that thread scheduling does not change the dispersal sequence. When multiple trees target the same empty cell, all writes set the cell to occupied; atomic operations make this safe under parallelism.

## 3. Benchmark Design

Runs were submitted to SLURM on Fir (`cpubase_bycore_b1`), allocating 1 node, 32 CPUs, and 16 GB RAM. Chapel 2.4.0 (`chapel-multicore`) was loaded via environment modules.

| Parameter | Value |
|-----------|-------|
| Grid size | 1200 × 1200 |
| Cycles | 12 |
| Founder clusters (`k`) | 4 |
| Trees per cluster | 10–100 (uniform random) |
| Dispersal radius | 15 |
| Random seed | 12345 |
| Repetitions | 3 per configuration |
| Thread counts | 1, 2, 4, 8, 16, 32 |

The problem size is large enough that parallel overhead is not the dominant cost. Each configuration is timed over three repetitions; reported values are means. Speedup is computed relative to the serial baseline (`tree2.chpl`, 1 thread). Correctness is verified by checking that the final tree count matches the serial result at every thread count.

## 4. Results

**Serial baseline** (`tree2.chpl`): **0.510 s** mean, final tree count **60 075**.

| Threads | Mean time (s) | Speedup | Tree count |
|--------:|--------------:|--------:|-----------:|
| 1 | 0.568 | 0.90 | 60 075 |
| 2 | 0.288 | 1.77 | 60 075 |
| 4 | 0.185 | 2.76 | 60 075 |
| 8 | 0.161 | 3.17 | 60 075 |
| 16 | 0.123 | 4.15 | 60 075 |
| 32 | 0.076 | 6.71 | 60 075 |

All parallel runs produced identical final tree counts, confirming bitwise reproducibility of the stochastic model across thread counts.

## 5. Discussion

Scattering founders across several randomly sized, randomly located clusters produces a richer colonization pattern than a single seed patch. With `k = 4` and 199 total founders under seed 12345, independent dispersal fronts grow from multiple sites and eventually merge, reaching 60 075 trees by cycle 12.

Parallelism becomes beneficial beyond 1 thread: speedup reaches **6.7×** at 32 threads, reducing runtime from 0.510 s (serial) to 0.076 s.

At 1 thread, the parallel executable is **10% slower** than the serial code (0.568 s vs 0.510 s). This overhead reflects the cost of `forall` scheduling, atomic operations, and parallel reduction infrastructure that are unnecessary at single-thread concurrency.

Scaling improves through 32 threads (0.90× → 6.71×), with particularly strong gains at 16 and 32 threads as the larger population increases the per-cycle work enough to amortize parallel overhead. The per-cell neighbourhood scan remains memory-bound, so further scaling would eventually sub-linear.

## 6. Visualization

To make the spread dynamics visible, we extended the parallel simulator with snapshot export (`tree_viz.chpl`). The approach mirrors the [Chapel Julia-set exercises](https://folio.vastcloud.org/chapel2/chapel-02-variables.html): each grid cell maps to one pixel in a rectangular image, and the landscape is written as a sequence of binary PPM frames.

**Rendering.** Empty cells are shown as light soil. Each tree is coloured by its **birth cycle** — founders in dark green, later waves in progressively warmer hues — so successive dispersal fronts are visible. A colour legend is appended to every frame and video. One snapshot is saved at cycle 0 and after each subsequent cycle (13 frames total).

**Visualization parameters.** Frames use a **360 × 360** grid with the same seed, radius, and `k = 4` cluster layout as the benchmark. The smaller landscape raises the occupied fraction to about **42%** by cycle 12 (54 230 trees), making the spread easier to see. Benchmark timing still uses 1200 × 1200.

**Pipeline** (`tree_visualize.sh`). For each thread count (1, 2, 4, 8, 16, 32), the simulator writes PPM frames, ImageMagick converts them to PNG, and ffmpeg assembles a video at 2 frames per second. Because the stochastic model is reproducible across thread counts, every video shows the same landscape evolution; generating one video per thread configuration confirms that parallelism does not alter the result.

### Key frames

Snapshots at cycles 0, 3, 6, 9, and 12 show scattered founder clusters (dark green) and successive dispersal waves in distinct colours. The legend on the right identifies each birth cycle.

| Cycle | Trees |
|------:|------:|
| 0 | 199 |
| 3 | 1 514 |
| 6 | 8 954 |
| 9 | 27 386 |
| 12 | 54 230 |

<p align="center">
  <img src="viz/figures/cycle_000.png" width="220" alt="Cycle 0 — four random founder clusters"/>
  <img src="viz/figures/cycle_003.png" width="220" alt="Cycle 3 — 1 514 trees"/>
  <img src="viz/figures/cycle_006.png" width="220" alt="Cycle 6 — 8 954 trees"/>
  <img src="viz/figures/cycle_009.png" width="220" alt="Cycle 9 — 27 386 trees"/>
  <img src="viz/figures/cycle_012.png" width="220" alt="Cycle 12 — 54 230 trees"/>
</p>

<p align="center"><em>Left to right: cycles 0, 3, 6, 9, 12. Colour = birth cycle (legend on the right of each frame).</em></p>

### Spread animation

The animation below plays all 13 frames (cycle 0 through cycle 12) at 2 frames per second. The same movie was generated independently at each thread count; only the 1-thread version is shown here because the landscapes are identical.

<video controls width="560" src="viz/t01/tree_spread_t01.mp4"></video>

<p align="center"><em>Age-coloured spread on a 360 × 360 grid with legend (<code>viz/t01/tree_spread_t01.mp4</code>).</em></p>

Equivalent videos for other thread configurations (same content, different run):

| Threads | Video |
|--------:|-------|
| 1 | [tree_spread_t01.mp4](viz/t01/tree_spread_t01.mp4) |
| 2 | [tree_spread_t02.mp4](viz/t02/tree_spread_t02.mp4) |
| 4 | [tree_spread_t04.mp4](viz/t04/tree_spread_t04.mp4) |
| 8 | [tree_spread_t08.mp4](viz/t08/tree_spread_t08.mp4) |
| 16 | [tree_spread_t16.mp4](viz/t16/tree_spread_t16.mp4) |
| 32 | [tree_spread_t32.mp4](viz/t32/tree_spread_t32.mp4) |

## 7. Artifacts

| File | Description |
|------|-------------|
| `tree2.chpl` | Serial implementation |
| `tree_parallel.chpl` | Parallel implementation |
| `tree_viz.chpl` | Parallel simulator with PPM snapshot output |
| `tree_benchmark.sh` | SLURM benchmark driver |
| `tree_visualize.sh` | SLURM visualization pipeline (frames, PNGs, videos) |
| `tree_scaling_45700324.csv` | Scaling summary (CSV) |
| `viz/figures/` | Key-frame still images and colour legend |
| `viz/t*/tree_spread_*.mp4` | Spread animation per thread count |
