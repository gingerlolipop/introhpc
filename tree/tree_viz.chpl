/*
  Two-species parallel spread with PPM snapshot output.

  Cell encoding: species * 1000 + (birthCycle + 1), where species is 1 (A) or
  2 (B). Species A is drawn in blues; species B in oranges (Okabe–Ito,
  colorblind-friendly pair).
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
config const reproProbA = 0.35;
config const reproProbB = 0.85;
config const winProbB = 0.60;
config const seed = 12345;
config const report = true;
config const outDir = "frames";

const Empty = 0;
const SpeciesA = 1;
const SpeciesB = 2;

const Land: domain(2) = {1..rows, 1..cols};
const maxBirth = steps;

var tree: [Land] int;
var nextTree: [Land] atomic int;
var propA: [Land] atomic int;
var propB: [Land] atomic int;
var bDie:  [Land] atomic int;

var founderRng = new randomStream(real, seed);
var spreadRng  = new randomStream(real, seed + 1);

const emptyR = 237: int(8);
const emptyG = 232: int(8);
const emptyB = 220: int(8);

// Species A — blues (Okabe–Ito #0072B2 → #56B4E9; darker founders → lighter spread).
const aR = [  0,  0,  0,  0,  0, 26, 51, 77, 86, 122, 157, 184, 208]: [0..maxBirth] int(8);
const aG = [ 68, 76, 89, 99, 114, 138, 163, 180, 180, 197, 213, 226, 236]: [0..maxBirth] int(8);
const aB = [136, 136, 153, 168, 178, 194, 210, 225, 233, 239, 244, 248, 251]: [0..maxBirth] int(8);

// Species B — oranges (Okabe–Ito #D55E00 → #E69F00 → #F0E442).
const bR = [153, 179, 204, 213, 230, 238, 245, 255, 255, 255, 255, 255, 255]: [0..maxBirth] int(8);
const bG = [ 76,  92, 102,  94, 159, 170, 184, 204, 217, 229, 240, 248, 252]: [0..maxBirth] int(8);
const bB = [  0,   0,   0,   0,   0,  34,  77, 102, 140, 168, 196, 224, 240]: [0..maxBirth] int(8);


proc occupied(val: int): bool {
  return val != Empty;
}


proc speciesOf(val: int): int {
  return val / 1000;
}


proc birthAge(val: int): int {
  return (val % 1000) - 1;
}


proc encode(species: int, birthCycle: int): int {
  return species * 1000 + birthCycle + 1;
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
        const sp = speciesOf(val);
        const age = min(birthAge(val), maxBirth);

        if sp == SpeciesA {
          w.writeBinary(aR[age]);
          w.writeBinary(aG[age]);
          w.writeBinary(aB[age]);
        } else {
          w.writeBinary(bR[age]);
          w.writeBinary(bG[age]);
          w.writeBinary(bB[age]);
        }
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
      grid[i, j] = encode(species, 0);
      planted += 1;
    }
  }
}


if !exists(outDir) then
  mkdir(outDir, parents=true);


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

writeSnapshot(0);

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
    const val = tree[i, j];

    if !occupied(val) then continue;

    const species = speciesOf(val);
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
              if speciesOf(tree[ni, nj]) == SpeciesB then
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
        nextTree[idx].write(encode(SpeciesB, cycle));
      else
        nextTree[idx].write(encode(SpeciesA, cycle));
    } else if propB[idx].read() > 0 then
      nextTree[idx].write(encode(SpeciesB, cycle));
    else if propA[idx].read() > 0 then
      nextTree[idx].write(encode(SpeciesA, cycle));
  }

  forall idx in Land do
    if bDie[idx].read() > 0 then
      nextTree[idx].write(Empty);

  forall idx in Land do
    tree[idx] = nextTree[idx].read();

  writeSnapshot(cycle);

  if report {
    var countA = 0;
    var countB = 0;
    for idx in Land {
      if speciesOf(tree[idx]) == SpeciesA then countA += 1;
      else if speciesOf(tree[idx]) == SpeciesB then countB += 1;
    }
    writeln("cycle ", cycle, ": ", countA + countB,
            " trees (A=", countA, ", B=", countB, ")");
  }
}

timer.stop();

var finalA = 0;
var finalB = 0;
for idx in Land {
  if speciesOf(tree[idx]) == SpeciesA then finalA += 1;
  else if speciesOf(tree[idx]) == SpeciesB then finalB += 1;
}

writeln("Final tree count: ", finalA + finalB,
        " (A=", finalA, ", B=", finalB, ")");
writeln("Snapshots written to ", outDir, "/");
writeln("Simulation finished in ", timer.elapsed(), " seconds");
