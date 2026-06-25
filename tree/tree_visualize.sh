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
STEPS=12
LEGEND="${VIZ_ROOT}/legend.png"

SIM_ARGS=(
  --rows=360
  --cols=360
  --steps="${STEPS}"
  --k=4
  --minTreesPerCluster=10
  --maxTreesPerCluster=100
  --radius=15
  --seed=12345
  --report=false
)

# Must match ageR/G/B in tree_viz.chpl (cycles 0..12).
LEGEND_COLORS=(
  "#1b4332" "#2d6a4f" "#40916c" "#52b788" "#74c494" "#95d5b2"
  "#b7e4c7" "#f4d35d" "#ee9638" "#f95738" "#c9184a" "#720957" "#3a0ca3"
)

export CHPL_RT_NUM_THREADS_PER_LOCALE_QUIET=yes

make_legend() {
  local out=$1
  local row_h=26
  local top=34
  local h=$(( top + (STEPS + 1) * row_h + 16 ))

  convert -size 200x"${h}" xc:'#faf8f5' \
    -font DejaVu-Sans-Bold -pointsize 14 -fill '#2c2c2c' \
    -annotate +12+22 'Birth cycle' \
    "${out}"

  local y
  for cycle in $(seq 0 "${STEPS}"); do
    y=$(( top + cycle * row_h ))
    local color="${LEGEND_COLORS[$cycle]}"
    convert "${out}" \
      -fill "${color}" -draw "rectangle 14,${y} 38,$((y + 18))" \
      -font DejaVu-Sans -pointsize 13 -fill '#2c2c2c' \
      -annotate +48+$((y + 14)) "${cycle}" \
      "${out}"
  done

  convert "${out}" \
    -fill '#ede8dc' -draw "rectangle 14,$(( top + (STEPS + 1) * row_h )) 38,$(( top + (STEPS + 1) * row_h + 18 ))" \
    -font DejaVu-Sans -pointsize 13 -fill '#2c2c2c' \
    -annotate +48+$(( top + (STEPS + 1) * row_h + 14 )) 'empty' \
    "${out}"
}

frame_with_legend() {
  local ppm=$1
  local png=$2
  convert "${ppm}" "${LEGEND}" +append -bordercolor '#faf8f5' -border 8 "${png}"
}

chpl --fast tree_viz.chpl -o tree_viz

mkdir -p "${VIZ_ROOT}/figures"
make_legend "${LEGEND}"

echo "Generating age-coloured snapshots and videos under ${VIZ_ROOT}/"
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
    frame_with_legend "${ppm}" "${png_dir}/${base}.png"
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

cp "${LEGEND}" "${VIZ_ROOT}/figures/legend.png"

echo
echo "Done."
echo "  Key frames : ${VIZ_ROOT}/figures/"
echo "  Legend     : ${VIZ_ROOT}/figures/legend.png"
echo "  Videos     : ${VIZ_ROOT}/t*/tree_spread_t*.mp4"
