/*
  Tree seed spread on a 2D grid
  -----------------------------

  This program simulates the spread of trees on a rectangular landscape.
  Each grid cell is either empty or occupied by a tree:

      0 = empty
      1 = tree

  The simulation starts with k founder clusters at random locations, each with a
  random size. At each cycle, every existing tree is checked.

  Reproduction rule:

      A tree can produce one new tree only if there is at least one other tree
      within its dispersal radius. If so, the tree chooses one empty cell
      uniformly at random from within that same radius, and that cell becomes
      occupied in the next cycle.

  Updates are synchronous: all new trees in a cycle are decided from the tree
  distribution at the start of that cycle. Newly produced trees do not reproduce
  until the following cycle. Therefore, we use two arrays:

      tree      current landscape, read during the cycle
      nextTree  next landscape, written during the cycle

  This is the serial baseline version. Later versions can replace the main
  loops with forall loops for shared-memory parallelism, and can replace the
  local domain with a distributed domain for multi-locale execution.
*/


use Time;
use Random;

config const rows = 60;
config const cols = 60;
config const steps = 2;
config const k = 4;
config const minTreesPerCluster = 10;
config const maxTreesPerCluster = 100;
config const radius = 5;
config const seed = 12345;
config const report = true;

const Land: domain(2) = {1..rows, 1..cols};

// tree     = landscape at the START of the current cycle (read-only during updates)
// nextTree = landscape at the END of the current cycle (written during updates)
var tree:     [Land] int;
var nextTree: [Land] int;

// Two independent RNG streams so founder placement never shifts the spread
// sequence. spreadRng must stay deterministic per (cycle, cell) when we
// later switch the main loop to forall.
var founderRng = new randomStream(real, seed);
var spreadRng  = new randomStream(real, seed + 1);


// Place k founder clusters at random locations. Each cluster size is drawn
// uniformly from [minTreesPerCluster, maxTreesPerCluster].
const halfBox = max(1, radius / 2);
const minR = halfBox + 1;
const maxR = rows - halfBox;
const minC = halfBox + 1;
const maxC = cols - halfBox;
var initialTrees = 0;

for cluster in 0..<k {
  const clusterSize = minTreesPerCluster +
    (founderRng.next() * (maxTreesPerCluster - minTreesPerCluster + 1)): int;
  const clusterR = minR +
    (founderRng.next() * (maxR - minR + 1)): int;
  const clusterC = minC +
    (founderRng.next() * (maxC - minC + 1)): int;

  var clusterPlanted = 0;

  while clusterPlanted < clusterSize {
    const i = clusterR - halfBox +
              (founderRng.next() * (2 * halfBox + 1)): int;
    const j = clusterC - halfBox +
              (founderRng.next() * (2 * halfBox + 1)): int;

    if Land.contains(i, j) && tree[i, j] == 0 {
      tree[i, j] = 1;
      clusterPlanted += 1;
    }
  }

  initialTrees += clusterPlanted;
}


// Main simulation.
var treeCount = initialTrees;
var timer: stopwatch;
timer.start();

for cycle in 1..steps {

  // Copy current trees into nextTree so survivors carry over. New seedlings
  // are OR-ed in below (nextTree[ni,nj] = 1). We copy element-wise rather
  // than `nextTree = tree` to mirror the parallel forall version.
  for idx in Land do
    nextTree[idx] = tree[idx];

  /*
    Pre-draw one random real per grid cell for this cycle.

    Why not call spreadRng.next() only inside `if tree[i,j] == 1`?
    Because in a parallel forall, iteration order is undefined. Consuming
    random numbers only for tree cells would tie the RNG stream to schedule,
    giving different results serial vs parallel. Here every cell gets a fixed
    randomValue regardless of whether it is a tree.
  */
  for (idx, randomValue) in zip(Land, spreadRng.next(Land)) {
    const (i, j) = idx;

    if tree[i, j] == 1 {
      var otherTree = false;
      var emptyCount = 0;

      // Scan the circular dispersal neighbourhood (disk, not a square).
      for di in -radius..radius {
        for dj in -radius..radius {
          if di*di + dj*dj <= radius*radius {
            const ni = i + di;
            const nj = j + dj;

            if Land.contains(ni, nj) {
              // Partner must be a different tree (exclude the cell itself).
              if (di != 0 || dj != 0) && tree[ni, nj] == 1 then
                otherTree = true;

              // Count empty landing sites (includes the centre if empty).
              if tree[ni, nj] == 0 then
                emptyCount += 1;
            }
          }
        }
      }

      // Reproduce only when a partner exists AND there is somewhere to land.
      if otherTree && emptyCount > 0 {
        /*
          Pick the target-th empty cell in a fixed (di,dj) scan order.
          randomValue is in [0,1), so (randomValue * emptyCount): int is
          usually in [0, emptyCount-1]. Cap with min() because a float can
          very rarely round up to emptyCount, which would be out of range.
        */
        const target = min((randomValue * emptyCount): int,
                           emptyCount - 1);
        var seen = 0;

        // Walk empty cells in the same order as the counting loop above.
        // `label place` lets us break out of both nested loops once placed.
        label place for di in -radius..radius {
          for dj in -radius..radius {
            if di*di + dj*dj <= radius*radius {
              const ni = i + di;
              const nj = j + dj;

              if Land.contains(ni, nj) && tree[ni, nj] == 0 {
                if seen == target {
                  // Multiple parents may pick the same cell; all write 1, which
                  // is fine. In a parallel forall this is a concurrent write to
                  // the same int — safe here because every write stores 1.
                  nextTree[ni, nj] = 1;
                  break place;
                }

                seen += 1;
              }
            }
          }
        }
      }
    }
  }

  // Commit nextTree as the new current landscape for the following cycle.
  for idx in Land do
    tree[idx] = nextTree[idx];

  treeCount = 0;
  for idx in Land do
    treeCount += tree[idx];

  if report then
    writeln("cycle ", cycle, ": ", treeCount, " trees");
}

timer.stop();

writeln("Final tree count: ", treeCount);
writeln("Simulation finished in ", timer.elapsed(), " seconds");
