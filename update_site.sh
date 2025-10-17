#!/usr/bin/env bash
set -euo pipefail

# ---------- Inputs ----------
GA_ID="${1:-}"
SITE_URL="${2:-}"

if [[ -z "$GA_ID" || -z "$SITE_URL" ]]; then
  echo "Usage: $0 GA_MEASUREMENT_ID SITE_URL"
  echo "Example: $0 G-XXXXXXXXXX https://gerhenry.github.io/Abgen/"
  exit 1
fi

# ---------- Ensure tools ----------
if ! command -v sed >/dev/null 2>&1; then
  echo "Installing sed (Termux) ..."
  pkg install -y sed >/dev/null 2>&1 || true
fi

# ---------- Snippets ----------
read -r -d '' GA_SNIPPET <<GA
<!-- Google tag (gtag.js) -->
<script async src="https://www.googletagmanager.com/gtag/js?id=${GA_ID}"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', '${GA_ID}');
</script>
GA

read -r -d '' SEO_BLOCK <<SEO
<link rel="canonical" href="${SITE_URL}"/>
<meta property="og:title" content="$(basename "$(pwd)")"/>
<meta property="og:description" content="Open-source IC design tools and projects."/>
<meta property="og:type" content="website"/>
<meta property="og:url" content="${SITE_URL}"/>
<meta name="twitter:card" content="summary_large_image"/>
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "SoftwareSourceCode",
  "name": "$(basename "$(pwd)")",
  "url": "${SITE_URL}",
  "programmingLanguage": "HTML, JavaScript",
  "license": "https://opensource.org/licenses/MIT",
  "creator": {"@type":"Person","name":"Ger Henry"}
}
</script>
SEO

# ---------- Functions ----------
inject_into_head () {
  local file="$1"
  # Skip if GA already present
  if grep -qi "googletagmanager.com/gtag/js" "$file"; then
    echo "  • GA already in $file — skipping GA."
  else
    sed -i '0,/<head[^>]*>/s//&\n<!-- GA_INSERT -->/' "$file"
    sed -i "0,/<\!-- GA_INSERT -->/s//${GA_SNIPPET//$'\n'/\\n}/" "$file"
    echo "  ✓ GA injected into $file"
  fi

  # Canonical / OG / JSON-LD (guard by canonical)
  if grep -qi '<link[^>]*rel=["'\'']canonical' "$file"; then
    echo "  • SEO tags already in $file — skipping SEO."
  else
    sed -i '0,/<head[^>]*>/s//&\n<!-- SEO_INSERT -->/' "$file"
    sed -i "0,/<\!-- SEO_INSERT -->/s//${SEO_BLOCK//$'\n'/\\n}/" "$file"
    echo "  ✓ SEO block injected into $file"
  fi
}

# ---------- Work ----------
echo "Scanning for index.html files…"
mapfile -t HTMLS < <(find . -type f -iname "index.html")

if [[ ${#HTMLS[@]} -eq 0 ]]; then
  echo "No index.html files found — creating a minimal one at ./index.html"
  cat > index.html <<MINI
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>$(basename "$(pwd)")</title></head>
<body><h1>$(basename "$(pwd)")</h1><p>Site bootstrap.</p></body></html>
MINI
  HTMLS=( "./index.html" )
fi

for f in "${HTMLS[@]}"; do
  inject_into_head "$f"
done

# robots.txt
if [[ ! -f robots.txt ]]; then
  cat > robots.txt <<ROB
User-agent: *
Allow: /
Sitemap: ${SITE_URL%/}/sitemap.xml
ROB
  echo "  ✓ robots.txt created"
else
  echo "  • robots.txt exists"
fi

# sitemap.xml (simple, lists root + sub-indexes)
echo "Building sitemap.xml ..."
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
  echo "  <url><loc>${SITE_URL%/}/</loc></url>"
  while IFS= read -r p; do
    # turn ./path/index.html into /path/
    clean="${p#./}"
    loc="${SITE_URL%/}/${clean%/index.html}/"
    echo "  <url><loc>${loc}</loc></url>"
  done < <(printf "%s\n" "${HTMLS[@]}")
  echo '</urlset>'
} > sitemap.xml
echo "  ✓ sitemap.xml written"

# ---------- Commit & push ----------
git add -A
git commit -m "SEO + GA + sitemap/robots refresh for $(basename "$(pwd)")" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
echo "Done."
