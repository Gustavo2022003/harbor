---
name: release
description: Lança uma nova versão do Harbor de ponta a ponta. Escolhe a versão pelo CHANGELOG, atualiza o README, o manual em PDF, a ARCHITECTURE e o CONTRIBUTING, regera docs e banners, roda o CI local, faz commit e publica com `make release`. Use quando o usuário pedir para "lançar", "publicar", "soltar uma release/versão" ou "fazer o release" do Harbor.
---

# Release do Harbor

Siga os passos **na ordem**. Pare e avise o usuário se algum falhar. Nunca pule o CI e nunca use `--no-verify`.

## 0. Pré-condições
- Branch `dev`, sincronizada com `origin/dev` (`git status -sb`).
- O certificado "Harbor Dev" está instalado (`security find-identity -p codesigning | grep "Harbor Dev"`). Se não estiver, peça ao usuário para rodar `make signing`.
- O `gh` está autenticado (`gh auth status`).
- Nunca envie segredos de assinatura para o GitHub, e nunca crie GitHub Actions: o projeto não usa.

## 1. Escolher a versão (SemVer)
Leia `## [Unreleased]` no `CHANGELOG.md` e a versão atual em `VERSION`:
- só `### Corrigido` → **patch** (X.Y.Z+1);
- algum `### Adicionado` ou `### Alterado` sem quebra → **minor** (X.Y+1.0);
- algo que quebre preferências ou dados, ou exija ação manual → **major**.

Se `[Unreleased]` estiver vazio, pare: não há o que lançar. Se o usuário já disse a versão, use a dele.

## 2. Revisar o CHANGELOG
- Confira se tudo o que mudou desde a última tag está lá: `git log --oneline $(git describe --tags --abbrev=0)..HEAD` e `git diff --stat` para o que ainda não tem commit.
- Junte entradas duplicadas e reescreva as que contradizem uma decisão posterior. Exemplo: um recurso adicionado e depois removido na mesma rodada sai das notas.
- Renomeie para `## [X.Y.Z] - AAAA-MM-DD` (data de hoje) e crie um `## [Unreleased]` vazio acima.

## 3. Atualizar a documentação
Para cada item do changelog, veja se ele aparece onde deve:

| Arquivo | O que conferir |
|---|---|
| `README.md` | Tabela "Notch fechado" (atividades e prioridade), tabela de abas, Instalação/Atualizações, Permissões, Integrações, Atalhos, Estrutura (pastas e arquivos novos), Desenvolvimento (exemplos com a versão nova), Solução de problemas |
| `docs/ARCHITECTURE.md` | Prioridade do notch fechado, tabela de serviços (serviço novo = linha nova), views, convenções e modos de depuração (`--snapshot`, `--update-now`) |
| `CONTRIBUTING.md` | Fluxo de branches e releases, se mudou |
| `docs/manual/src/manual.html` | Textos de interface (nomes de ajustes e menus), tutoriais afetados e a tabela de problemas. Use `<span class="ui">`, `<span class="path">…<i>›</i>…</span>` e `<code>`. Não use box-shadow, filter nem backdrop-filter (quebram no Preview) |

- Os nomes de botões e ajustes nos docs devem ser **exatamente** os da UI. Confira com `grep -rn 'Toggle("\|Button("' Sources/Harbor/Views`.
- Escreva em pt-BR, no mesmo tom do resto.

Depois rode `make docs`. O script falha se alguma página do manual transbordar: nesse caso, encurte o texto e rode de novo. Se uma tela mudou muito, recapture as imagens em `docs/manual/src/img/` com `--snapshot`.

## 4. Verificar
1. `scripts/ci.sh` (completo, não use `--quick`) tem que passar.
2. Gere as capturas: `make build && build/Harbor.app/Contents/MacOS/Harbor --snapshot <pasta-de-rascunho>`. Abra as que mudaram e confira se nada saiu cortado ou sobreposto.
   - Para capturar uma seção específica dos Ajustes, mude `defaults write com.gustavo.harbor settings.section <general|visual|integrations|pins|about>`.
   - Antes, leia o valor atual e restaure-o no final.
3. Se a release mexe no hook do Claude, no esquema `harbor://` ou na atualização automática, teste o fluxo real. Veja as dicas de teste em "Convenções", no `docs/ARCHITECTURE.md`.

## 5. Commit e publicação
```bash
git add -A
git commit -m "feat: …"   # Conventional Commits; um commit por assunto, se fizer sentido
git commit -am "docs(changelog): X.Y.Z"   # se o CHANGELOG ficou num commit separado
make release VERSION=X.Y.Z
```
O `release.sh` faz o resto:
- roda o CI de novo e escreve `VERSION`;
- faz o merge de `dev` em `main` e cria a tag;
- compila e assina com "Harbor Dev";
- gera `dist/Harbor-X.Y.Z.zip` e `.dmg`;
- publica no GitHub Releases, com as notas extraídas do CHANGELOG;
- volta para a `dev`.

## 6. Conferir e reportar
- `gh release view vX.Y.Z --json assets,body`: tem que ter o `.dmg` e o `.zip`, e as notas certas.
- `git log origin/main --oneline -2` deve mostrar `release: vX.Y.Z`.
- Reabra o build local: `pkill -x Harbor; open build/Harbor.app`.
- Responda ao usuário com o link da release, o resumo das novidades e o que ele precisa fazer para atualizar:
  - a partir da v2.4.0: Ajustes › Sobre › Atualizações;
  - antes disso: o `.dmg` ou `make install`.
