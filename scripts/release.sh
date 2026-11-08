#!/bin/bash
# Prepara uma release: atualiza VERSION e CHANGELOG, faz merge dev → main e cria a tag.
# O GitHub Actions (release.yml) compila, assina e publica a release ao receber a tag.
#
# Uso: scripts/release.sh 2.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:-}"
[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Uso: scripts/release.sh X.Y.Z"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "❌ Há mudanças não commitadas."; exit 1; }
[[ "$(git branch --show-current)" == "dev" ]] || { echo "❌ Rode a partir da branch dev."; exit 1; }
grep -q "## \[$NEW\]" CHANGELOG.md || { echo "❌ Adicione a seção '## [$NEW]' no CHANGELOG.md antes."; exit 1; }

echo "$NEW" > VERSION
git add VERSION
git commit -m "chore: release v$NEW" || true
git push origin dev

git checkout main
git pull --ff-only origin main
git merge --no-ff dev -m "release: v$NEW"
git tag -a "v$NEW" -m "Harbor v$NEW"
git push origin main "v$NEW"
git checkout dev

echo "✅ v$NEW enviada — acompanhe em: gh run watch"
