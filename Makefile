# Harbor ⚓️ — atalhos de desenvolvimento
.PHONY: build run install dist icon signing clean release release-local help

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

release:          ## Release via GitHub Actions: make release VERSION=2.2.0
	@scripts/release.sh $(VERSION)

release-local:    ## Release compilada e publicada deste Mac: make release-local VERSION=2.2.0
	@scripts/release.sh $(VERSION) --local

clean:            ## Apaga artefatos de build
	@rm -rf .build build dist

help:
	@grep -E '^[a-z]+:.*##' Makefile | sed 's/:.*## /\t/'
