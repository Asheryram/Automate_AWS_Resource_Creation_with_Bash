#!/usr/bin/env bash
set -euo pipefail

# generate_images.sh
# Convert text output files in ./screenshots/*.txt into PNG images using ImageMagick

OUT_DIR="$(pwd)/screenshots"
mkdir -p "$OUT_DIR"

if ! command -v convert >/dev/null 2>&1; then
  echo "ImageMagick 'convert' is required. Install it (e.g. 'sudo apt install imagemagick')."
  exit 1
fi

shopt -s nullglob
for txt in "$OUT_DIR"/*.txt; do
  base=$(basename "$txt" .txt)
  out="$OUT_DIR/${base}.png"

  # Try rendering by feeding text via stdin to avoid ImageMagick security-policy errors
  if convert -background white -fill black -font DejaVu-Sans-Mono -pointsize 12 \
       -size 1200x caption:@- "$out" < "$txt" 2>/dev/null; then
    echo "Created: $out"
  else
    # Fallback: read file content and render via inline caption (may be slower/long)
    echo "Primary method failed; attempting fallback rendering for $txt"
    content=$(sed 's/"/\\\"/g' "$txt")
    if convert -background white -fill black -font DejaVu-Sans-Mono -pointsize 12 \
         -size 1200x caption:"$content" "$out" 2>/dev/null; then
      echo "Created (fallback): $out"
    else
      echo "Failed to create image for $txt - check ImageMagick policy or install other tools (enscript/wkhtmltoimage)"
    fi
  fi
done

if compgen -G "$OUT_DIR/*.txt" >/dev/null; then
  echo "All done. PNGs saved in: $OUT_DIR"
else
  echo "No .txt files found in $OUT_DIR. Run the output capture helper first (capture_outputs.sh)."
fi
