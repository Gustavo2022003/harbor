#!/bin/bash
# CI local do Harbor: roda antes de cada push (hook .githooks/pre-push) e de cada release.
#
#   scripts/ci.sh          # todas as verificações
#   scripts/ci.sh --quick  # sem o teste de fumaça (só compila e valida)
#
# Pular em uma emergência: git push --no-verify   (ou HARBOR_SKIP_CI=1)
set -uo pipefail
cd "$(dirname "$0")/.."

QUICK=0; [[ "${1:-}" == "--quick" ]] && QUICK=1
OUT=".build/ci"; mkdir -p "$OUT"
FAILS=0; START=$(date +%s)

step() { printf "\033[1m▸ %s\033[0m\n" "$1"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
bad()  { printf "  \033[31m✗\033[0m %s\n" "$1"; FAILS=$((FAILS+1)); }
warn() { printf "  \033[33m!\033[0m %s\n" "$1"; }

# 1. Projeto ───────────────────────────────────────────────────────────────
step "Projeto"
V="$(tr -d '[:space:]' < VERSION)"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && ok "VERSION $V" || bad "VERSION inválido: '$V'"
grep -q '^## \[Unreleased\]' CHANGELOG.md && ok "CHANGELOG tem [Unreleased]" || bad "CHANGELOG sem a seção ## [Unreleased]"
plutil -lint -s Resources/Info.plist && ok "Info.plist válido" || bad "Info.plist inválido"
[[ -f Resources/AppIcon.icns ]] && ok "AppIcon.icns" || bad "Resources/AppIcon.icns ausente"

for s in scripts/*.sh .githooks/*; do
  bash -n "$s" 2>/dev/null || bad "erro de sintaxe em $s"
done
ok "sintaxe dos scripts"

# 2. Convenções e segurança ─────────────────────────────────────────────────
step "Convenções e segurança"
if grep -rnE '^\s*@State\b' Sources >/dev/null; then
  bad "@State encontrado (use @Local):"; grep -rnE '^\s*@State\b' Sources | sed 's/^/      /'
else ok "sem @State"; fi

TRACKED_SECRETS=$(git ls-files | grep -E '\.(p12|pem|key|mobileprovision)$|p12-password' || true)
[[ -z "$TRACKED_SECRETS" ]] && ok "nenhum certificado/chave no git" || bad "arquivos sensíveis no git: $TRACKED_SECRETS"
if git grep -nIE 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}' -- . ':!scripts/ci.sh' >/dev/null 2>&1; then
  bad "possível segredo no código:"; git grep -nIlE 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|ghp_[A-Za-z0-9]{30,}|github_pat_' -- . ':!scripts/ci.sh' | sed 's/^/      /'
else ok "nenhum token/chave privada no código"; fi

# 3. Compilação ────────────────────────────────────────────────────────────
step "Compilação (release)"
if swift build -c release >"$OUT/build.log" 2>&1; then
  W=$(sed -E 's/\x1b\[[0-9;]*m//g' "$OUT/build.log" | grep -E '^/.*: warning:' | sort -u | wc -l | tr -d ' ')
  ok "compilou"; [[ "$W" -gt 0 ]] && warn "$W avisos do compilador (veja $OUT/build.log)"
else
  bad "falhou ao compilar:"
  sed -E 's/\x1b\[[0-9;]*m//g' "$OUT/build.log" | grep -E '^/.*:[0-9]+:[0-9]+: error:' \
    | sed "s|$PWD/||" | sort -u | head -15 | sed 's/^/      /'
fi

# 4. Teste de fumaça: abre o app e renderiza todas as abas ─────────────────
if [[ $QUICK -eq 0 && $FAILS -eq 0 ]]; then
  step "Teste de fumaça (renderiza cada aba)"
  APP="$OUT/Harbor.app"; SHOTS="$OUT/shots"
  rm -rf "$APP" "$SHOTS"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SHOTS"
  cp .build/release/Harbor "$APP/Contents/MacOS/"
  cp Resources/Info.plist "$APP/Contents/"; cp Resources/AppIcon.icns "$APP/Contents/Resources/"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
  # A cópia de teste não pode reivindicar o esquema harbor:// (roubaria os eventos do Claude do app de verdade)
  /usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$APP/Contents/Info.plist" 2>/dev/null || true
  codesign --force --sign - "$APP" 2>/dev/null   # ad-hoc: não toca nas Chaves

  "$APP/Contents/MacOS/Harbor" --snapshot "$PWD/$SHOTS" >"$OUT/smoke.log" 2>&1 &
  PID=$!
  for _ in $(seq 1 90); do kill -0 $PID 2>/dev/null || break; sleep 1; done
  if kill -0 $PID 2>/dev/null; then
    kill $PID; bad "o app não terminou em 90 s (travou?)"
  else
    wait $PID; RC=$?
    TABS=$(grep -A1 'enum NookTab' Sources/Harbor/App/NotchViewModel.swift | grep -oE 'case .*' | sed 's/case//' | tr ',' '\n' | grep -c '[a-z]')
    EXPECTED=$((TABS + 1))   # + o notch fechado
    N=$(find "$SHOTS" -name '*.png' -size +1k | wc -l | tr -d ' ')
    if [[ $RC -ne 0 ]]; then bad "o app saiu com código $RC (veja $OUT/smoke.log)"
    elif [[ "$N" -lt "$EXPECTED" ]]; then bad "renderizou $N de $EXPECTED abas"
    else ok "abriu e renderizou $N abas ($SHOTS)"; fi
  fi
  # Remove a cópia de teste do LaunchServices e do disco
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  [[ -x $LSREGISTER ]] && "$LSREGISTER" -u "$APP" 2>/dev/null || true
  rm -rf "$APP"
fi

# ──────────────────────────────────────────────────────────────────────────
T=$(( $(date +%s) - START ))
if [[ $FAILS -eq 0 ]]; then
  printf "\n\033[32;1m✅ CI local passou\033[0m (%ss)\n" "$T"
else
  printf "\n\033[31;1m❌ CI local falhou: %s problema(s)\033[0m (%ss)\n" "$FAILS" "$T"; exit 1
fi
