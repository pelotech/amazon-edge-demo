#!/bin/sh
set -e

HTML_DIR="/usr/share/nginx/html"

# Copy originals for serving
mkdir -p "${HTML_DIR}/originals"
for f in /data/videos/*.avi; do
  [ -f "$f" ] || continue
  cp "$f" "${HTML_DIR}/originals/"
done

# Convert to MP4
for f in /data/videos/*.avi; do
  [ -f "$f" ] || continue
  base=$(basename "${f%.*}")
  echo "Converting $f -> ${HTML_DIR}/${base}.mp4"
  ffmpeg -i "$f" -y "${HTML_DIR}/${base}.mp4"
done

# Generate index.html with video gallery
cat > "${HTML_DIR}/index.html" <<'HEADER'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Video Gallery</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: #111; color: #eee; font-family: system-ui, sans-serif; padding: 2rem; }
  h1 { text-align: center; margin-bottom: 0.5rem; font-weight: 300; letter-spacing: 0.05em; }
  .header-link { text-align: center; margin-bottom: 2rem; }
  .header-link a { color: #888; text-decoration: none; font-size: 0.9rem; }
  .header-link a:hover { color: #fff; }
  .gallery { max-width: 800px; margin: 0 auto; display: flex; flex-direction: column; gap: 2rem; }
  .card { background: #1a1a1a; border-radius: 8px; overflow: hidden; }
  .card video { width: 100%; display: block; }
  .card .caption { padding: 0.75rem 1rem; font-size: 0.85rem; color: #aaa; }
  .card a { color: #aaa; text-decoration: none; }
  .card a:hover { color: #fff; }
</style>
</head>
<body>
<h1>Video Gallery</h1>
<div class="header-link"><a href="/originals/">View Originals</a></div>
<div class="gallery">
HEADER

for f in "${HTML_DIR}"/*.mp4; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  origname="${name%.mp4}.avi"
  cat >> "${HTML_DIR}/index.html" <<CARD
<div class="card"><video src="${name}" controls preload="metadata"></video><div class="caption"><a href="${name}">${name}</a> | <a href="/originals/${origname}">Original</a></div></div>
CARD
done

cat >> "${HTML_DIR}/index.html" <<'FOOTER'
</div>
</body>
</html>
FOOTER

exec nginx -g 'daemon off;'
