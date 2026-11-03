import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import "MediaModel.js" as MediaModel

Item {
  id: root

  property var shell: null
  property string preferredPlayerKey: ""
  // Player the user picked by hand (list click, Tab). It stays active even if
  // another player is playing, until a different player starts or this one goes away.
  property string pinnedPlayerKey: ""
  property var playerStartedAt: ({})
  property var pendingTrackOsd: null
  property int playSerial: 0

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var playbackStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && isPlaybackStream(n) && n.audio) list.push(n)
    }
    return list
  }
  readonly property var sourcePlayers: orderedSourcePlayers()
  readonly property var sourceCyclePlayers: orderedCycleSourcePlayers()
  readonly property var activePlayer: selectActivePlayer()
  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string artUrl: activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""
  readonly property string identity: activePlayer ? (activePlayer.identity || activePlayer.desktopEntry || "") : ""

  // --- Cover art: fetched/copied, byte-capped, and dimension-validated
  // before it ever reaches a QML Image. trackArtUrl is attacker-controlled
  // (any MPRIS player, including a hostile web page via a browser's media
  // session bridge) and Image has no built-in cap on response size or
  // decoded pixel count — a small, highly-compressed file claiming an
  // enormous width/height could make the shell allocate far more memory
  // than the ~22-64px it actually renders at, or crash outright. This
  // downloads/copies to a temp file with hard size and time caps, checks
  // its real dimensions with ImageMagick (itself resource-limited) without
  // ever handing raw remote bytes to Image, and only then publishes the
  // validated local path. Redirects are not followed — safeArtUrl only
  // vets the initial host, so following one could reach an internal
  // address it already rejected.
  readonly property int artMaxBytes: 8 * 1024 * 1024
  readonly property int artMaxDimension: 4096
  property int _artGeneration: 0
  property string _artCurrentFile: ""
  property string safeArtPath: ""

  readonly property string _artCacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/omarchy/vinicgobbi.media"

  readonly property string _artFetchScript: [
    "dir=$(dirname -- \"$2\")",
    "mkdir -p -- \"$dir\" || exit 1",
    "tmp=\"$2.tmp\"",
    "rm -f -- \"$tmp\"",
    "if [ \"$3\" = \"1\" ]; then",
    "  src=${1#file://}",
    // Regular files only: /dev/zero reports size 0 and never ends (it would
    // fill the disk), a FIFO would hang the fetch. head -c caps it anyway.
    "  [ -f \"$src\" ] || exit 1",
    "  size=$(stat -L -c%s -- \"$src\" 2>/dev/null) || exit 1",
    "  [ \"$size\" -le \"$4\" ] || exit 1",
    "  head -c \"$4\" -- \"$src\" > \"$tmp\" || exit 1",
    "else",
    // The URL passed safeArtUrl (https, a public-looking host), but a name
    // can still resolve to this machine or the LAN. Resolve it once, refuse
    // local addresses, and make curl connect to that address only, so a page
    // playing audio can't send the shell's requests into the local network.
    "  hp=${1#https://}; hp=${hp%%[/?#]*}; h=${hp%%:*}; p=443",
    "  [ \"$hp\" != \"$h\" ] && p=${hp##*:}",
    "  ip=$(getent ahostsv4 \"$h\" 2>/dev/null | awk '{ print $1; exit }')",
    "  [ -n \"$ip\" ] || ip=$(getent ahostsv6 \"$h\" 2>/dev/null | awk '{ print $1; exit }')",
    "  [ -n \"$ip\" ] || exit 1",
    "  case \"$ip\" in",
    "    *:*)",
    // IPv6: global unicast (2000::/3) only, and not v4-mapped.
    "      case \"$ip\" in [23]*:*) ;; *) exit 1 ;; esac",
    "      pin=\"[$ip]\" ;;",
    "    *)",
    "      ok=$(printf '%s\\n' \"$ip\" | awk -F. 'NF == 4 { a = $1 + 0; b = $2 + 0; if (a == 0 || a == 10 || a == 127 || a >= 224 || (a == 169 && b == 254) || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 100 && b >= 64 && b <= 127) || (a == 198 && (b == 18 || b == 19))) print \"no\"; else print \"yes\" }')",
    "      [ \"$ok\" = yes ] || exit 1",
    "      pin=$ip ;;",
    "  esac",
    "  curl -fsS --proto =https --connect-timeout 3 --max-time 8 --max-filesize \"$4\" --resolve \"$h:$p:$pin\" -- \"$1\" 2>/dev/null | head -c \"$4\" > \"$tmp\"",
    "  [ -s \"$tmp\" ] || { rm -f -- \"$tmp\"; exit 1; }",
    "fi",
    // Only real PNG/JPEG/GIF/WebP, told apart by their first bytes, and
    // ImageMagick is told which decoder to use: left to guess, it would hand
    // a PostScript/PDF/SVG dressed up as cover art to Ghostscript or an SVG
    // renderer, far more attack surface than reading four image headers.
    "sig=$(head -c 12 -- \"$tmp\" | od -An -tx1 | tr -d ' \\n')",
    "case \"$sig\" in",
    "  89504e470d0a1a0a*) fmt=png;;",
    "  ffd8ff*) fmt=jpeg;;",
    "  474946383761*|474946383961*) fmt=gif;;",
    "  52494646????????57454250) fmt=webp;;",
    "  *) rm -f -- \"$tmp\"; exit 1;;",
    "esac",
    "dims=$(timeout 5 identify -limit area 64MB -limit memory 64MB -limit map 64MB -format '%w %h' -- \"${fmt}:${tmp}[0]\" 2>/dev/null) || { rm -f -- \"$tmp\"; exit 1; }",
    "w=${dims%% *}",
    "h=${dims##* }",
    "case \"$w\" in ''|*[!0-9]*) rm -f -- \"$tmp\"; exit 1;; esac",
    "case \"$h\" in ''|*[!0-9]*) rm -f -- \"$tmp\"; exit 1;; esac",
    "if [ \"$w\" -gt \"$5\" ] || [ \"$h\" -gt \"$5\" ]; then rm -f -- \"$tmp\"; exit 1; fi",
    "mv -f -- \"$tmp\" \"$2\""
  ].join("\n")

  // At most one fetch runs at a time (reassigning `command` on an
  // already-running Process is exactly what every other Process in this
  // codebase guards against — see e.g. VpnService.qml's `if (x.running)
  // return`). A track change while a fetch is in flight replaces this
  // instead of starting a second one; only the latest request matters.
  property var _artPending: null

  function _clearArt() {
    // Bump the generation too, not just the visible state: otherwise a
    // fetch already in flight for the track that just went away would
    // still match root._artGeneration when it lands and resurrect art for
    // a track that's no longer playing.
    root._artGeneration += 1
    root._artPending = null
    root.safeArtPath = ""
    var stale = root._artCurrentFile
    root._artCurrentFile = ""
    if (stale) artCleanupProcess.remove(stale)
  }

  function _startArtFetch(request) {
    artFetchProcess.generation = request.generation
    artFetchProcess.targetPath = request.target
    artFetchProcess.command = ["bash", "-c", root._artFetchScript, "_",
      request.safe, request.target, request.isLocal ? "1" : "0", String(root.artMaxBytes), String(root.artMaxDimension)]
    artFetchProcess.running = true
  }

  function refreshArt() {
    var safe = MediaModel.safeArtUrl(root.artUrl)
    if (safe === "") { root._clearArt(); return }

    root._artGeneration += 1
    var isLocal = /^file:\/\/\//i.test(safe)
    var generation = root._artGeneration
    var request = {
      safe: safe,
      generation: generation,
      isLocal: isLocal,
      target: root._artCacheDir + "/cover-" + generation + "-" + Math.floor(Math.random() * 1e6) + ".img"
    }

    if (artFetchProcess.running) {
      root._artPending = request
      return
    }
    root._startArtFetch(request)
  }

  onArtUrlChanged: root.refreshArt()

  function initArtCache() {
    // Sweep anything left behind by a crashed previous session before this
    // one starts writing to the same cache directory.
    artStartupCleanupProcess.command = ["sh", "-c", "rm -rf -- \"$1\"; mkdir -p -- \"$1\"", "_", root._artCacheDir]
    artStartupCleanupProcess.running = true
    root.refreshArt()
  }

  Process { id: artStartupCleanupProcess }

  Process {
    id: artCleanupProcess
    property var _queue: []
    function remove(path) {
      if (!path) return
      if (running) { _queue.push(path); return }
      command = ["rm", "-f", "--", path]
      running = true
    }
    onExited: {
      if (_queue.length === 0) return
      var next = _queue.shift()
      command = ["rm", "-f", "--", next]
      running = true
    }
  }

  Process {
    id: artFetchProcess
    property int generation: 0
    property string targetPath: ""
    onExited: function(exitCode) {
      // A newer track may have started a fresh fetch while this one was in
      // flight; only publish (or clean up in place of) a result that's
      // still the one currently requested.
      if (generation === root._artGeneration) {
        if (exitCode === 0) {
          var previous = root._artCurrentFile
          root._artCurrentFile = targetPath
          root.safeArtPath = Util.fileUrl(targetPath)
          if (previous && previous !== targetPath) artCleanupProcess.remove(previous)
        } else {
          root.safeArtPath = ""
        }
      } else if (exitCode === 0) {
        artCleanupProcess.remove(targetPath)
      }

      // At most one fetch runs at a time: start whatever the latest
      // track-change queued while this one was in flight.
      var pending = root._artPending
      root._artPending = null
      if (pending) root._startArtFetch(pending)
    }
  }

  function isProxyPlayer(player) {
    return MediaModel.isProxyPlayer(player)
  }

  function hasMetadata(player) {
    return MediaModel.hasMetadata(player)
  }

  function hasTrackMetadata(player) {
    return MediaModel.hasTrackMetadata(player)
  }

  // Stopped players with no track (e.g. the empty chromium instance that
  // Spotify's embedded Chromium registers next to the real player) have
  // nothing to show or control.
  function isIdlePlayer(player) {
    return !!player && !player.isPlaying
      && player.playbackState === MprisPlaybackState.Stopped
      && !hasTrackMetadata(player)
  }

  function playerCanControl(player) {
    return MediaModel.playerCanControl(player)
  }

  function canHandleAction(player, action) {
    return MediaModel.canHandleAction(player, action)
  }

  function canCycleSource(player) {
    return MediaModel.canCycleSource(player)
  }

  function nodeProps(node) {
    return MediaModel.nodeProps(node)
  }

  function isPlaybackStream(node) {
    return MediaModel.isPlaybackStream(node)
  }

  function streamLabelKey(label) {
    return MediaModel.streamLabelKey(label)
  }

  function rawStreamLabel(node) {
    return MediaModel.rawStreamLabel(node)
  }

  function playerAppLabel(player) {
    return MediaModel.playerAppLabel(player)
  }

  function playerHasPlaybackStream(player) {
    return MediaModel.playerHasPlaybackStream(player, playbackStreams)
  }

  function playerKey(player) {
    return MediaModel.playerKey(player)
  }

  function playerForKey(key) {
    if (!key) return null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (playerKey(p) === key) return p
    }
    return null
  }

  function playerOrder(player, fallback) {
    var key = playerKey(player)
    var value = key ? playerStartedAt[key] : undefined
    return value === undefined ? fallback : value
  }

  function syncPlayingOrder() {
    var next = {}
    var alive = {}
    var serial = playSerial

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      var key = playerKey(p)
      if (!key) continue

      alive[key] = true
      if (!p.isPlaying) continue

      if (playerStartedAt[key] === undefined) {
        serial += 1
        next[key] = serial
        // A different player just started: follow the playback again.
        if (pinnedPlayerKey && key !== pinnedPlayerKey) pinnedPlayerKey = ""
      } else {
        next[key] = playerStartedAt[key]
      }
    }

    if (preferredPlayerKey && !alive[preferredPlayerKey]) preferredPlayerKey = ""
    if (pinnedPlayerKey && !alive[pinnedPlayerKey]) pinnedPlayerKey = ""

    playSerial = serial
    playerStartedAt = next
  }

  function orderedSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (hasMetadata(p) && !isIdlePlayer(p)) list.push(p)
    }

    list.sort(function(a, b) {
      if (!!a.isPlaying !== !!b.isPlaying) return a.isPlaying ? -1 : 1
      if (isProxyPlayer(a) !== isProxyPlayer(b)) return isProxyPlayer(a) ? 1 : -1
      if (a.isPlaying && b.isPlaying) {
        var orderDelta = playerOrder(a, 1000) - playerOrder(b, 1000)
        if (orderDelta !== 0) return orderDelta
      }
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  function orderedCycleSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (canCycleSource(p) && !isIdlePlayer(p)) list.push(p)
    }

    list.sort(function(a, b) {
      if (isProxyPlayer(a) !== isProxyPlayer(b)) return isProxyPlayer(a) ? 1 : -1
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  function oldestPlayingPlayer(requirePlaybackStream) {
    var oldest = null
    var oldestOrder = 0
    var playingProxy = null
    var proxyOrder = 0

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxyPlayer = isProxyPlayer(p)
      if (p.isPlaying) {
        if (requirePlaybackStream && !playerHasPlaybackStream(p)) continue

        var order = playerOrder(p, i + 1000)
        if (!proxyPlayer && (!oldest || order < oldestOrder)) {
          oldest = p
          oldestOrder = order
        } else if (proxyPlayer && (!playingProxy || order < proxyOrder)) {
          playingProxy = p
          proxyOrder = order
        }
      }
    }

    return oldest || playingProxy || null
  }

  function selectActivePlayer() {
    var pinned = pinnedPlayerKey ? playerForKey(pinnedPlayerKey) : null
    if (pinned && hasMetadata(pinned)) return pinned

    var preferred = null
    var trackPlayer = null
    var trackProxy = null
    var streamPlayer = null
    var streamProxy = null
    var controllablePlayer = null
    var controllableProxy = null
    var identityPlayer = null
    var identityProxy = null

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p || isIdlePlayer(p)) continue

      var proxy = isProxyPlayer(p)

      if (preferredPlayerKey && playerKey(p) === preferredPlayerKey && hasMetadata(p)) preferred = p

      if (playerHasPlaybackStream(p)) {
        if (!proxy && !streamPlayer) streamPlayer = p
        else if (proxy && !streamProxy) streamProxy = p
      } else if (hasTrackMetadata(p)) {
        if (!proxy && !trackPlayer) trackPlayer = p
        else if (proxy && !trackProxy) trackProxy = p
      } else if (playerCanControl(p)) {
        if (!proxy && !controllablePlayer) controllablePlayer = p
        else if (proxy && !controllableProxy) controllableProxy = p
      } else if (hasMetadata(p)) {
        if (!proxy && !identityPlayer) identityPlayer = p
        else if (proxy && !identityProxy) identityProxy = p
      }
    }

    if (preferred && preferred.isPlaying) return preferred
    var streamCandidate = streamPlayer || streamProxy
    var streamPreferred = preferred && playerHasPlaybackStream(preferred) ? preferred : null
    return oldestPlayingPlayer(true) || oldestPlayingPlayer(false) || streamPreferred || streamCandidate || preferred || trackPlayer || trackProxy || controllablePlayer || controllableProxy || identityPlayer || identityProxy || null
  }

  function labelFor(player) {
    return MediaModel.labelFor(player)
  }

  function osdMessage(player, fallback) {
    return MediaModel.osdMessage(player, fallback)
  }

  function trackSignature(player) {
    return MediaModel.trackSignature(player)
  }

  function showOsd(actionLabel, iconName, player) {
    if (!shell) return
    shell.summon("omarchy.osd", JSON.stringify({
      icon: iconName || "media",
      message: osdMessage(player || activePlayer, actionLabel)
    }))
  }

  function scheduleOsd(actionLabel, iconName, player, waitForTrackChange, beforeTrackSignature) {
    if (waitForTrackChange) {
      pendingTrackOsd = {
        actionLabel: actionLabel,
        iconName: iconName,
        player: player,
        playerKey: playerKey(player),
        before: beforeTrackSignature,
        attempts: 0
      }
      trackOsdTimer.restart()
    } else {
      Qt.callLater(function() { root.showOsd(actionLabel, iconName, player) })
    }
  }

  function flushPendingTrackOsd(force) {
    var pending = pendingTrackOsd
    if (!pending) return

    var player = playerForKey(pending.playerKey) || pending.player
    if (force || MediaModel.trackChanged(pending.before, player) || pending.attempts >= 10) {
      pendingTrackOsd = null
      trackOsdTimer.stop()
      root.showOsd(pending.actionLabel, pending.iconName, player)
      return
    }

    pending.attempts = pending.attempts + 1
    pendingTrackOsd = pending
    trackOsdTimer.restart()
  }

  function selectPlayer(key) {
    var player = playerForKey(key)
    if (!player || !hasMetadata(player)) return false
    preferredPlayerKey = playerKey(player)
    pinnedPlayerKey = preferredPlayerKey
    return true
  }

  function playPlayer(player) {
    if (!player) return false
    if (player.canPlay) {
      player.play()
      return true
    }
    return false
  }

  function pausePlayer(player) {
    if (!player) return false
    if (player.canPause) {
      player.pause()
      return true
    }
    if (player.canTogglePlaying && player.isPlaying) {
      player.togglePlaying()
      return true
    }
    return false
  }

  function switchSource(delta, transferPlayback, showFeedback) {
    var list = sourceCyclePlayers
    if (!list || list.length === 0) return false

    var activeKey = playerKey(activePlayer)
    var index = 0
    for (var i = 0; i < list.length; i++) {
      if (playerKey(list[i]) === activeKey) {
        index = i
        break
      }
    }

    index = (index + delta + list.length) % list.length
    var current = activePlayer
    var next = list[index]
    var currentWasPlaying = current && current.isPlaying
    var currentKey = playerKey(current)
    var nextKey = playerKey(next)

    preferredPlayerKey = nextKey
    pinnedPlayerKey = nextKey

    if (transferPlayback && currentWasPlaying && next && nextKey !== currentKey) {
      var nextWasPlaying = next.isPlaying
      var nextStarted = nextWasPlaying || playPlayer(next)
      if (nextStarted) pausePlayer(current)
    }

    if (showFeedback !== false) Qt.callLater(function() {
      root.showOsd("Source", "media-source", next)
    })

    return true
  }

  function playerForAction(action, targetKey) {
    var targeted = playerForKey(targetKey)
    if (targeted) return targeted

    if (action === "pause" || action === "playPause") {
      var oldest = oldestPlayingPlayer(true) || oldestPlayingPlayer(false)
      if (oldest) return oldest
    }

    if (canHandleAction(activePlayer, action)) return activePlayer

    var list = sourcePlayers
    for (var i = 0; i < list.length; i++) {
      if (canHandleAction(list[i], action)) return list[i]
    }

    return activePlayer
  }

  function runAction(action, showFeedback, targetKey) {
    var player = playerForAction(action, targetKey)
    var key = playerKey(player)
    var actionLabel = "Play/pause"
    var iconName = "media"
    var beforeTrackSignature = trackSignature(player)
    var handled = false

    if (action === "next") {
      actionLabel = "Next"
      iconName = "media-next"
      if (player && player.canGoNext) {
        player.next()
        handled = true
      }
    } else if (action === "previous") {
      actionLabel = "Previous"
      iconName = "media-previous"
      if (player && player.canGoPrevious) {
        player.previous()
        handled = true
      }
    } else if (action === "play") {
      actionLabel = "Play"
      iconName = "media-play"
      if (player && player.canPlay) {
        player.play()
        handled = true
      } else if (player && player.canTogglePlaying && !player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "pause") {
      actionLabel = "Pause"
      iconName = "media-pause"
      if (player && player.canPause) {
        player.pause()
        handled = true
      } else if (player && player.canTogglePlaying && player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "playPause") {
      actionLabel = player && player.isPlaying ? "Pause" : "Play"
      iconName = player && player.isPlaying ? "media-pause" : "media-play"
      if (player && player.isPlaying && player.canPause) {
        player.pause()
        handled = true
      } else if (player && !player.isPlaying && player.canPlay) {
        player.play()
        handled = true
      } else if (player && player.canTogglePlaying) {
        player.togglePlaying()
        handled = true
      }
    }

    if (handled && key) preferredPlayerKey = key
    if (showFeedback !== false)
      scheduleOsd(actionLabel, iconName, player, handled && (action === "next" || action === "previous"), beforeTrackSignature)
    return handled
  }

  // Recompute play-order reactively instead of polling every 500ms.
  // syncPlayingOrder only depends on the set of players and each player's
  // isPlaying state: onPlayersChanged covers players appearing/disappearing,
  // and the Instantiator wires isPlayingChanged for each live player.
  Component.onCompleted: {
    root.syncPlayingOrder()
    root.initArtCache()
  }
  onPlayersChanged: root.syncPlayingOrder()

  Instantiator {
    model: root.players
    delegate: Connections {
      required property var modelData
      target: modelData
      function onIsPlayingChanged() { root.syncPlayingOrder() }
    }
  }

  Timer {
    id: trackOsdTimer
    interval: 120
    repeat: false
    onTriggered: root.flushPendingTrackOsd(false)
  }

  PwObjectTracker { objects: root.playbackStreams }

  function statusJson() {
    var p = activePlayer
    return JSON.stringify({
      hasPlayer: p !== null,
      hasMedia: root.hasMedia,
      playing: p ? !!p.isPlaying : false,
      identity: p ? (p.identity || "") : "",
      desktopEntry: p ? (p.desktopEntry || "") : "",
      title: p ? (p.trackTitle || "") : "",
      artist: p ? (p.trackArtist || "") : "",
      album: p && p.trackAlbum ? p.trackAlbum : "",
      artUrl: p && p.trackArtUrl ? p.trackArtUrl : "",
      canGoNext: p ? !!p.canGoNext : false,
      canGoPrevious: p ? !!p.canGoPrevious : false,
      canTogglePlaying: p ? !!p.canTogglePlaying : false
    })
  }

  IpcHandler {
    target: "media"

    function status(): string {
      return root.statusJson()
    }

    function playPause(): string {
      return root.runAction("playPause", true) ? "ok" : "unhandled"
    }

    function next(): string {
      return root.runAction("next", true) ? "ok" : "unhandled"
    }

    function previous(): string {
      return root.runAction("previous", true) ? "ok" : "unhandled"
    }

    function play(): string {
      return root.runAction("play", true) ? "ok" : "unhandled"
    }

    function pause(): string {
      return root.runAction("pause", true) ? "ok" : "unhandled"
    }

    function sourceNext(): string {
      return root.switchSource(1, false, true) ? "ok" : "unhandled"
    }

    function sourcePrevious(): string {
      return root.switchSource(-1, false, true) ? "ok" : "unhandled"
    }

    function sourceSwitch(): string {
      return root.switchSource(1, true, true) ? "ok" : "unhandled"
    }

    function sourceSwitchPrevious(): string {
      return root.switchSource(-1, true, true) ? "ok" : "unhandled"
    }

    function ping(): string {
      return "ok"
    }
  }
}
