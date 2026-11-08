# Fluxo de desenvolvimento

## Branches

| Branch | Papel |
|---|---|
| `main` | **Produção**. Só recebe merges de `dev` em releases. Cada release vira uma tag `vX.Y.Z`. |
| `dev` | **Desenvolvimento**. Integra as features; é onde o dia a dia acontece. |
| `feat/<nome>`, `fix/<nome>` | Trabalho isolado, aberto a partir de `dev` e mesclado de volta via PR. |

```
feat/x ──► dev ──► main (tag v2.2.0) ──► Release no GitHub
```

## Commits

[Conventional Commits](https://www.conventionalcommits.org/pt-br/), em português:

```
feat(spotify): fila e curtir
fix(notch): bolha some ao trocar de tela
chore: release v2.2.0
```

Escopos comuns: `notch`, `media`, `spotify`, `mic`, `downloads`, `github`, `pins`, `claude`, `glass`, `settings`, `ci`.

## Dia a dia

```bash
git checkout dev && git pull
git checkout -b feat/minha-feature
make run                 # compila e abre
# … código …
git commit -m "feat(x): …"
gh pr create --base dev
```

Antes de abrir o PR, adicione o que mudou na seção `## [Unreleased]` do `CHANGELOG.md`.

## Releases (SemVer)

- **patch** (`2.1.1`): correções.
- **minor** (`2.2.0`): features novas.
- **major** (`3.0.0`): mudanças que quebram algo, como dados ou preferências.

1. Em `dev`, renomeie `## [Unreleased]` para `## [X.Y.Z] - AAAA-MM-DD` e crie um novo `## [Unreleased]` vazio.
2. `make release VERSION=X.Y.Z`: mescla em `main`, cria a tag, compila, assina e publica a release (tudo neste Mac).
