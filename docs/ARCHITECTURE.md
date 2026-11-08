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

`alert` › `meeting` › `download` › `claude` › `music` › `timer` › `none`

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
| `ClaudeActivity` | Sessões do Claude Code | Hooks → `harbor://claude?d=…` |
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
- Uma view por aba (`NookHomeView`, `MediaTabView`, `ClipboardTabView`, `PRsTabView`, …).

## Convenções

- **Não use `@State`**: no SDK do macOS 27 ele é uma macro que só funciona com o Xcode completo.
  Use `@Local` (`Views/Local.swift`), que tem a mesma semântica.
- Preferências em `UserDefaults` (`@AppStorage`). Chaves agrupadas em enums (`Prefs`, `VizPrefs`, …).
- Shaders Metal são compilados em tempo de execução (`device.makeLibrary(source:)`).
- Depuração visual: `build/Harbor.app/Contents/MacOS/Harbor --snapshot <pasta>` gera um PNG de cada aba.
