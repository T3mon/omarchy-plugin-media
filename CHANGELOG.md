## Unreleased

### Feat

- output picker also lists outputs on another sound card profile (Speaker
  while headphones are plugged in); picking one switches the card's profile
  and resumes playback if the switch paused it
- visualizer: faint bars behind the bar widget and/or the popup, each with
  its own toggle in the advanced options

### Fix

- unplugged outputs are re-checked whenever the list of outputs changes
  (after a profile switch they showed up again)

## v0.3.0 (2026-11-12)

### Feat

- mute: click the speaker icon to mute just this player
- output picker: move just this player's sound to another device; the list
  sits behind the current output's name and hides unplugged outputs (HDMI
  with no monitor)
- copy song: click the title to copy "Artist – Title" (or the track link)
- Spotify web app: shuffle, repeat and queue buttons that send Spotify's own
  shortcuts to its window; shuffle/repeat state is a local guess
- "Open player" for browsers and web apps, which can't raise themselves:
  focuses the window showing the track through Hyprland

### Fix

- volume slider did nothing for browsers and web apps: it now sets the
  player's PipeWire stream volume
- no spaces around the separator in the bar text

## v0.2.1 (2026-11-03)

### Fix

- **seguranca**: capas em cache ficam privadas
- **seguranca**: capa não acessa a rede local por DNS

## v0.2.0 (2026-10-04)

### Feat

- badge LIVE em transmissões ao vivo no lugar do tempo na barra e da barra de progresso no popup (o Chromium manda duração INT64_MAX e a barra mostrava 0:14 / 2562047788:00:54; Firefox e mpv omitem a duração)

### Fix

- tooltip da barra nunca aparecia (o shell exige tooltipHovered no alvo) e agora mostra título, artista · álbum e player (· LIVE), uma linha cada, limitadas a 80 caracteres

## v0.1.2 (2026-10-03)

### Fix

- **security**: capa do álbum só aceita PNG/JPEG/GIF/WebP pela assinatura dos bytes, com o decodificador do ImageMagick explícito (um PostScript/PDF/SVG disfarçado chegava ao Ghostscript), arquivo local só se for arquivo comum (file:///dev/zero enchia o disco, FIFO travava a busca), curl só https e IPs em grafias alternativas (127.1, 2130706433, 0x7f.1) tratados como internos

## v0.1.1 (2026-10-03)

### Fix

- evita reatribuir command/running num Process já em execução (troca rápida de faixa) e corrige corrida onde arte de uma faixa antiga podia ressuscitar
- mescla os dois Component.onCompleted duplicados (quebrava o carregamento do service)
- valida a capa do álbum (bytes, timeout, dimensões decodificadas) antes do QML Image, contra bomba de descompressão via MPRIS não confiável
- disable qmllint's alias category too

### Refactor

- usa Util.alpha() e CursorSurface (componentes do Omarchy) em vez de reimplementar hover/seleção e alpha na mão

## v0.1.0 (2026-09-21)

### Feat

- make the bar's play/pause icon a button
- add previous and next buttons to the bar, configurable
- add advanced options menu and more bar content options
- add volume, shuffle, repeat, speed, seek and keyboard control
- initial Media Manager plugin cloned from omarchy.media

### Fix

- make the open-popup indicator cover the whole widget
- sanitize player metadata before showing it
- keep the manually selected player active and ignore idle ones
- rename seek bar id that shadowed the widget's bar property
- resolve the media service through the omarchy.media id

### Refactor

- store the options inline on the widget entry in shell.json
