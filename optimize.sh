#!/usr/bin/env bash
# Optimise les médias du portfolio pour un cadre d'affichage de 854x480.
# Originaux intacts ; sortie dans optimized/.
#   Images : WebP, dimensionnées pour couvrir 2x le cadre (1708x960), jamais agrandies.
#   Vidéos : H.264 MP4 (compatible partout), ~1,5x le cadre (couvre 1280x720),
#            30 fps max, sans audio, faststart pour la lecture en streaming.
set -euo pipefail
cd "$(dirname "$0")"

OUT=optimized
mkdir -p "$OUT/images" "$OUT/videos"

# Facteur d'échelle "cover" pour une boîte BWxBH, sans agrandissement.
# Les médias en portrait sont "contain" (hauteur = BH).
scale_dims() { # w h BW BH -> "W H" (pairs)
  awk -v w="$1" -v h="$2" -v bw="$3" -v bh="$4" 'BEGIN{
    if (h > w) s = bh / h; else { s = bw / w; if (bh / h > s) s = bh / h }
    if (s > 1) s = 1
    W = int(w * s / 2 + 0.5) * 2; H = int(h * s / 2 + 0.5) * 2
    print W, H }'
}

for f in images/*; do
  name=$(basename "$f"); base="${name%.*}"; ext="${name##*.}"
  case "$ext" in
    webp) cp "$f" "$OUT/images/$name"; continue ;;   # déjà optimisées, éviter une double compression
    jpg|jpeg|png) ;;
    *) continue ;;
  esac
  read -r w h < <(magick identify -format "%w %h\n" "$f")
  read -r W H < <(scale_dims "$w" "$h" 1708 960)
  echo "IMG  $name  ${w}x${h} -> ${W}x${H}"
  magick "$f" -filter Lanczos -resize "${W}x${H}!" -strip "$OUT/images/$base.tmp.png"
  cwebp -quiet -q 82 -m 6 -sharp_yuv -metadata none "$OUT/images/$base.tmp.png" -o "$OUT/images/$base.webp"
  rm "$OUT/images/$base.tmp.png"
done

for f in videos/*.mp4; do
  name=$(basename "$f")
  read -r w h < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$f" | tr x ' ')
  read -r W H < <(scale_dims "$w" "$h" 1280 720)
  fps=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$f")
  fps=$(awk -v r="$fps" 'BEGIN{split(r,a,"/"); v=a[1]/(a[2]?a[2]:1); print (v>30?30:r)}')
  echo "VID  $name  ${w}x${h} -> ${W}x${H}"
  ffmpeg -v error -y -i "$f" -an -map_metadata -1 \
    -vf "scale=${W}:${H}:flags=lanczos,fps=$fps" \
    -c:v libx264 -preset veryslow -crf 25 -profile:v high -pix_fmt yuv420p \
    -movflags +faststart "$OUT/videos/$name"
  # Si le réencodage n'apporte rien, garder le flux original (remuxé en faststart, sans audio).
  if [ "$(stat -f%z "$OUT/videos/$name")" -ge "$(stat -f%z "$f")" ]; then
    echo "     -> pas de gain, flux original conservé"
    ffmpeg -v error -y -i "$f" -an -map_metadata -1 -c:v copy -movflags +faststart "$OUT/videos/$name"
  fi
done

echo; du -sh images videos "$OUT/images" "$OUT/videos"
