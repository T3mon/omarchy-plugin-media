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
