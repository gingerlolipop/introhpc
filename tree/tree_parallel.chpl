/*
  Shared-memory parallel tree seed spread on a 2D grid.

  Parallel concepts used:
      1. forall data-parallel loops
      2. a parallel Random stream iterator
      3. atomic writes for competing seed arrivals
      4. a parallel reduction for the tree count

  This version is intended for several CPU cores on one Cedar node.
*/

use Time;
use Random;

config const rows = 60;
config const cols = 60;
config const steps = 2;
config const k = 3;
config const minTreesPerCluster = 10;
config const maxTreesPerCluster = 100;
config const radius = 5;
config const seed = 12345;
config const report = true;

const Land: domain(2) = {1..rows, 1..cols};

var tree: [Land] int;

/*
  Different parent trees can select the same target cell concurrently.
  Atomic elements make those concurrent writes safe.
*/
var nextTree: [Land] atomic int;

var founderRng = new randomStream(real, seed);
var spreadRng  = new randomStream(real, seed + 1);


// Founder placement is small, so keep it serial.
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

  // Existing trees persist. Each iteration writes a different element.
  forall idx in Land do
    nextTree[idx].write(tree[idx]);

  /*
    rng.next(Land) maps a reproducible random value to every index in Land.
    Unlike calling rng.next() inside forall, this parallel iterator is safe.
  */
  forall (idx, randomValue) in zip(Land, spreadRng.next(Land)) {
    const (i, j) = idx;

    if tree[i, j] == 1 {
      var otherTree = false;
      var emptyCount = 0;

      // These variables are private to this forall iteration.
      for di in -radius..radius {
        for dj in -radius..radius {
          if di*di + dj*dj <= radius*radius {
            const ni = i + di;
            const nj = j + dj;

            if Land.contains(ni, nj) {
              if (di != 0 || dj != 0) && tree[ni, nj] == 1 then
                otherTree = true;

              if tree[ni, nj] == 0 then
                emptyCount += 1;
            }
          }
        }
      }

      if otherTree && emptyCount > 0 {
        const target = min((randomValue * emptyCount): int,
                           emptyCount - 1);
        var seen = 0;

        label place for di in -radius..radius {
          for dj in -radius..radius {
            if di*di + dj*dj <= radius*radius {
              const ni = i + di;
              const nj = j + dj;

              if Land.contains(ni, nj) && tree[ni, nj] == 0 {
                if seen == target {
                  /*
                    Several tasks may write 1 to the same cell.
                    Atomic write prevents a data race.
                  */
                  nextTree[ni, nj].write(1);
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

  // forall ends with a barrier, so all seed placements are complete here.
  forall idx in Land do
    tree[idx] = nextTree[idx].read();

  // Chapel parallel reduction.
  treeCount = (+ reduce tree);

  if report then
    writeln("cycle ", cycle, ": ", treeCount, " trees");
}

timer.stop();

writeln("Final tree count: ", treeCount);
writeln("Simulation finished in ", timer.elapsed(), " seconds");
