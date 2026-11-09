# Changelog

Todas as mudanças relevantes do Harbor. Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e [SemVer](https://semver.org/lang/pt-BR/).

## [Unreleased]

### Adicionado
- Aba temporária **Agora**: aparece na barra de abas só enquanto algo está em execução (Claude Code, download, timer, reunião próxima) e abre sozinha ao passar o mouse no notch com uma atividade. Mostra os detalhes de cada uma: pedido, ferramenta em uso e última mensagem do Claude; progresso, velocidade e tempo restante dos downloads; controles do timer; botão de entrar na reunião. As outras abas continuam ao lado; ao fechar, o notch volta para a aba em que você estava.

### Corrigido
- Eventos do Claude Code iam parar em outra cópia do app (a do teste do CI), que abria e fechava, e o notch deixava de mostrar o Claude. O hook agora entrega os eventos ao Harbor que está aberto (`~/.harbor/app-path`; o script é atualizado sozinho ao abrir o app), e a cópia do CI não reivindica mais o `harbor://` e é removida depois do teste.
- Tempo do Claude encostando na borda do notch fechado (asa mais larga).
- O aviso de ociosidade do Claude não deixa mais um cartão "Esperando você" preso.

## [2.2.0] - 2026-11-08

### Adicionado
- **Manual ilustrado em PDF** (`docs/manual/Harbor-Manual.pdf`) e um PDF por tutorial (`docs/manual/tutoriais/`), gerados com `make docs`.
- Banners do README no visual do Harbor.
- **Ajustes › Sobre**: versão, links para o repositório oficial, feedback, reportar um problema (com a versão já preenchida) e manual.
- "Enviar feedback…" e "Repositório oficial" no menu da barra de menus.
- Modelos de issue para feedback e bugs.

### Alterado
- Ícone da barra de menus agora é uma âncora (desenhada em código, se adapta à barra clara/escura).
- Versão e botão Sair saíram do rodapé da barra lateral dos Ajustes e foram para a seção Sobre.

## [2.1.0] - 2026-11-08

### Adicionado
- **Mudo global do microfone** (⌥M) com bolha: laranja quando um app usa o microfone, vermelha no mudo.
- **Downloads ao vivo** no notch (Chrome, Edge, Brave, Safari e Firefox). Ao concluir, o arquivo vai para a Bandeja.
- **Badges do Dock** nas bolhas de apps fixados.
- **Aba PRs**: status dos checks de CI e das revisões dos seus PRs, PRs aguardando sua revisão e avisos quando algo muda.
- **Spotify**: curtir a música atual e ver/pular para músicas da fila (Web API, login OAuth PKCE).
- Certificado de assinatura estável ("Harbor Dev"): as permissões não se perdem mais a cada build.
- Estrutura de repositório: Makefile, scripts de build/release/assinatura, releases no GitHub (publicadas localmente), documentação.
- CI local (`make ci`): roda antes de cada push e de cada release, com validações, build e teste de fumaça de todas as abas.

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
