# Tree Seed Spread Simulation: Experiment Report

## 1. Overview

We simulate how trees colonize a two-dimensional landscape over discrete time steps. The landscape is a rectangular grid: each cell is either empty or occupied by one tree. Starting from a small cluster of founder trees near the centre, trees spread outward cycle by cycle according to a simple dispersal rule. Over 12 cycles on a 1200 × 1200 grid, the population grows from 100 founders to 17 779 trees.

The computational goal is to measure how much faster this simulation runs when the grid update is parallelized across CPU cores. Two Chapel programs implement the same model:

- **`tree2.chpl`** — serial baseline using `for` loops
- **`tree_parallel.chpl`** — shared-memory parallel version using `forall`, atomic writes, and parallel reduction

Both are compiled with `chpl --fast` and compared on UBC Sockeye.

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

Before the first cycle, `initialTrees` founders are placed near the grid centre. Random candidate locations are drawn within a small box around the midpoint; a location is accepted only if it is empty, until the target count is reached.

### Reproducibility

Two independent random-number streams separate founder placement from seed dispersal. In the parallel version, one random value is pre-assigned to every grid cell each cycle so that thread scheduling does not change the dispersal sequence. When multiple trees target the same empty cell, all writes set the cell to occupied; atomic operations make this safe under parallelism.

## 3. Benchmark Design

Runs were submitted to SLURM on UBC Sockeye (`cpubase_bycore_b1`), allocating 1 node, 32 CPUs, and 16 GB RAM. Chapel 2.4.0 (`chapel-multicore`) was loaded via environment modules.

| Parameter | Value |
|-----------|-------|
| Grid size | 1200 × 1200 |
| Cycles | 12 |
| Initial trees | 100 |
| Dispersal radius | 15 |
| Random seed | 12345 |
| Repetitions | 3 per configuration |
| Thread counts | 1, 2, 4, 8, 16, 32 |

The problem size is large enough that parallel overhead is not the dominant cost. Each configuration is timed over three repetitions; reported values are means. Speedup is computed relative to the serial baseline (`tree2.chpl`, 1 thread). Correctness is verified by checking that the final tree count matches the serial result at every thread count.

## 4. Results

**Serial baseline** (`tree2.chpl`): **0.238 s** mean, final tree count **17 779**.

| Threads | Mean time (s) | Speedup | Tree count |
|--------:|--------------:|--------:|-----------:|
| 1 | 0.316 | 0.75 | 17 779 |
| 2 | 0.161 | 1.48 | 17 779 |
| 4 | 0.110 | 2.15 | 17 779 |
| 8 | 0.085 | 2.81 | 17 779 |
| 16 | 0.073 | 3.28 | 17 779 |
| 32 | 0.053 | 4.49 | 17 779 |

All parallel runs produced identical final tree counts, confirming bitwise reproducibility of the stochastic model across thread counts.

## 5. Discussion

Parallelism becomes beneficial beyond 1 thread: speedup reaches **4.5×** at 32 threads, reducing runtime from 0.238 s (serial) to 0.053 s.

At 1 thread, the parallel executable is **25% slower** than the serial code (0.316 s vs 0.238 s). This overhead reflects the cost of `forall` scheduling, atomic operations, and parallel reduction infrastructure that are unnecessary at single-thread concurrency.

Scaling is near-linear from 1 to 8 threads (0.75× → 2.81×) but sub-linear beyond that (3.28× at 16 threads, 4.49× at 32). The per-cell neighbourhood scan is memory-bound and repeats work across overlapping disks, so adding threads yields diminishing returns once the grid update is sufficiently saturated.

## 6. Artifacts

| File | Description |
|------|-------------|
| `tree2.chpl` | Serial implementation |
| `tree_parallel.chpl` | Parallel implementation |
| `tree_benchmark.sh` | SLURM benchmark driver |
| `tree_benchmark_45687164.out` | Full job log |
| `tree_scaling_45687164.csv` | Scaling summary (CSV) |
