/*
  Shared-memory parallel two-species tree spread (BAM-inspired).

  Species A: slow regeneration, persistent. Species B: fast regeneration,
  dies after successful reproduction; places two seeds when another B is nearby.
  Competing claims on one cell resolve 60/40 in favour of B by default.
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
config const reproProbA = 0.35;
config const reproProbB = 0.85;
config const winProbB = 0.60;
config const seed = 12345;
config const report = true;

const Empty = 0;
const SpeciesA = 1;
const SpeciesB = 2;

const Land: domain(2) = {1..rows, 1..cols};

var tree: [Land] int;
var nextTree: [Land] atomic int;
var propA: [Land] atomic int;
var propB: [Land] atomic int;
var bDie:  [Land] atomic int;

var founderRng = new randomStream(real, seed);
var spreadRng  = new randomStream(real, seed + 1);


proc occupied(val: int): bool {
  return val != Empty;
}


proc nthEmptyInDisk(treeGrid: [Land] int, ci: int, cj: int, targetIndex: int,
                    skipI: int = -1, skipJ: int = -1): (int, int, bool) {
  var seen = 0;

  for di in -radius..radius {
    for dj in -radius..radius {
      if di*di + dj*dj <= radius*radius {
        const ni = ci + di;
        const nj = cj + dj;

        if Land.contains(ni, nj) && treeGrid[ni, nj] == Empty {
          if ni == skipI && nj == skipJ then continue;

          if seen == targetIndex then
            return (ni, nj, true);

          seen += 1;
        }
      }
    }
  }

  return (-1, -1, false);
}


proc plantCluster(ref grid: [Land] int, species: int,
                  clusterR: int, clusterC: int, clusterSize: int,
                  halfBox: int) {
  var planted = 0;

  while planted < clusterSize {
    const i = clusterR - halfBox +
              (founderRng.next() * (2 * halfBox + 1)): int;
    const j = clusterC - halfBox +
              (founderRng.next() * (2 * halfBox + 1)): int;

    if Land.contains(i, j) && grid[i, j] == Empty {
      grid[i, j] = species;
      planted += 1;
    }
  }
}


const halfBox = max(1, radius / 2);
const minR = halfBox + 1;
const maxR = rows - halfBox;
const minC = halfBox + 1;
const maxC = cols - halfBox;

for cluster in 0..<k {
  const clusterSize = minTreesPerCluster +
    (founderRng.next() * (maxTreesPerCluster - minTreesPerCluster + 1)): int;
  const clusterR = minR +
    (founderRng.next() * (maxR - minR + 1)): int;
  const clusterC = minC +
    (founderRng.next() * (maxC - minC + 1)): int;

  plantCluster(tree, SpeciesA, clusterR, clusterC, clusterSize, halfBox);
  plantCluster(tree, SpeciesB, clusterR, clusterC, clusterSize, halfBox);
}


var timer: stopwatch;
timer.start();

for cycle in 1..steps {
  forall idx in Land do
    nextTree[idx].write(tree[idx]);

  forall idx in Land {
    propA[idx].write(0);
    propB[idx].write(0);
    bDie[idx].write(0);
  }

  const reproRolls: [Land] real = spreadRng.next(Land);
  const targetRolls: [Land] real = spreadRng.next(Land);
  const secondTargetRolls: [Land] real = spreadRng.next(Land);
  const competeRolls: [Land] real = spreadRng.next(Land);

  forall (idx, reproRoll, targetRoll, secondTargetRoll) in
      zip(Land, reproRolls, targetRolls, secondTargetRolls) {
    const (i, j) = idx;
    const species = tree[i, j];

    if !occupied(species) then continue;

    var otherTree = false;
    var otherB = false;
    var emptyCount = 0;

    for di in -radius..radius {
      for dj in -radius..radius {
        if di*di + dj*dj <= radius*radius {
          const ni = i + di;
          const nj = j + dj;

          if Land.contains(ni, nj) {
            if (di != 0 || dj != 0) && occupied(tree[ni, nj]) {
              otherTree = true;
              if tree[ni, nj] == SpeciesB then
                otherB = true;
            }

            if tree[ni, nj] == Empty then
              emptyCount += 1;
          }
        }
      }
    }

    const reproProb = if species == SpeciesA then reproProbA else reproProbB;

    if otherTree && emptyCount > 0 && reproRoll < reproProb {
      const target1 = min((targetRoll * emptyCount): int, emptyCount - 1);
      const (t1i, t1j, ok1) = nthEmptyInDisk(tree, i, j, target1);

      if ok1 {
        if species == SpeciesA then
          propA[t1i, t1j].write(1);
        else {
          propB[t1i, t1j].write(1);
          bDie[i, j].write(1);

          if otherB && emptyCount >= 2 {
            const remain = emptyCount - 1;
            const target2 = min((secondTargetRoll * remain): int, remain - 1);
            const (t2i, t2j, ok2) = nthEmptyInDisk(tree, i, j, target2, t1i, t1j);

            if ok2 then
              propB[t2i, t2j].write(1);
          }
        }
      }
    }
  }

  forall idx in Land {
    if tree[idx] != Empty then continue;

    if propA[idx].read() > 0 && propB[idx].read() > 0 {
      if competeRolls[idx] < winProbB then
        nextTree[idx].write(SpeciesB);
      else
        nextTree[idx].write(SpeciesA);
    } else if propB[idx].read() > 0 then
      nextTree[idx].write(SpeciesB);
    else if propA[idx].read() > 0 then
      nextTree[idx].write(SpeciesA);
  }

  forall idx in Land do
    if bDie[idx].read() > 0 then
      nextTree[idx].write(Empty);

  forall idx in Land do
    tree[idx] = nextTree[idx].read();

  if report {
    var countA = 0;
    var countB = 0;
    for idx in Land {
      if tree[idx] == SpeciesA then countA += 1;
      else if tree[idx] == SpeciesB then countB += 1;
    }
    writeln("cycle ", cycle, ": ", countA + countB,
            " trees (A=", countA, ", B=", countB, ")");
  }
}

timer.stop();

var finalA = 0;
var finalB = 0;
for idx in Land {
  if tree[idx] == SpeciesA then finalA += 1;
  else if tree[idx] == SpeciesB then finalB += 1;
}

writeln("Final tree count: ", finalA + finalB,
        " (A=", finalA, ", B=", finalB, ")");
writeln("Simulation finished in ", timer.elapsed(), " seconds");
