# Harbor ⚓️ — atalhos de desenvolvimento
.PHONY: build run install dist icon signing clean release

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

release:          ## Abre uma release: make release VERSION=2.2.0
	@scripts/release.sh $(VERSION)

clean:            ## Apaga artefatos de build
	@rm -rf .build build dist

help:
	@grep -E '^[a-z]+:.*##' Makefile | sed 's/:.*## /\t/'
