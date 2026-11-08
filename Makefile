# Harbor ⚓️ — atalhos de desenvolvimento
.PHONY: build run install dist icon signing ci hooks clean release help

build:            ## Compila build/Harbor.app
	@scripts/build.sh

run:              ## Compila e abre
	@scripts/build.sh --run

install:          ## Compila e instala em /Applications
	@scripts/build.sh --install

dist:             ## Gera dist/Harbor-<versão>.zip e .dmg
	@scripts/build.sh --dist

icon:             ## Regera Resources/AppIcon.icns a partir de scripts/make-icon.swift
	@scripts/make-icon.sh

signing:          ## Cria o certificado "Harbor Dev" (uma vez por Mac)
	@scripts/setup-signing.sh

ci:               ## CI local: valida, compila e abre o app renderizando cada aba
	@scripts/ci.sh

hooks:            ## Ativa o CI automático antes de cada git push (uma vez por clone)
	@git config core.hooksPath .githooks && echo "✅ Hook pre-push ativo"

release:          ## CI + compila, assina e publica: make release VERSION=2.2.0
	@scripts/release.sh $(VERSION)

clean:            ## Apaga artefatos de build
	@rm -rf .build build dist

help:
	@grep -E '^[a-z]+:.*##' Makefile | sed 's/:.*## /\t/'
