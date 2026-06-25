/*
  Parallel tree spread with age-coloured PPM snapshot output.

  Each cell stores a birth cycle (0 = empty; 1..steps+1 encodes birth at
  cycle 0..steps). Snapshots colour trees by birth cycle so dispersal waves
  are visible. A colour legend is appended when frames are converted to PNG.
*/

use Time;
use Random;
use FileSystem;
use IO;

config const rows = 360;
config const cols = 360;
config const steps = 12;
config const k = 4;
config const minTreesPerCluster = 10;
config const maxTreesPerCluster = 100;
config const radius = 15;
config const seed = 12345;
config const report = true;
config const outDir = "frames";

const Land: domain(2) = {1..rows, 1..cols};
const maxBirth = steps;  // founders = 0, newest = steps

var tree: [Land] int;
var nextTree: [Land] atomic int;

var founderRng = new randomStream(real, seed);
var spreadRng  = new randomStream(real, seed + 1);

// Empty soil (warm beige).
const emptyR = 237: int(8);
const emptyG = 232: int(8);
const emptyB = 220: int(8);

// Birth-cycle palette: founders (dark green) → warm hues for recent spread.
const ageR = [27, 45, 64, 82, 116, 149, 183, 244, 238, 249, 201, 114, 58]: [0..maxBirth] int(8);
const ageG = [67, 106, 145, 183, 196, 213, 228, 211, 150, 87, 24, 9, 12]: [0..maxBirth] int(8);
const ageB = [50, 79, 108, 136, 148, 178, 199, 93, 56, 56, 74, 87, 163]: [0..maxBirth] int(8);


proc occupied(val: int): bool {
  return val > 0;
}


proc birthAge(val: int): int {
  return val - 1;
}


proc cycleLabel(cycle: int): string {
  var digits = cycle:string;
  while digits.size < 3 do
    digits = "0" + digits;
  return digits;
}


proc writeSnapshot(cycle: int) {
  const filename = outDir + "/cycle_" + cycleLabel(cycle) + ".ppm";
  const img = open(filename, ioMode.cw);
  const w = img.writer(locking=true);

  w.writeln("P6");
  w.writeln(cols, " ", rows);
  w.writeln(255);

  for i in 1..rows {
    for j in 1..cols {
      const val = tree[i, j];

      if occupied(val) {
        const age = birthAge(val);
        w.writeBinary(ageR[age]);
        w.writeBinary(ageG[age]);
        w.writeBinary(ageB[age]);
      } else {
        w.writeBinary(emptyR);
        w.writeBinary(emptyG);
        w.writeBinary(emptyB);
      }
    }
  }

  w.close();
  img.close();
}


if !exists(outDir) then
  mkdir(outDir, parents=true);


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
      tree[i, j] = 1;  // birth cycle 0 → stored as 1
      clusterPlanted += 1;
    }
  }

  initialTrees += clusterPlanted;
}

writeSnapshot(0);

var treeCount = initialTrees;
var timer: stopwatch;
timer.start();

for cycle in 1..steps {
  forall idx in Land do
    nextTree[idx].write(tree[idx]);

  forall (idx, randomValue) in zip(Land, spreadRng.next(Land)) {
    const (i, j) = idx;

    if occupied(tree[i, j]) {
      var otherTree = false;
      var emptyCount = 0;

      for di in -radius..radius {
        for dj in -radius..radius {
          if di*di + dj*dj <= radius*radius {
            const ni = i + di;
            const nj = j + dj;

            if Land.contains(ni, nj) {
              if (di != 0 || dj != 0) && occupied(tree[ni, nj]) then
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
        const newborn = cycle + 1;  // birth cycle cycle → stored as cycle+1

        label place for di in -radius..radius {
          for dj in -radius..radius {
            if di*di + dj*dj <= radius*radius {
              const ni = i + di;
              const nj = j + dj;

              if Land.contains(ni, nj) && tree[ni, nj] == 0 {
                if seen == target {
                  nextTree[ni, nj].write(newborn);
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

  forall idx in Land do
    tree[idx] = nextTree[idx].read();

  treeCount = 0;
  for idx in Land do
    if occupied(tree[idx]) then
      treeCount += 1;

  writeSnapshot(cycle);

  if report then
    writeln("cycle ", cycle, ": ", treeCount, " trees");
}

timer.stop();

writeln("Final tree count: ", treeCount);
writeln("Snapshots written to ", outDir, "/");
writeln("Simulation finished in ", timer.elapsed(), " seconds");
