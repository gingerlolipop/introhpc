#!/bin/bash
#SBATCH --time=00:20:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=8G
#SBATCH --output=tree_visualize_%j.out

set -euo pipefail

module load chapel-multicore/2.4.0
module load ffmpeg/7.1.1

VIZ_ROOT="${VIZ_ROOT:-viz}"
THREAD_LIST=(1 2 4 8 16 32)
KEY_CYCLES=(0 3 6 9 12)
FPS=2

SIM_ARGS=(
  --rows=600
  --cols=600
  --steps=12
  --initialTrees=100
  --radius=15
  --seed=12345
  --report=false
)

export CHPL_RT_NUM_THREADS_PER_LOCALE_QUIET=yes

chpl --fast tree_viz.chpl -o tree_viz

mkdir -p "${VIZ_ROOT}/figures"

echo "Generating snapshots and videos under ${VIZ_ROOT}/"
echo

for threads in "${THREAD_LIST[@]}"; do
  tag=$(printf "t%02d" "${threads}")
  frame_dir="${VIZ_ROOT}/${tag}/frames"
  png_dir="${VIZ_ROOT}/${tag}/png"
  video="${VIZ_ROOT}/${tag}/tree_spread_${tag}.mp4"

  rm -rf "${frame_dir}" "${png_dir}"
  mkdir -p "${frame_dir}" "${png_dir}"

  echo "=== ${tag}: ${threads} thread(s) ==="
  CHPL_RT_NUM_THREADS_PER_LOCALE="${threads}" \
    ./tree_viz "${SIM_ARGS[@]}" --outDir="${frame_dir}"

  for ppm in "${frame_dir}"/cycle_*.ppm; do
    base=$(basename "${ppm}" .ppm)
    convert "${ppm}" "${png_dir}/${base}.png"
  done

  ffmpeg -y -loglevel error -framerate "${FPS}" \
    -i "${png_dir}/cycle_%03d.png" \
    -c:v libx264 -pix_fmt yuv420p \
    "${video}"

  echo "Wrote ${video}"
  echo
done

echo "Exporting key-frame stills to ${VIZ_ROOT}/figures/"
ref_png_dir="${VIZ_ROOT}/t01/png"
for cycle in "${KEY_CYCLES[@]}"; do
  label=$(printf "cycle_%03d" "${cycle}")
  cp "${ref_png_dir}/${label}.png" \
     "${VIZ_ROOT}/figures/${label}.png"
done

echo
echo "Done."
echo "  Key frames : ${VIZ_ROOT}/figures/"
echo "  Videos     : ${VIZ_ROOT}/t*/tree_spread_t*.mp4"
