#!/bin/bash
#SBATCH --time=00:30:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=16G
#SBATCH --output=tree_benchmark_%j.out

set -euo pipefail

module load chapel-multicore/2.4.0

# Compile both programs with compiler optimizations.
chpl --fast tree2.chpl -o tree
chpl --fast tree_parallel.chpl -o tree_parallel

# Large enough to make parallel overhead less dominant.
ARGS=(
  --rows=1200
  --cols=1200
  --steps=12
  --treesPerCluster=100
  --numClusters=2
  --clusterSeparation=200
  --radius=15
  --seed=12345
  --report=false
)

REPEATS=3
MAX_THREADS=${SLURM_CPUS_PER_TASK}
THREAD_LIST=(1 2 4 8 16 32)

export CHPL_RT_NUM_THREADS_PER_LOCALE_QUIET=yes

extract_time () {
  awk '/Simulation finished/{print $(NF-1)}'
}

extract_count () {
  awk '/Final tree count/{print $4}'
}

average () {
  awk -v total="$1" -v n="$2" 'BEGIN {printf "%.6f", total/n}'
}

add () {
  awk -v a="$1" -v b="$2" 'BEGIN {printf "%.12f", a+b}'
}

divide () {
  awk -v a="$1" -v b="$2" 'BEGIN {printf "%.4f", a/b}'
}


echo "Problem: ${ARGS[*]}"
echo "Allocated CPUs: ${MAX_THREADS}"
echo

# Serial baseline.
serial_total=0
serial_count=""

for rep in $(seq 1 "${REPEATS}"); do
  out=$(CHPL_RT_NUM_THREADS_PER_LOCALE=1 ./tree "${ARGS[@]}")
  t=$(printf '%s\n' "$out" | extract_time)
  c=$(printf '%s\n' "$out" | extract_count)

  serial_total=$(add "$serial_total" "$t")
  serial_count="$c"

  echo "serial repetition ${rep}: ${t} s, trees=${c}"
done

serial_mean=$(average "$serial_total" "$REPEATS")

echo
echo "threads,mean_seconds,speedup,tree_count" \
  > "tree_scaling_${SLURM_JOB_ID}.csv"

# Run the parallel executable with several thread counts.
for threads in "${THREAD_LIST[@]}"; do
  if (( threads > MAX_THREADS )); then
    continue
  fi

  parallel_total=0
  parallel_count=""

  for rep in $(seq 1 "${REPEATS}"); do
    out=$(CHPL_RT_NUM_THREADS_PER_LOCALE="$threads" \
          ./tree_parallel "${ARGS[@]}")
    t=$(printf '%s\n' "$out" | extract_time)
    c=$(printf '%s\n' "$out" | extract_count)

    if [[ "$c" != "$serial_count" ]]; then
      echo "ERROR: serial and parallel tree counts differ."
      echo "serial=${serial_count}, parallel=${c}, threads=${threads}"
      exit 1
    fi

    parallel_total=$(add "$parallel_total" "$t")
    parallel_count="$c"

    echo "parallel ${threads} threads, repetition ${rep}: ${t} s"
  done

  parallel_mean=$(average "$parallel_total" "$REPEATS")
  speedup=$(divide "$serial_mean" "$parallel_mean")

  echo "${threads},${parallel_mean},${speedup},${parallel_count}" \
    >> "tree_scaling_${SLURM_JOB_ID}.csv"
done

echo
echo "Serial mean: ${serial_mean} s"
echo
column -s, -t "tree_scaling_${SLURM_JOB_ID}.csv" || \
  cat "tree_scaling_${SLURM_JOB_ID}.csv"

echo
echo "Results saved to tree_scaling_${SLURM_JOB_ID}.csv"
