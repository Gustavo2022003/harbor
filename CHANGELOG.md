# Changelog

Todas as mudanças relevantes do Harbor. Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e [SemVer](https://semver.org/lang/pt-BR/).

## [Unreleased]

## [2.1.0] - 2026-11-08

### Adicionado
- **Mudo global do microfone** (⌥M) com bolha: laranja quando um app usa o microfone, vermelha no mudo.
- **Downloads ao vivo** no notch (Chrome, Edge, Brave, Safari e Firefox). Ao concluir, o arquivo vai para a Bandeja.
- **Badges do Dock** nas bolhas de apps fixados.
- **Aba PRs**: status dos checks de CI e das revisões dos seus PRs, PRs aguardando sua revisão e avisos quando algo muda.
- **Spotify**: curtir a música atual e ver/pular para músicas da fila (Web API, login OAuth PKCE).
- Certificado de assinatura estável ("Harbor Dev"): as permissões não se perdem mais a cada build.
- Estrutura de repositório: Makefile, scripts de build/release/assinatura, CI e releases no GitHub, documentação.

### Alterado
- Bolhas de apps fixados agora ficam à direita do notch, junto das demais.
- Atalhos em Ajustes exibidos em duas colunas; versão lida do bundle.

## [2.0.0] - 2026-11-08

### Adicionado
- Atalhos globais: ⌥Espaço (abrir/fechar), ⌥V (histórico), ⌥N (nota), ⌥⇧C (conta-gotas), ⌥P (fixar app).
- Avisos no notch fechado: volume, brilho, carregador, bateria fraca, fones Bluetooth e timer concluído.
- Substituição do aviso nativo de volume/brilho do macOS (requer Acessibilidade).
- Integração com Claude Code via hooks: "trabalhando", "pronto" e "pede permissão".
- Busca no histórico de cópias.
- Visualizador de áudio real (FFT do áudio do sistema) com intensidade ajustável.
- Reuniões: contagem regressiva no notch e botão "Entrar" (Meet, Zoom, Teams…).
- Aba Ferramentas: nota rápida, conta-gotas e monitor de rede.
- Timer de foco integrado ao Modo Foco do macOS via app Atalhos.
- AirDrop na Bandeja.
- Apps fixados: viram bolhas ao lado do notch quando você sai deles.
- Odômetro do mouse com unidades divertidas e bolha fixável.
- Acabamentos: brilho "vivo" com a música, escolha de tela, ocultar em tela cheia e animações de entrada/saída.
- Liquid Glass: motores Refração (shader Metal), AppKit e SwiftUI.
- Ajustes reorganizados em seções (Geral, Visual, Integrações, Apps fixados).

## [1.0.0] - 2026-11-07

### Adicionado
- Primeira versão: island no notch com mídia (Spotify/Música), CPU/bateria, timer Foco/Pausa, tarefas, agenda, bandeja de arquivos, espelho (câmera 1:1), histórico de cópias e temas do visualizador.
