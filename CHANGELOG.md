# Changelog

Todas as mudanças relevantes do Harbor. Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e [SemVer](https://semver.org/lang/pt-BR/).

## [Unreleased]

### Documentação
- Problemas conhecidos viram issues com o rótulo `troubleshooting` (a primeira é a #3, sobre permissões perdidas), com link no README e na tela de abrir issue.

## [2.4.1] - 2026-11-09

### Corrigido
- Aviso nativo de volume e brilho voltando a aparecer junto com o do Harbor. A cópia de teste do CI usava o mesmo identificador do app (`com.gustavo.harbor`). Quando um pedido de permissão aparecia para ela e era aprovado, o macOS passava as permissões (Acessibilidade, Gravação de Tela, Calendários) para essa cópia ad-hoc, e o Harbor de verdade as perdia. A cópia agora usa `com.gustavo.harbor.ci`.

### Documentação
- README e manual: como recuperar as permissões (`tccutil reset …`) quando o aviso nativo volta a aparecer.

## [2.4.0] - 2026-11-09

### Adicionado
- Ajuste **Reabrir na última aba** (Ajustes › Geral, desligado por padrão). Desligado, o notch sempre abre no Início, ou na aba **Agora** quando algo está rodando. Ligado, volta para a aba em que você parou.
- **Atualização pelo próprio app**: Ajustes › Sobre › Atualizações compara a versão instalada com a última release do GitHub e, se houver uma mais nova, o botão **Atualizar para vX** baixa o `.zip`, confere se foi assinado pelo mesmo certificado do app atual, troca o app antigo pelo novo e reabre o Harbor. Procura sozinho ao abrir e a cada 6 h (aviso no notch uma vez por versão) e pelo menu da âncora › **Procurar atualizações…**. Usa o `gh` CLI, porque o repositório é privado.
- **Bluetooth no island**:
  - **Fone na asa da música**: com música tocando e o som saindo por Bluetooth, um ícone de fone/AirPods aparece junto do visualizador.
  - **Aviso de bateria fraca** em 20% e 10% para qualquer aparelho Bluetooth (fones, teclado, mouse).
  - **Cartão de aparelhos** na aba Ferramentas: todos os aparelhos conectados com a bateria de cada um (esquerdo/direito/estojo nos AirPods) e qual está tocando o som.
  - A bateria vem do `system_profiler`, então funciona também com fones de outras marcas.
- Skill **`/release`** do Claude Code (`.claude/skills/release/`): checklist completo de release (versão, CHANGELOG, README, manual, ARCHITECTURE, CI e publicação).

### Documentação
- README, manual em PDF, ARCHITECTURE e CONTRIBUTING atualizados: aba Agora, atualizações, Bluetooth, comportamento em tela cheia e solução de problemas do hook e da atualização.

### Alterado
- **Música tem prioridade sobre o Claude** nas asas do notch fechado. Com os dois ativos, o selo do Claude girando aparece ao lado da capa, do mesmo tamanho, e o hover abre a aba **Agora** para ver o que ele está fazendo.
- Ajustes › Geral: atalhos em uma coluna (antes ficavam cortados); "Fones Bluetooth" virou **Aparelhos Bluetooth** (conexão e bateria fraca).
- O island fica fixo ao trocar de Space e com outros apps em tela cheia. Ele só se recolhe quando o app da atividade que está mostrando (o Spotify/Música tocando, ou o terminal onde o Claude está trabalhando) está em tela cheia na frente. A troca tem um pequeno debounce para não piscar durante a animação do Space. O ajuste passou a se chamar **Recolher em tela cheia**.
- O hook do Claude informa em qual app ele roda (Terminal, iTerm, VS Code…); o script em `~/.harbor/` é atualizado sozinho.

## [2.3.0] - 2026-11-09

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
