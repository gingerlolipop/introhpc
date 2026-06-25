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
  --reproProbA=0.35
  --reproProbB=0.85
  --winProbB=0.60
  --seed=12345
  --report=false
)

# Species A (greens) and species B (oranges) sample colours at birth cycle 0.
LEGEND_A_COLOR="#1b4332"
LEGEND_B_COLOR="#d00000"

export CHPL_RT_NUM_THREADS_PER_LOCALE_QUIET=yes

make_legend() {
  local out=$1
  local row_h=30
  local top=34
  local h=$(( top + 4 * row_h + 20 ))

  convert -size 240x"${h}" xc:'#faf8f5' \
    -font DejaVu-Sans-Bold -pointsize 14 -fill '#2c2c2c' \
    -annotate +12+22 'Species' \
    "${out}"

  local y=$(( top ))
  convert "${out}" \
    -fill "${LEGEND_A_COLOR}" -draw "rectangle 14,${y} 38,$((y + 18))" \
    -font DejaVu-Sans -pointsize 13 -fill '#2c2c2c' \
    -annotate +48+$((y + 14)) 'A — persistent (greens)' \
    "${out}"

  y=$(( top + row_h ))
  convert "${out}" \
    -fill "${LEGEND_B_COLOR}" -draw "rectangle 14,${y} 38,$((y + 18))" \
    -font DejaVu-Sans -pointsize 13 -fill '#2c2c2c' \
    -annotate +48+$((y + 14)) 'B — invasive (oranges)' \
    "${out}"

  y=$(( top + 2 * row_h ))
  convert "${out}" \
    -fill '#ede8dc' -draw "rectangle 14,${y} 38,$((y + 18))" \
    -font DejaVu-Sans -pointsize 13 -fill '#2c2c2c' \
    -annotate +48+$((y + 14)) 'empty soil' \
    "${out}"

  y=$(( top + 3 * row_h ))
  convert "${out}" \
    -font DejaVu-Sans-Oblique -pointsize 11 -fill '#555555' \
    -annotate +12+$((y + 12)) 'Hue within each species = birth cycle' \
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

ffmpeg -y -loglevel error -framerate "${FPS}" \
  -i "${ref_png_dir}/cycle_%03d.png" \
  -vf "scale=400:-1:flags=lanczos" \
  -loop 0 "${VIZ_ROOT}/figures/tree_spread.gif"

echo
echo "Done."
echo "  Key frames : ${VIZ_ROOT}/figures/"
echo "  Legend     : ${VIZ_ROOT}/figures/legend.png"
echo "  Videos     : ${VIZ_ROOT}/t*/tree_spread_t*.mp4"
