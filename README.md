# Harbor ⚓️

Um app nativo de macOS, feito em Swift e SwiftUI, que transforma o notch num "porto": é lá que ficam a sua música, os arquivos, o que você copia, o timer e a câmera.

## Compilar e rodar

```bash
./build.sh            # gera build/Harbor.app
./build.sh --run      # gera o app e abre
./build.sh --install  # copia para /Applications e abre
```

Basta ter os Command Line Tools instalados. O Xcode não é necessário.

## Abas (passe o mouse no notch)
- **Início**: música, CPU e bateria, timer Foco/Pausa e tarefas
- **Mídia**: player completo com barra de progresso
- **Copiados**: histórico do ⌘C com busca; clique num item para colar
- **Agenda**: eventos do dia, com o botão **Entrar** em reuniões que têm link (Meet, Zoom, Teams…)
- **Bandeja**: arraste arquivos até o notch para guardá-los; envie por **AirDrop**
- **Espelho**: câmera 1:1 com o island esticado para baixo
- **Odômetro**: distância percorrida pelo mouse; dá para fixar uma bolha ao lado do notch
- **Ferramentas**: nota rápida, conta-gotas e monitor de rede
- **Ajustes**: Geral, Visual e Integrações

## Notch fechado
O que aparece, em ordem de prioridade:
1. **Avisos**: volume, brilho, carregador, bateria fraca, fones Bluetooth, timer concluído, Claude terminou ou pede permissão
2. **Reunião** nos próximos 10 minutos
3. **Claude Code trabalhando**, com o tempo decorrido
4. **Música**, com capa e visualizador (simulado ou real) e um brilho que pulsa
5. **Timer**

## Atalhos
| Atalho | Ação |
|---|---|
| ⌥ Espaço | Abrir / fechar |
| ⌥ V | Histórico de cópias, com a busca já selecionada |
| ⌥ N | Nota rápida |
| ⌥ ⇧ C | Conta-gotas |
| Esc | Fechar |

## Claude Code
Em Ajustes › Integrações, o botão **Instalar hooks** cria `~/.harbor/claude-hook.sh` e adiciona hooks em `~/.claude/settings.json`. Antes, é feito um backup em `settings.json.harbor-backup`. Os eventos chegam ao Harbor pelo endereço `harbor://claude`.

## Permissões
- **Automação (Spotify/Música)**: para ler e controlar a música
- **Câmera**: para a aba Espelho
- **Calendários**: para a aba Agenda
- **Acessibilidade** (opcional): para colar automaticamente ao clicar num item copiado
- **Gravação de Tela** (opcional): para o vidro com refração e o visualizador real
- **Bluetooth**: para os avisos de fones

> O app é assinado localmente. Depois de rodar `./build.sh` de novo, pode ser preciso conceder as permissões outra vez.

## Depuração
`build/Harbor.app/Contents/MacOS/Harbor --snapshot <pasta>` renderiza cada aba como PNG.
