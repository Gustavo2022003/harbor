#!/bin/bash
# Gera a documentação visual a partir dos HTMLs em docs/:
#   docs/manual/Harbor-Manual.pdf          manual completo
#   docs/manual/tutoriais/NN-<tema>.pdf    um PDF por capítulo
#   docs/banners/*.png                     banners do README
# Requer o Google Chrome (modo headless).
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[[ -x "$CHROME" ]] || { echo "❌ Google Chrome não encontrado (defina CHROME=…)"; exit 1; }
chrome() { "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
  --virtual-time-budget=4000 "$@" >/dev/null 2>&1; }

ROOT="file://$PWD"
MANUAL="$ROOT/docs/manual/src/manual.html"

# ── Manual ──────────────────────────────────────────────────────────────
echo "▸ Verificando páginas…"
OVER=$("$CHROME" --headless=new --disable-gpu --allow-file-access-from-files --virtual-time-budget=4000 --dump-dom "$MANUAL" 2>/dev/null \
  | grep -o 'data-overflow="[^"]*"' | sed 's/data-overflow="\(.*\)"/\1/')
[[ -z "$OVER" ]] || { echo "❌ Conteúdo transbordando a página: $OVER"; exit 1; }

echo "▸ Manual completo"
chrome --no-pdf-header-footer --print-to-pdf="docs/manual/Harbor-Manual.pdf" "$MANUAL"

echo "▸ Tutoriais"
rm -rf docs/manual/tutoriais && mkdir -p docs/manual/tutoriais
i=0
for part in instalacao permissoes hud vidro claude github spotify foco pins agenda problemas; do
  i=$((i+1)); out=$(printf "docs/manual/tutoriais/%02d-%s.pdf" "$i" "$part")
  chrome --no-pdf-header-footer --print-to-pdf="$out" "$MANUAL?only=$part"
  echo "  ✓ $out"
done

# ── Banners ─────────────────────────────────────────────────────────────
echo "▸ Banners"
BANNER="$ROOT/docs/banners/src/banner.html"
shot() { chrome --default-background-color=00000000 --force-device-scale-factor=2 --window-size="$2" --screenshot="docs/banners/$1.png" "$3"; echo "  ✓ docs/banners/$1.png"; }
enc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$1"; }

shot hero 1280,400 "$BANNER?kind=hero"
# nome | número | ícone | título | subtítulo
while IFS='|' read -r name n icon title sub; do
  [[ -z "$name" ]] && continue
  shot "$name" 1280,132 "$BANNER?kind=section&n=$n&icon=$(enc "$icon")&title=$(enc "$title")&sub=$(enc "$sub")"
done <<'LIST'
recursos|01|✨|Recursos|Tudo o que cabe no notch
manual|02|📘|Manual e tutoriais|PDFs com o passo a passo de cada configuração
instalacao|03|📦|Instalação|Baixe, arraste e abra
compilar|04|🛠️|Compilar a partir do código|Command Line Tools e um make run
permissoes|05|🔐|Permissões|O que cada uma libera
integracoes|06|🧩|Integrações|Claude Code, GitHub, Spotify e Modo Foco
atalhos|07|⌨️|Atalhos|Tudo a um ⌥ de distância
estrutura|08|🗂️|Estrutura do projeto|Onde fica cada coisa
desenvolvimento|09|🚀|Desenvolvimento e releases|Branches, CI local e publicação
problemas|10|🩺|Solução de problemas|Quando algo não funciona
LIST

echo "✅ Documentação gerada"
