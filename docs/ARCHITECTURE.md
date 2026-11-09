# Arquitetura do Harbor

O Harbor é um app SwiftUI + AppKit empacotado manualmente (SwiftPM → `.app`), sem projeto Xcode.

```
main.swift ─► AppDelegate ─► NotchController ─┬─► NotchPanel (NSPanel transparente sobre o notch)
                                              │      └─► NSHostingView(NotchRootView)
                                              ├─► NotchViewModel (estado da UI: aberto/aba/tamanhos)
                                              └─► Serviços (ObservableObject, injetados como environmentObject)
```

## Janela e interação

- **`NotchPanel`**: `NSPanel` sem borda, `nonactivatingPanel`, nível acima da barra de menus, em todos os Spaces.
  Fica com `ignoresMouseEvents = true` quando fechado: os cliques passam para a barra de menus.
  As exceções são as bolhas clicáveis.
- **`NotchController`**: um timer de 30 Hz lê a posição do mouse (`NSEvent.mouseLocation`) e decide:
  abrir/fechar por hover, arrastar arquivo → Bandeja, cliques nas bolhas. Também cuida dos atalhos globais
  (Carbon), tela cheia, troca de tela e de **qual atividade aparece no notch fechado** (`computeActivity`).
- **`NotchViewModel`**: tamanhos (notch físico, island aberto por aba, asas da atividade), aba atual,
  pedidos de foco, estado "recolhido".

### Prioridade do notch fechado

`alert` › `meeting` › `download` › `music` › `claude` › `timer` › `none`

Com música e Claude ativos ao mesmo tempo, a música ocupa as asas e o selo do Claude aparece ao lado da capa (`vm.claudeBehindMusic`).

### Aba temporária "Agora"

`NookTab.live` só aparece na barra quando `vm.live` (calculado por `computeLive()`: reunião, Claude, download, timer) não está vazio. O hover com algo rodando abre nela. Ao fechar, `tabBeforeLive` devolve o usuário à aba anterior. Sem o ajuste `reopenLastTab`, o notch sempre abre no Início ou na Agora.

### Tela cheia

O island só se recolhe quando o app da atividade mostrada (`islandSourceApps()`: o app da música ou o terminal do Claude, vindo de `__CFBundleIdentifier` no hook) está em tela cheia na frente, com debounce de 0,45 s.

## Serviços (`Sources/Harbor/Services`)

| Serviço | Responsabilidade | Fonte |
|---|---|---|
| `MediaController` | O que está tocando, controles, capa e cor de destaque | AppleScript (Spotify/Música), MediaRemote |
| `SpotifyAPI` | Fila e curtir | Web API do Spotify (OAuth PKCE, token no Keychain) |
| `AudioLevels` | FFT do áudio do sistema para o visualizador real | ScreenCaptureKit + Accelerate |
| `SystemMonitor` | CPU, bateria e rede | `host_statistics`, IOKit, `getifaddrs` |
| `AlertCenter` | Avisos (volume, brilho, energia, Bluetooth) | CoreAudio, DisplayServices, IOKit, IOBluetooth |
| `MediaKeyInterceptor` | Substitui o aviso nativo de volume/brilho | `CGEventTap` (NX_SYSDEFINED) |
| `MicController` | Mudo global e "microfone em uso" | CoreAudio (entrada padrão) |
| `ClaudeActivity` | Sessões do Claude Code, pedido, ferramenta em uso e última mensagem | Hooks → `harbor://claude?d=…&app=…` (entregue ao app em `~/.harbor/app-path`) + transcript JSONL |
| `BluetoothMonitor` | Aparelhos conectados, bateria e se o som sai por Bluetooth | `system_profiler SPBluetoothDataType -json`, CoreAudio |
| `Updater` | Compara com a última release, baixa, verifica a assinatura e troca o app | `gh release view/download`, Security (`SecStaticCodeCheckValidity` com o requisito designado do app atual) |
| `GitHubStatus` | PRs, checks e revisões | `gh api graphql` |
| `DownloadsMonitor` | Downloads em andamento | `~/Downloads` + `NSProgress` |
| `AppPinStore` | Apps fixados e badges | NSWorkspace + Acessibilidade (Dock) |
| `CalendarStore` | Eventos e próxima reunião | EventKit |
| `ClipboardStore` | Histórico do ⌘C | NSPasteboard |
| `BackdropCapture` | Captura do fundo para o vidro com refração | ScreenCaptureKit + Metal |
| `FocusTimer`, `TaskStore`, `ShelfStore`, `MouseOdometer`, `ColorPickerStore`, `CameraManager` | Recursos das abas | — |

## Views (`Sources/Harbor/Views`)

- `NotchRootView`: forma do island (`NotchShape`), superfície (`IslandSurface`: preto ou Liquid Glass),
  bolhas laterais e a barra de abas.
- `ClosedNotchView`: conteúdo do island fechado (asas) e as bolhas.
- Uma view por aba (`LiveTabView`, `NookHomeView`, `MediaTabView`, `ClipboardTabView`, `PRsTabView`, …).

## Convenções

- **Não use `@State`**: no SDK do macOS 27 ele é uma macro que só funciona com o Xcode completo.
  Use `@Local` (`Views/Local.swift`), que tem a mesma semântica.
- Preferências em `UserDefaults` (`@AppStorage`). Chaves agrupadas em enums (`Prefs`, `VizPrefs`, …).
- Shaders Metal são compilados em tempo de execução (`device.makeLibrary(source:)`).
- Depuração visual: `build/Harbor.app/Contents/MacOS/Harbor --snapshot <pasta>` gera um PNG de cada aba, mais `closed` e `closed-music` (música com o selo do Claude). O modo usa uma sessão fictícia do Claude.
- Teste da atualização: `Harbor --update-now` procura e instala sem clique (use numa cópia com versão menor).
- Uma cópia do app que não deve receber eventos (CI, testes) precisa ficar sem `CFBundleURLTypes`, ou o macOS pode entregar o `harbor://` para ela. Ela também precisa de outro `CFBundleIdentifier` (o CI usa `com.gustavo.harbor.ci`): com o mesmo id e outra assinatura, uma permissão aprovada para a cópia substitui a do app real no TCC.
