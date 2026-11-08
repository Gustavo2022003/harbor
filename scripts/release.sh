#!/bin/bash
# Prepara e publica uma release.
#
#   scripts/release.sh 2.2.0           → atualiza VERSION, merge dev → main, cria a tag e envia.
#                                        O GitHub Actions (release.yml) compila, assina e publica.
#   scripts/release.sh 2.2.0 --local   → igual, mas compila/assina/publica a partir deste Mac
#                                        (usa o certificado "Harbor Dev" das suas Chaves).
#
# Antes: adicione a seção "## [X.Y.Z] - AAAA-MM-DD" no CHANGELOG.md (na branch dev).
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:-}"
MODE="${2:-}"
[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Uso: scripts/release.sh X.Y.Z [--local]"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "❌ Há mudanças não commitadas."; exit 1; }
[[ "$(git branch --show-current)" == "dev" ]] || { echo "❌ Rode a partir da branch dev."; exit 1; }
grep -q "^## \[$NEW\]" CHANGELOG.md || { echo "❌ Adicione a seção '## [$NEW] - data' no CHANGELOG.md."; exit 1; }
git rev-parse "v$NEW" >/dev/null 2>&1 && { echo "❌ A tag v$NEW já existe."; exit 1; }

echo "$NEW" > VERSION
git add VERSION
git commit -q -m "chore: release v$NEW" || true
git push -q origin dev

git checkout -q main
git pull -q --ff-only origin main
git merge -q --no-ff dev -m "release: v$NEW"
git tag -a "v$NEW" -m "Harbor v$NEW"
git push -q origin main "v$NEW"

if [[ "$MODE" == "--local" ]]; then
  scripts/build.sh --dist
  awk -v v="$NEW" '$0 ~ "^## \\[" v "\\]" {on=1; next} on && /^## \[/ {exit} on {print}' CHANGELOG.md > dist/notes.md
  gh release create "v$NEW" "dist/Harbor-$NEW.zip" "dist/Harbor-$NEW.dmg" \
    --title "Harbor $NEW" --notes-file dist/notes.md --verify-tag
  echo "✅ Release v$NEW publicada: $(gh release view "v$NEW" --json url -q .url)"
else
  echo "✅ Tag v$NEW enviada — o GitHub Actions vai publicar a release (acompanhe: gh run watch)"
fi

git checkout -q dev
