/*
  Two-species tree spread on a 2D grid (BAM-inspired).

  Cell values:
      0 = empty
      1 = species A (slow regeneration, long-lived, never dies)
      2 = species B (fast regeneration, dies after successful reproduction)

  Both species share the same founder-cluster layout. When A and B claim the
  same empty cell in one cycle, B wins with probability winProbB (default 60%).
  When a B tree reproduces with another B in its dispersal disk, it places two
  seeds instead of one.
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

var tree:     [Land] int;
var nextTree: [Land] int;

var founderRng = new randomStream(real, seed);
var spreadRng  = new randomStream(real, seed + 1);


proc occupied(val: int): bool {
  return val != Empty;
}


// Return the (i,j) of the targetIndex-th empty cell in the disk around (ci,cj),
// optionally skipping one cell (used to pick a second distinct landing site).
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


proc claimB(ref propB: [Land] bool, ref bDie: [Land] bool,
            pi: int, pj: int, ni: int, nj: int) {
  propB[ni, nj] = true;
  bDie[pi, pj] = true;
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
  for idx in Land do
    nextTree[idx] = tree[idx];

  var propA: [Land] bool;
  var propB: [Land] bool;
  var bDie:  [Land] bool;

  for idx in Land {
    propA[idx] = false;
    propB[idx] = false;
    bDie[idx] = false;
  }

  const reproRolls: [Land] real = spreadRng.next(Land);
  const targetRolls: [Land] real = spreadRng.next(Land);
  const secondTargetRolls: [Land] real = spreadRng.next(Land);
  const competeRolls: [Land] real = spreadRng.next(Land);

  for (idx, reproRoll, targetRoll, secondTargetRoll) in
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
          propA[t1i, t1j] = true;
        else {
          claimB(propB, bDie, i, j, t1i, t1j);

          if otherB && emptyCount >= 2 {
            const remain = emptyCount - 1;
            const target2 = min((secondTargetRoll * remain): int, remain - 1);
            const (t2i, t2j, ok2) = nthEmptyInDisk(tree, i, j, target2, t1i, t1j);

            if ok2 then
              propB[t2i, t2j] = true;
          }
        }
      }
    }
  }

  for idx in Land {
    if tree[idx] != Empty then continue;

    if propA[idx] && propB[idx] {
      if competeRolls[idx] < winProbB then
        nextTree[idx] = SpeciesB;
      else
        nextTree[idx] = SpeciesA;
    } else if propB[idx] then
      nextTree[idx] = SpeciesB;
    else if propA[idx] then
      nextTree[idx] = SpeciesA;
  }

  for idx in Land do
    if bDie[idx] then
      nextTree[idx] = Empty;

  for idx in Land do
    tree[idx] = nextTree[idx];

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
