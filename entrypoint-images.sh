#!/bin/sh
set -e

HTML_DIR="/usr/share/nginx/html"

# Copy originals for serving
mkdir -p "${HTML_DIR}/originals"
for f in /data/images/*.jpg /data/images/*.jpeg; do
  [ -f "$f" ] || continue
  cp "$f" "${HTML_DIR}/originals/"
done

# Convert to WebP
for f in /data/images/*.jpg /data/images/*.jpeg; do
  [ -f "$f" ] || continue
  base=$(basename "${f%.*}")
  echo "Converting $f -> ${HTML_DIR}/${base}.webp"
  cwebp "$f" -o "${HTML_DIR}/${base}.webp"
done

# Generate index.html with image gallery
cat > "${HTML_DIR}/index.html" <<'HEADER'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Image Gallery</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: #111; color: #eee; font-family: system-ui, sans-serif; padding: 2rem; }
  h1 { text-align: center; margin-bottom: 0.5rem; font-weight: 300; letter-spacing: 0.05em; }
  .header-link { text-align: center; margin-bottom: 2rem; }
  .header-link a { color: #888; text-decoration: none; font-size: 0.9rem; }
  .header-link a:hover { color: #fff; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 1.5rem; }
  .card { background: #1a1a1a; border-radius: 8px; overflow: hidden; }
  .card img { width: 100%; height: auto; display: block; }
  .card .caption { padding: 0.75rem 1rem; font-size: 0.85rem; color: #aaa; }
  .card a { color: #aaa; text-decoration: none; }
  .card a:hover { color: #fff; }
</style>
</head>
<body>
<h1>Image Gallery</h1>
<div class="header-link"><a href="/originals/">View Originals</a></div>
<div class="grid">
HEADER

for f in "${HTML_DIR}"/*.webp; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  base="${name%.webp}"
  # Find the matching original (jpg or jpeg)
  origname=""
  for ext in jpg jpeg; do
    if [ -f "${HTML_DIR}/originals/${base}.${ext}" ]; then
      origname="${base}.${ext}"
      break
    fi
  done
  cat >> "${HTML_DIR}/index.html" <<CARD
<div class="card"><a href="${name}"><img src="${name}" alt="${name}"></a><div class="caption"><a href="${name}">${name}</a> | <a href="/originals/${origname}">Original</a></div></div>
CARD
done

cat >> "${HTML_DIR}/index.html" <<'FOOTER'
</div>
</body>
</html>
FOOTER

exec nginx -g 'daemon off;'
