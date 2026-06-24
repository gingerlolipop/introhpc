/*
  Parallel tree spread with PPM snapshot output.

  Writes one binary PPM image per cycle (plus cycle 0 after founder placement),
  similar to plotting a 2D field in the Chapel Julia-set exercises:
  each grid cell maps to one pixel.
*/

use Time;
use Random;
use FileSystem;
use IO;

config const rows = 600;
config const cols = 600;
config const steps = 12;
config const initialTrees = 100;
config const radius = 15;
config const seed = 12345;
config const report = true;
config const outDir = "frames";

const Land: domain(2) = {1..rows, 1..cols};

var tree: [Land] int;
var nextTree: [Land] atomic int;

var founderRng = new randomStream(real, seed);
var spreadRng  = new randomStream(real, seed + 1);

// Empty soil and tree colours (RGB).
const emptyR = 232: int(8);
const emptyG = 220: int(8);
const emptyB = 200: int(8);
const treeR  =  34: int(8);
const treeG  = 139: int(8);
const treeB  =  34: int(8);


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
      if tree[i, j] == 1 {
        w.writeBinary(treeR);
        w.writeBinary(treeG);
        w.writeBinary(treeB);
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


const cr = rows / 2;
const cc = cols / 2;
const halfBox = max(1, radius / 2);

var planted = 0;

while planted < initialTrees {
  const i = cr - halfBox +
            (founderRng.next() * (2 * halfBox + 1)): int;
  const j = cc - halfBox +
            (founderRng.next() * (2 * halfBox + 1)): int;

  if Land.contains(i, j) && tree[i, j] == 0 {
    tree[i, j] = 1;
    planted += 1;
  }
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

    if tree[i, j] == 1 {
      var otherTree = false;
      var emptyCount = 0;

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

  forall idx in Land do
    tree[idx] = nextTree[idx].read();

  treeCount = (+ reduce tree);
  writeSnapshot(cycle);

  if report then
    writeln("cycle ", cycle, ": ", treeCount, " trees");
}

timer.stop();

writeln("Final tree count: ", treeCount);
writeln("Snapshots written to ", outDir, "/");
writeln("Simulation finished in ", timer.elapsed(), " seconds");
