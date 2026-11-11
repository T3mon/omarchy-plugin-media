import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Io
import qs.Ui
import qs.Commons
import "MediaModel.js" as MediaModel

BarWidget {
  id: root
  moduleName: "vinicgobbi.media"

  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  // Options live inline on this widget's entry in shell.json (`settings`, injected
  // by the bar). `pendingPrefs` shows a change right away and is dropped once the
  // shell has reloaded the file and handed us the new settings.
  property var pendingPrefs: null
  readonly property var prefs: pendingPrefs ? pendingPrefs : MediaModel.normalizePrefs(settings)
  onSettingsChanged: pendingPrefs = null

  function setPref(name, value) {
    var next = {}
    for (var k in prefs) next[k] = prefs[k]
    next[name] = value
    savePrefs(next)
  }

  // An entry without our keys means "all defaults", so a reset just clears them.
  function resetPrefs() { savePrefs(MediaModel.defaultPrefs()) }

  function savePrefs(next) {
    var prefsNow = MediaModel.normalizePrefs(next)
    pendingPrefs = prefsNow
    if (bar && bar.shell)
      bar.shell.updateEntryInline(moduleName, MediaModel.entrySettings(prefsNow, settings))
  }
  // Metadata comes from whatever is playing, so it is capped in length. The
  // cover art itself is never bound to the raw remote URL: mediaService
  // downloads/validates it (host, size, and decoded dimensions) into a
  // local cache file first (see Service.qml's refreshArt) and this only
  // ever points Image at that already-validated local path.
  readonly property string album: activePlayer && activePlayer.trackAlbum ? MediaModel.clip(activePlayer.trackAlbum) : ""
  readonly property string playerName: activePlayer ? MediaModel.clip(activePlayer.identity || activePlayer.desktopEntry || "") : ""
  readonly property string artUrl: mediaService ? mediaService.safeArtPath : ""
  readonly property string barText: MediaModel.barLabel(
    { title: title, artist: artist, album: album, player: playerName }, prefs)

  // Live streams have no end, so they get a LIVE badge instead of a time.
  readonly property bool isLive: MediaModel.isLiveStream(activePlayer)

  // The bar only shows a tooltip while its target reports tooltipHovered;
  // without it the tooltip was never shown. Not while the popup is open,
  // which already shows the same info.
  readonly property bool tooltipHovered: widgetArea.containsMouse && !popupOpen
  readonly property string tooltipText: MediaModel.tooltipLabel(
    { title: title, artist: artist, album: album, player: playerName, live: isLive })

  // Elapsed / total time for the bar. Empty when the player doesn't report it.
  readonly property string timeText: {
    var p = activePlayer
    if (!p || !p.positionSupported || isLive) return ""
    var elapsed = formatTime(p.position)
    return p.lengthSupported && p.length > 0 ? elapsed + " / " + formatTime(p.length) : elapsed
  }
  function formatTime(seconds) {
    var s = Math.max(0, Math.floor(seconds))
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    var sec = s % 60
    return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (sec < 10 ? "0" : "") + sec
  }
  property bool settingsOpen: false
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string playIcon: activePlayer && activePlayer.isPlaying ? "󰏤" : "󰐊"
  readonly property string title: activePlayer ? MediaModel.clip(activePlayer.trackTitle) : ""
  readonly property string artist: activePlayer ? MediaModel.clip(activePlayer.trackArtist) : ""

  property bool popupOpen: false

  // "LIVE" pill shown where the time would be.
  component LiveBadge: Rectangle {
    property string family: ""
    property int pixelSize: Style.font.caption
    implicitWidth: liveText.implicitWidth + Style.space(8)
    implicitHeight: liveText.implicitHeight + Style.space(2)
    radius: height / 2
    color: Color.urgent

    Text {
      id: liveText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "LIVE"
      color: Color.background
      font.family: parent.family
      font.pixelSize: parent.pixelSize
      font.bold: true
    }
  }

  // Small clickable glyph for the bar (previous / next). It only reports the
  // click; the widget-wide MouseArea below still handles everything else.
  component BarButton: Item {
    id: btn
    property string glyphText: ""
    property color fg: Color.foreground
    property string family: ""
    property real pixelSize: 12
    property bool active: true
    // False where a click must fall through to the widget (e.g. the only
    // clickable thing on a vertical bar is the icon, and it opens the popup).
    property bool clickable: true
    signal activated()

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight
    width: implicitWidth
    height: implicitHeight
    opacity: active ? 1 : 0.4

    Text {
      id: label
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: btn.glyphText
      color: hit.containsMouse && hit.enabled ? Color.accent : btn.fg
      font.family: btn.family
      font.pixelSize: btn.pixelSize
    }

    MouseArea {
      id: hit
      anchors.fill: parent
      // A bigger target than the glyph itself: the bar is thin.
      anchors.margins: -Style.space(4)
      enabled: btn.active && btn.clickable
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.activated()
    }
  }

  readonly property var rateSteps: [0.75, 1, 1.25, 1.5, 2]
  readonly property bool rateAdjustable: activePlayer !== null && activePlayer.maxRate > activePlayer.minRate

  function seekBy(seconds) {
    var p = activePlayer
    if (!p || !p.canSeek || !p.positionSupported || !p.lengthSupported || p.length <= 0) return
    p.position = Math.max(0, Math.min(p.length, p.position + seconds))
    p.positionChanged()
  }

  // Volume. Chromium-based browsers (Brave, Chrome, web apps) report an MPRIS
  // volume but ignore changes to it, so the slider did nothing for them.
  // Instead, change the player's own audio stream in PipeWire when one can be
  // matched to it (like the system mixer does), and only fall back to MPRIS
  // volume when there's no matching stream.
  readonly property var playerStream: {
    var p = activePlayer
    if (!p) return null
    var key = MediaModel.streamLabelKey(MediaModel.playerAppLabel(p))
    if (!key) return null
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream || !n.audio || !MediaModel.isPlaybackStream(n)) continue
      var streamKey = MediaModel.streamLabelKey(MediaModel.rawStreamLabel(n))
      if (streamKey && (streamKey === key || streamKey.indexOf(key) !== -1 || key.indexOf(streamKey) !== -1))
        return n
    }
    return null
  }
  PwObjectTracker { objects: root.playerStream ? [root.playerStream] : [] }

  readonly property bool usesStreamVolume: playerStream !== null && playerStream.ready && playerStream.audio !== null
  readonly property bool volumeAvailable: usesStreamVolume || (activePlayer !== null && activePlayer.volumeSupported)
  readonly property real currentVolume: usesStreamVolume ? playerStream.audio.volume
    : (activePlayer && activePlayer.volumeSupported ? activePlayer.volume : 0)

  function applyVolume(value) {
    if (usesStreamVolume) playerStream.audio.volume = value
    else if (activePlayer && activePlayer.volumeSupported) activePlayer.volume = value
  }

  // Mute. On the PipeWire stream when there is one (browsers ignore MPRIS
  // mute too); otherwise fake it by dropping MPRIS volume to 0 and back.
  property real volumeBeforeMute: -1
  readonly property bool muted: usesStreamVolume ? playerStream.audio.muted
    : (volumeBeforeMute >= 0 && currentVolume <= 0)
  function toggleMute() {
    if (usesStreamVolume) { playerStream.audio.muted = !playerStream.audio.muted; return }
    if (!activePlayer || !activePlayer.volumeSupported) return
    if (muted) { activePlayer.volume = volumeBeforeMute; volumeBeforeMute = -1 }
    else { volumeBeforeMute = activePlayer.volume; activePlayer.volume = 0 }
  }

  // Output device. Moves only this player's stream to another sink, the way
  // pavucontrol does (pactl's sink-input index is the stream's object.serial).
  readonly property var outputSinks: {
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    return nodes.filter(function(n) { return n && n.isSink && !n.isStream && n.audio })
  }
  PwNodeLinkTracker { id: streamLinks; node: root.playerStream }
  readonly property var currentSink: {
    var groups = streamLinks.linkGroups || []
    for (var i = 0; i < groups.length; i++)
      if (groups[i] && groups[i].target && groups[i].target.isSink) return groups[i].target
    return null
  }
  readonly property bool outputSwitchable: usesStreamVolume && outputSinks.length > 1
  function sinkLabel(n) {
    return String(n.nickname || n.description || n.name || "Output")
  }
  function moveToSink(sink) {
    if (!usesStreamVolume || !sink || sink === currentSink || moveProcess.running) return
    var serial = playerStream.properties ? playerStream.properties["object.serial"] : undefined
    if (serial === undefined) return
    moveProcess.command = ["pactl", "move-sink-input", String(serial), String(sink.name)]
    moveProcess.running = true
  }
  Process { id: moveProcess }

  // Copy "Artist – Title" (or the track's URL when the player gives one).
  property bool justCopied: false
  function copyTrack() {
    var p = activePlayer
    if (!p || copyProcess.running) return
    var md = p.metadata || {}
    var url = String(md["xesam:url"] || "")
    var text = /^https?:/.test(url) ? url
      : [p.trackArtist, p.trackTitle].filter(function(x) { return !!x }).join(" – ")
    if (!text) return
    copyProcess.command = ["wl-copy", "--", text]
    copyProcess.running = true
    justCopied = true
    copiedTimer.restart()
  }
  Process { id: copyProcess }
  Timer { id: copiedTimer; interval: 1500; onTriggered: root.justCopied = false }

  function adjustVolume(delta) {
    if (!volumeAvailable) return
    var base = pendingVolume >= 0 ? pendingVolume : currentVolume
    queueVolume(Math.max(0, Math.min(1, base + delta)))
  }

  function cycleRate() {
    var p = activePlayer
    if (!p || !rateAdjustable) return
    var steps = rateSteps.filter(function(r) { return r >= p.minRate && r <= p.maxRate })
    if (steps.length === 0) return
    var next = steps[0]
    for (var i = 0; i < steps.length; i++) {
      if (steps[i] > p.rate + 0.001) { next = steps[i]; break }
    }
    p.rate = next
  }

  function cycleRepeat() {
    var p = activePlayer
    if (p && !p.loopSupported && spotifyWebControls) {
      if (sendSpotifyShortcut("R")) spotifyRepeatGuess = (spotifyRepeatGuess + 1) % 3
      return
    }
    if (!p || !p.loopSupported) return
    // off -> repeat playlist -> repeat track -> off
    p.loopState = p.loopState === MprisLoopState.None ? MprisLoopState.Playlist
      : (p.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None)
  }

  function toggleShuffle() {
    var p = activePlayer
    if (p && !p.shuffleSupported && spotifyWebControls) {
      if (sendSpotifyShortcut("S")) spotifyShuffleGuess = !spotifyShuffleGuess
      return
    }
    if (p && p.shuffleSupported) p.shuffle = !p.shuffle
  }

  // Tab / Shift+Tab: pick which player the popup manages, following the
  // order of the source list. Playback is left alone.
  function cycleSource(direction) {
    var list = sourcePlayers
    if (!mediaService || !list || list.length < 2) return
    var activeKey = mediaService.playerKey(activePlayer)
    var index = 0
    for (var i = 0; i < list.length; i++) {
      if (mediaService.playerKey(list[i]) === activeKey) { index = i; break }
    }
    var next = list[(index + direction + list.length) % list.length]
    mediaService.selectPlayer(mediaService.playerKey(next))
  }

  // Players that can't raise themselves (Chromium-based browsers and web apps
  // report CanRaise = false) get their window focused through Hyprland
  // instead: first a window whose title contains the track title (a web app
  // or the browser tab showing it), else any window of that app.
  readonly property bool canOpenPlayer: !!activePlayer
    && (activePlayer.canRaise || (title !== "" || playerName !== ""))

  readonly property string _focusScript: [
    "addr=$(hyprctl clients -j | jq -r --arg t \"$1\" --arg c \"$2\" '",
    "  (map(select($t != \"\" and (.title | ascii_downcase | contains($t | ascii_downcase))))",
    "   + map(select($c != \"\" and (.class | ascii_downcase | contains($c | ascii_downcase)))))",
    "  | .[0].address // empty')",
    "[ -n \"$addr\" ] || exit 1",
    "hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:$addr\\\" })\" >/dev/null 2>&1 \\",
    "  || hyprctl dispatch focuswindow \"address:$addr\" >/dev/null 2>&1"
  ].join("\n")

  Process { id: focusProcess }

  // Shuffle / repeat for the Spotify web app. Browsers don't expose shuffle
  // or repeat over MPRIS, so for a Chromium-based player whose window is the
  // Spotify web app (class contains "open.spotify.com"), the buttons send
  // Spotify's own shortcuts (Alt+S / Alt+R) straight to that window instead.
  // Spotify doesn't report the state back, so the buttons show a guess: they
  // assume both start off and track our own clicks. Clicking Spotify's own
  // buttons (or reloading it) makes the guess wrong until clicked back.
  // Every other player without native support keeps them hidden.
  property string spotifyWebWindow: ""
  onSpotifyWebWindowChanged: { spotifyShuffleGuess = false; spotifyRepeatGuess = 0 }
  property bool spotifyShuffleGuess: false
  property int spotifyRepeatGuess: 0 // 0 off, 1 repeat all, 2 repeat one (Spotify's Alt+R cycle)
  readonly property bool spotifyWebControls: spotifyWebWindow !== "" && !!activePlayer
    && !activePlayer.shuffleSupported && !activePlayer.loopSupported

  Process {
    id: spotifyFinder
    // $1 = track title. The window must be the Spotify web app AND show the
    // track that's playing, so a YouTube tab playing while Spotify is open
    // doesn't get Spotify's buttons.
    readonly property string script: "hyprctl clients -j | jq -r --arg t \"$1\" "
      + "'[.[] | select((.class | test(\"open\\\\.spotify\\\\.com\")) and $t != \"\" "
      + "and (.title | ascii_downcase | contains($t | ascii_downcase)))] | .[0].address // empty'"
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var addr = text.trim()
        root.spotifyWebWindow = /^0x[0-9a-f]+$/.test(addr) ? addr : ""
      }
    }
  }

  function refreshSpotifyWebWindow() {
    var p = activePlayer
    // Only Chromium-based players can be the web app.
    if (!p || p.shuffleSupported || p.loopSupported || p.canRaise) { spotifyWebWindow = ""; return }
    if (spotifyFinder.running) return
    spotifyFinder.command = ["bash", "-c", spotifyFinder.script, "_", String(p.trackTitle || "")]
    spotifyFinder.running = true
  }

  onActivePlayerChanged: { volumeBeforeMute = -1; refreshSpotifyWebWindow() }
  onTitleChanged: refreshSpotifyWebWindow()

  function sendSpotifyShortcut(key) {
    if (!spotifyWebControls || shortcutProcess.running) return false
    shortcutProcess.command = ["hyprctl", "dispatch",
      "hl.dsp.send_shortcut({ mods = \"ALT\", key = \"" + key + "\", window = \"address:" + spotifyWebWindow + "\" })"]
    shortcutProcess.running = true
    return true
  }

  Process { id: shortcutProcess }

  // Brings the Spotify window forward and toggles its queue panel
  // (Alt+Shift+Q). It's a toggle, so it closes the queue if already open.
  function openSpotifyQueue() {
    if (!spotifyWebControls || shortcutProcess.running) return
    var win = "address:" + spotifyWebWindow
    shortcutProcess.command = ["bash", "-c",
      "hyprctl dispatch \"$1\" >/dev/null && hyprctl dispatch \"$2\" >/dev/null", "_",
      "hl.dsp.focus({ window = \"" + win + "\" })",
      "hl.dsp.send_shortcut({ mods = \"ALT SHIFT\", key = \"Q\", window = \"" + win + "\" })"]
    shortcutProcess.running = true
    popupOpen = false
  }

  function openPlayer() {
    var p = activePlayer
    if (!p) return
    if (p.canRaise) {
      p.raise()
    } else {
      if (focusProcess.running) return
      // "Brave" -> "brave" matches window classes like brave-browser and
      // brave-open.spotify.com__-Default.
      var app = String(p.identity || p.desktopEntry || "").toLowerCase().split(" ")[0]
      focusProcess.command = ["bash", "-c", root._focusScript, "_", String(p.trackTitle || ""), app]
      focusProcess.running = true
    }
    popupOpen = false
  }

  // Every action is a D-Bus call to the player. Bursts (wheel notches, double
  // clicks, key repeat) make players like Spotify stall, and isPlaying lags the
  // real state, so a fast second play/pause would repeat the first one. Drop
  // actions that arrive too soon after the previous one.
  property double lastActionAt: 0
  function transport(action, minGapMs) {
    if (!mediaService || !activePlayer) return
    var now = Date.now()
    if (now - lastActionAt < (minGapMs || 200)) return
    lastActionAt = now
    mediaService.runAction(action, false, mediaService.playerKey(activePlayer))
  }

  // Wheel seeks and volume drags fire per event; batch them into one call.
  property real pendingSeek: 0
  Timer {
    id: seekFlush
    interval: 150
    onTriggered: {
      var d = root.pendingSeek
      root.pendingSeek = 0
      if (d !== 0) root.seekBy(d)
    }
  }
  function queueSeek(seconds) {
    pendingSeek += seconds
    if (!seekFlush.running) seekFlush.start()
  }

  property real pendingVolume: -1
  Timer {
    id: volumeFlush
    interval: 60
    onTriggered: root.flushVolume()
  }
  function flushVolume() {
    volumeFlush.stop()
    if (pendingVolume >= 0 && volumeAvailable) applyVolume(pendingVolume)
    pendingVolume = -1
  }
  function queueVolume(value) {
    pendingVolume = value
    if (!volumeFlush.running) volumeFlush.start()
  }

  function close() { popupOpen = false }

  // MPRIS doesn't push the position while playing; only poll when the bar
  // actually shows the time.
  Timer {
    interval: 1000
    repeat: true
    running: root.shown && root.prefs.showTime && !root.isLive && root.activePlayer !== null && root.activePlayer.isPlaying
    onTriggered: root.activePlayer.positionChanged()
  }
  onPopupOpenChanged: {
    if (!popupOpen) settingsOpen = false
    else refreshSpotifyWebWindow()
  }

  readonly property bool shown: hasMedia && (!prefs.hideWhenPaused || (activePlayer !== null && activePlayer.isPlaying))

  visible: shown
  implicitWidth: shown ? row.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  // Size of the mark the bar draws under (or beside) the widget while its popup
  // is open. Without these hints the bar draws about half the widget's width,
  // which stops well short of the text; report the full extent instead.
  readonly property real openPanelIndicatorWidth: implicitWidth
  readonly property real openPanelIndicatorHeight: implicitHeight

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)
    // Above the widget-wide MouseArea (declared below) so the buttons get their
    // clicks; the rest of the row has no handlers, so everything else falls
    // through to that MouseArea.
    z: 1

    Image {
      id: cover
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(root.barSize - Style.space(8), Style.space(22))
      height: width
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      source: root.artUrl
      visible: root.prefs.showCover && source !== ""
    }

    BarButton {
      id: prevButton
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical && root.prefs.showPrevious
      glyphText: "󰒮"
      fg: root.bar.barForeground
      family: root.bar.fontFamily
      pixelSize: Style.font.body
      active: root.activePlayer !== null && !!root.activePlayer.canGoPrevious
      onActivated: root.transport("previous")
    }

    BarButton {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      glyphText: root.playIcon
      visible: root.prefs.showIcon || (root.barText === "" && !cover.visible && !timeLabel.visible && !prevButton.visible && !nextButton.visible)
      fg: activePlayer && activePlayer.isPlaying ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
      family: root.bar.fontFamily
      pixelSize: Style.font.body
      active: root.activePlayer !== null
        && !!(root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
      clickable: !root.bar.vertical
      onActivated: root.transport("playPause")
      Behavior on fg {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    BarButton {
      id: nextButton
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical && root.prefs.showNext
      glyphText: "󰒭"
      fg: root.bar.barForeground
      family: root.bar.fontFamily
      pixelSize: Style.font.body
      active: root.activePlayer !== null && !!root.activePlayer.canGoNext
      onActivated: root.transport("next")
    }

    Item {
      id: scrollClip
      width: root.prefs.dynamicWidth ? labelText.implicitWidth : root.prefs.maxWidth
      height: glyph.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical && root.barText !== ""

      Text {
        id: labelText
        textFormat: Text.PlainText
        text: root.barText
        color: root.bar.barForeground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
        // Fit mode shows the whole text. A fixed width either scrolls, or (cut
        // mode) uses the shortened text, elided to the width as a safety net.
        elide: !root.prefs.dynamicWidth && root.prefs.textMode === "ellipsis" ? Text.ElideRight : Text.ElideNone
        width: !root.prefs.dynamicWidth && root.prefs.textMode === "ellipsis" ? scrollClip.width : implicitWidth

        property bool needsScroll: !root.prefs.dynamicWidth && root.prefs.textMode === "scroll" && implicitWidth > scrollClip.width

        NumberAnimation on x {
          id: scrollAnim
          running: labelText.needsScroll && !root.popupOpen && !root.bar.vertical
          loops: Animation.Infinite
          duration: Math.max(6000, labelText.implicitWidth * 25)
          from: scrollClip.width
          to: -labelText.implicitWidth
          easing.type: Easing.Linear
          onRunningChanged: if (!running) labelText.x = 0
        }
      }
    }

    Text {
      id: timeLabel
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical && root.prefs.showTime && root.timeText !== ""
      text: root.timeText
      color: Qt.darker(root.bar.barForeground, 1.3)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }

    LiveBadge {
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical && root.prefs.showTime && root.isLive
      family: root.bar.fontFamily
    }
  }

  MouseArea {
    id: widgetArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.activePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (!root.activePlayer) return
      if (mouse.button === Qt.MiddleButton) {
        root.transport("next")
      } else if (mouse.button === Qt.RightButton) {
        root.transport("playPause")
      } else {
        root.popupOpen = !root.popupOpen
      }
    }
    onWheel: function(wheel) {
      if (!root.activePlayer) return
      if (wheel.angleDelta.y > 0) root.transport("previous", 350)
      else if (wheel.angleDelta.y < 0) root.transport("next", 350)
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.hasMedia ? root.tooltipText : "")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(root.settingsOpen ? settingsView.implicitHeight : column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.settingsOpen) return
        if (dx !== 0) root.queueSeek(dx * 5)
        else root.adjustVolume(-dy * 0.05)
      }
      onActivateRequested: if (!root.settingsOpen) root.transport("playPause")
      onCloseRequested: { if (root.settingsOpen) root.settingsOpen = false; else root.close() }
      onTabRequested: function(direction) { if (!root.settingsOpen) root.cycleSource(direction) }
      onTextKey: function(t) {
        if (root.settingsOpen && t !== "q" && t !== "Q" && t !== "c" && t !== "C") return
        if (t === "q" || t === "Q") { if (root.settingsOpen) root.settingsOpen = false; else root.close() }
        else if (t === "c" || t === "C") root.settingsOpen = !root.settingsOpen
        else if (t === "n" || t === "N") root.transport("next")
        else if (t === "p" || t === "P") root.transport("previous")
        else if (t === "s" || t === "S") root.toggleShuffle()
        else if (t === "r" || t === "R") root.cycleRepeat()
        else if (t === "f" || t === "F") root.cycleRate()
        else if (t === "o" || t === "O") root.openPlayer()
      }

      Flickable {
        id: settingsFlick
        anchors.fill: parent
        visible: root.settingsOpen
        contentWidth: width
        contentHeight: settingsView.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        AdvancedSettings {
          id: settingsView
          width: settingsFlick.width
          prefs: root.prefs
          foreground: root.bar.foreground
          sampleTitle: root.title
          sampleArtist: root.artist
          sampleAlbum: root.album
          samplePlayer: root.playerName
          fontFamily: root.bar.fontFamily
          onChanged: function(name, value) { root.setPref(name, value) }
          onResetRequested: root.resetPrefs()
          onBackRequested: root.settingsOpen = false
        }
      }

      Button {
        iconText: "󰒓"
        z: 2
        anchors.top: parent.top
        anchors.right: parent.right
        visible: !root.settingsOpen
        foreground: root.bar.foreground
        horizontalPadding: Style.spacing.controlPaddingX
        verticalPadding: Style.spacing.controlPaddingY
        tooltipText: "Advanced options"
        onClicked: root.settingsOpen = true
      }

      Column {
        id: column
        visible: !root.settingsOpen
        anchors.fill: parent
        spacing: Style.space(10)

        Row {
          spacing: Style.space(10)
          width: parent.width

          BorderSurface {
            width: Style.space(64)
            height: Style.space(64)
            radius: Style.spacing.labelGap
            color: Style.normalFillFor(root.bar.foreground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

            Image {
              anchors.fill: parent
              anchors.margins: Style.space(2)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              source: root.artUrl
              visible: source !== ""
            }

            Text {
              anchors.centerIn: parent
              visible: root.artUrl === ""
              text: "󰝚"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.displayLarge
            }
          }

          Column {
            spacing: Style.space(4)
            width: parent.width - Style.space(74) - Style.space(30)

            Text {
              textFormat: Text.PlainText
              text: root.justCopied ? "Copied" : (root.title || "Nothing playing")
              color: titleHit.containsMouse && root.hasMedia ? Color.accent : root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
              width: parent.width

              MouseArea {
                id: titleHit
                anchors.fill: parent
                enabled: root.hasMedia
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copyTrack()
              }
            }

            Text {
              textFormat: Text.PlainText
              text: root.artist
              color: Qt.darker(root.bar.foreground, 1.3)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }

            Text {
              textFormat: Text.PlainText
              text: root.album
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }
          }
        }

        // Live streams have no end to seek to: the badge plus a full,
        // display-only track take the progress bar's place.
        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: root.isLive

          LiveBadge {
            id: popupLiveBadge
            anchors.verticalCenter: parent.verticalCenter
            family: root.bar.fontFamily
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - popupLiveBadge.width - parent.spacing
            height: Style.space(4)
            radius: height / 2
            color: Color.urgent
          }
        }

        Column {
          id: progress
          width: parent.width
          spacing: Style.space(4)

          readonly property bool available: root.activePlayer !== null
            && root.activePlayer.lengthSupported && root.activePlayer.positionSupported
            && root.activePlayer.length > 0 && !root.isLive
          readonly property bool seekable: available && root.activePlayer.canSeek
          readonly property real length: available ? root.activePlayer.length : 0
          readonly property real position: available ? Math.max(0, Math.min(length, root.activePlayer.position)) : 0
          property bool dragging: false
          property real dragPosition: 0
          readonly property real shown: dragging ? dragPosition : position

          visible: available

          function format(seconds) {
            var s = Math.max(0, Math.floor(seconds))
            var h = Math.floor(s / 3600)
            var m = Math.floor((s % 3600) / 60)
            var sec = s % 60
            var mm = (h > 0 && m < 10 ? "0" : "") + m
            return (h > 0 ? h + ":" : "") + mm + ":" + (sec < 10 ? "0" : "") + sec
          }

          // MPRIS does not push position updates while playing, so ask for a
          // fresh position several times per second to keep the bar moving smoothly.
          Timer {
            interval: 250
            repeat: true
            triggeredOnStart: true
            running: root.popupOpen && progress.available && !progress.dragging
              && root.activePlayer.isPlaying
            onTriggered: root.activePlayer.positionChanged()
          }

          // Paused players don't tick, but still refresh once when the popup opens
          // or the track changes so the bar never shows a stale time.
          Connections {
            target: root
            function onPopupOpenChanged() {
              if (root.popupOpen && root.activePlayer) root.activePlayer.positionChanged()
            }
          }

          Item {
            id: seekBar
            width: parent.width
            height: Style.space(16)

            function seekTo(x) {
              progress.dragPosition = Math.max(0, Math.min(1, x / width)) * progress.length
            }

            Rectangle {
              id: track
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: Style.space(4)
              radius: height / 2
              color: Util.alpha(root.bar.foreground, 0.2)

              Rectangle {
                width: progress.length > 0 ? parent.width * progress.shown / progress.length : 0
                height: parent.height
                radius: parent.radius
                color: Color.accent
              }
            }

            // Highlighted knob at the current position; grows while dragging.
            Rectangle {
              property real size: Style.space(progress.dragging ? 16 : 12)
              width: size
              height: size
              radius: size / 2
              anchors.verticalCenter: parent.verticalCenter
              x: Math.max(0, Math.min(seekBar.width - size,
                (progress.length > 0 ? seekBar.width * progress.shown / progress.length : 0) - size / 2))
              color: Color.accent
              border.width: Style.space(2)
              border.color: root.bar.foreground

              Behavior on size {
                NumberAnimation { duration: 100 }
              }
            }

            MouseArea {
              anchors.fill: parent
              enabled: progress.seekable
              cursorShape: progress.seekable ? Qt.PointingHandCursor : Qt.ArrowCursor
              onPressed: function(mouse) {
                progress.dragging = true
                seekBar.seekTo(mouse.x)
              }
              onPositionChanged: function(mouse) {
                if (progress.dragging) seekBar.seekTo(mouse.x)
              }
              onReleased: {
                if (progress.dragging && root.activePlayer) root.activePlayer.position = progress.dragPosition
                progress.dragging = false
              }
              onCanceled: progress.dragging = false
              onWheel: function(wheel) {
                root.queueSeek(wheel.angleDelta.y > 0 ? 5 : -5)
              }
            }
          }

          Item {
            width: parent.width
            height: elapsed.implicitHeight

            Text {
              id: elapsed
              textFormat: Text.PlainText
              anchors.left: parent.left
              text: progress.format(progress.shown)
              color: Qt.darker(root.bar.foreground, 1.3)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              text: progress.format(progress.length)
              color: Qt.darker(root.bar.foreground, 1.3)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)

          Button {
            iconText: "󰒝"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            visible: (!!root.activePlayer && root.activePlayer.shuffleSupported) || root.spotifyWebControls
            selected: root.activePlayer && root.activePlayer.shuffleSupported ? root.activePlayer.shuffle
              : (root.spotifyWebControls && root.spotifyShuffleGuess)
            tooltipText: "Shuffle"
            onClicked: root.toggleShuffle()
          }

          Button {
            iconText: "󰒮"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.activePlayer && root.activePlayer.canGoPrevious
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.transport("previous")
          }

          Button {
            iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.panelGap
            verticalPadding: Style.spacing.controlPaddingY
            iconSize: Style.font.iconLarge
            enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.transport("playPause")
          }

          Button {
            iconText: "󰒭"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.activePlayer && root.activePlayer.canGoNext
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.transport("next")
          }

          Button {
            iconText: (root.activePlayer && root.activePlayer.loopSupported
              ? root.activePlayer.loopState === MprisLoopState.Track
              : (root.spotifyWebControls && root.spotifyRepeatGuess === 2)) ? "󰑘" : "󰑖"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            visible: (!!root.activePlayer && root.activePlayer.loopSupported) || root.spotifyWebControls
            selected: root.activePlayer && root.activePlayer.loopSupported ? root.activePlayer.loopState !== MprisLoopState.None
              : (root.spotifyWebControls && root.spotifyRepeatGuess !== 0)
            tooltipText: "Repeat"
            onClicked: root.cycleRepeat()
          }

          Button {
            iconText: "󰏌"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            visible: root.canOpenPlayer
            tooltipText: "Open player"
            onClicked: root.openPlayer()
          }

          Button {
            iconText: "󰲸"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            visible: root.spotifyWebControls
            tooltipText: "Queue"
            onClicked: root.openSpotifyQueue()
          }

          Button {
            text: root.activePlayer ? (Math.round(root.activePlayer.rate * 100) / 100) + "x" : ""
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            visible: root.rateAdjustable
            selected: visible && Math.abs(root.activePlayer.rate - 1) > 0.001
            tooltipText: "Playback speed"
            onClicked: root.cycleRate()
          }
        }

        Row {
          id: volume
          width: parent.width
          spacing: Style.space(8)
          visible: root.volumeAvailable

          property bool dragging: false
          property real dragValue: 0
          readonly property real level: dragging ? dragValue
            : Math.max(0, Math.min(1, root.currentVolume))

          Text {
            id: volumeIcon
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: root.muted || volume.level <= 0 ? "󰝟" : (volume.level < 0.5 ? "󰖀" : "󰕾")
            color: muteHit.containsMouse ? Color.accent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.icon

            MouseArea {
              id: muteHit
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleMute()
            }
          }

          Item {
            id: volumeBar
            width: parent.width - volumeIcon.width - volumePercent.width - parent.spacing * 2
            height: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter

            function setFrom(x) {
              volume.dragValue = Math.max(0, Math.min(1, x / width))
              root.queueVolume(volume.dragValue)
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: Style.space(4)
              radius: height / 2
              color: Util.alpha(root.bar.foreground, 0.2)

              Rectangle {
                width: parent.width * volume.level
                height: parent.height
                radius: parent.radius
                color: Color.accent
                opacity: root.muted ? 0.35 : 1
              }
            }

            Rectangle {
              readonly property real size: Style.space(12)
              width: size
              height: size
              radius: size / 2
              anchors.verticalCenter: parent.verticalCenter
              x: Math.max(0, Math.min(volumeBar.width - size, volumeBar.width * volume.level - size / 2))
              color: Color.accent
              border.width: Style.space(2)
              border.color: root.bar.foreground
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onPressed: function(mouse) {
                volume.dragging = true
                volumeBar.setFrom(mouse.x)
              }
              onPositionChanged: function(mouse) {
                if (volume.dragging) volumeBar.setFrom(mouse.x)
              }
              onReleased: {
              root.flushVolume()
              volume.dragging = false
            }
              onCanceled: volume.dragging = false
            }
          }

          Text {
            id: volumePercent
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(34)
            horizontalAlignment: Text.AlignRight
            text: root.muted ? "Muted" : Math.round(volume.level * 100) + "%"
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Flow {
          id: outputs
          width: parent.width
          spacing: Style.space(4)
          visible: root.outputSwitchable

          Repeater {
            model: outputs.visible ? root.outputSinks : []

            Button {
              required property var modelData
              text: root.sinkLabel(modelData)
              foreground: root.bar.foreground
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              selected: modelData === root.currentSink
              tooltipText: String(modelData.description || modelData.name || "")
              onClicked: root.moveToSink(modelData)
            }
          }
        }

        PanelSeparator {
          visible: root.sourcePlayers.length > 1
          foreground: root.bar.foreground
        }

        Column {
          id: sourceList
          visible: root.sourcePlayers.length > 1
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.sourcePlayers

            CursorSurface {
              id: sourceRow
              required property var modelData

              readonly property var player: modelData
              readonly property bool selected: root.activePlayer && player
                && root.mediaService.playerKey(root.activePlayer) === root.mediaService.playerKey(player)
              readonly property string sourceTitle: player ? MediaModel.clip(player.trackTitle || player.identity || player.desktopEntry || "Media source") : "Media source"
              readonly property string sourceDetail: player && player.trackArtist ? MediaModel.clip(player.trackArtist) : (player && player.identity ? MediaModel.clip(player.identity) : "")

              width: sourceList.width
              height: sourceInner.implicitHeight + Style.space(10)
              radius: Style.spacing.labelGap
              foreground: root.bar.foreground
              current: selected

              Row {
                id: sourceInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
                anchors.rightMargin: sourceRow.borderRight + Style.space(8)
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  width: Style.space(18)
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  width: parent.width - Style.space(26)
                  spacing: Style.space(1)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    textFormat: Text.PlainText
                    text: sourceRow.sourceTitle
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: sourceRow.selected
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: sourceRow.sourceDetail
                    color: Qt.darker(root.bar.foreground, 1.5)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                    visible: text !== ""
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: sourceRow.hasCursor = true
                onExited: sourceRow.hasCursor = false
                onClicked: if (root.mediaService) root.mediaService.selectPlayer(root.mediaService.playerKey(sourceRow.player))
              }
            }
          }
        }
      }
    }
  }
}
