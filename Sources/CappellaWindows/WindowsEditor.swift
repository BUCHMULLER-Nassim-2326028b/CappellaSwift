import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation

@MainActor
final class WindowsEditor {
    let window = Window()
    let document = WindowsDocument()
    let media = WindowsMedia()
    let root = Grid()
    var videoOnly = false
    var applyVideoOnlyLayout: ((Bool) -> Void)?
    let windowChrome = Grid()
    let customTitleBar = Grid()
    let titleText = label("Cappella", size: 12)
    let titleLogo = Image()
    var resizeRegions: [WindowsResizeRegion] = []
    var resizeRegion: WindowsResizeRegion?
    var resizeOrigin = 0.0
    var resizeValue = 0.0
    var resizeDPI = 1.0
    var resizeCoordinate: Double?
    let resizeTimer = DispatcherTimer()
    var menuChecks: [(ToggleMenuFlyoutItem, () -> Bool)] = []
    var handledDesktopKeys = Set<UInt>()
    var isClosed = false
    var onClosed: (() -> Void)?
    var closeApproved = false
    var closePromptActive = false
    let editorAdornments = Canvas()
    let caretTimer = DispatcherTimer()
    var caretVisible = true
    var isResizing = false
    let script = StackPanel()
    let scriptScroll = ScrollViewer()
    var scriptCues: [Cue] = []
    var scriptPlaybackState: DialogueScriptState?
    var scriptActiveIDs = Set<UUID>()
    var scriptFollowID: UUID?
    var scriptPlaybackFrame: Int?
    var scriptPlaybackRevision = UInt64.max
    var scriptPlaybackDark: Bool?
    var scriptOrder: [UUID] = []
    var scriptRows: [UUID: (border: Border, header: TextBlock, text: TextBlock)] = [:]
    var scriptSelection: UUID?
    var scriptRevision = UInt64.max
    var scriptModels: [UUID: Cue] = [:]
    var scriptRoles: [Role] = []
    var scriptFPS = 0
    var lastWindowTitle: String?
    var appliedDark: Bool?
    var appliedBandHeight = 0.0
    var displayedFrame: Int?
    var displayedFPS = 0
    var displayedLoop: Marker?
    var displayedVI: Bool?
    var renderingSubscription: EventCleanup?
    lazy var bandTextCursor = try? InputSystemCursor.create(.ibeam)
    let bandMotionLayer = Canvas()
    let band = Canvas()
    let bandBackdrop = Canvas()
    let bandRuler = Canvas()
    var rulerState: WindowsRulerState?
    let bandOverlay = Canvas()
    let bandTranslation = CompositeTransform()
    let bandMotion = WindowsTimelineMotion()
    var timelineClock = WindowsTimelineClock()
    var bandCueViews: [UUID: Canvas] = [:]
    var bandMarkerViews: [UUID: Canvas] = [:]
    var lastBandPopulation = -Double.infinity
    var bandOriginFrame = 0
    var bandCacheWidth = 0.0
    var bandCacheHeight = 0.0
    var bandState: WindowsBandState?
    var bandIndexedCues: [(cue: Cue, end: Double)] = []
    var bandPrefixEnds: [Double] = []
    var playbackFrame: Double?
    var lastAutosavePoll = Date.distantPast
    let timelineScrollbar = ScrollBar()
    var timelineScrollRevision = UInt64.max
    var timelineScrollEnd = 0
    var updatingTimelineScrollbar = false
    var timelineScrollRangeCache: TimelineScrollRange?
    var timelineWheelScroll = TimelineWheelScroll()
    let bandContainer = Grid()
    let editorLayer = Canvas()
    let timecode = label("00:00:00:00", size: 28, color: ink(0xFFFFFF))
    let loopLabel = label("", size: 13, color: ink(0xDDDDDD))
    let loopRange = label("", size: 10, color: ink(0x6E8796))
    let clockPanel = Border()
    var displayedLoopEnd: Int?
    var clockProjectRevision = UInt64.max
    var clockLastCueEnd = 0
    var displayedClockMedia: Bool?
    let videoView = MediaPlayerElement()
    let vo = button("VO", action: {})
    let vi = button("VI", action: {})
    let timer = DispatcherTimer()
    var textEditor: TextBox?
    var textEditorCue: UUID?
    var pendingReaction: UUID?
    var changingText = false
    var phrasePasteActive = false
    var timelineSelectionOrigin: Int?
    var timelineLastClick: (cue: Foundation.UUID, time: Double, x: Double, y: Double)?
    var dialogShowing = false
    var activeDialog: ContentDialog?
    var lastRenderUptime = ProcessInfo.processInfo.systemUptime
    let editorMeasurement = TextBlock()
    var timelineMeasurementFont = ""
    var timelineMeasurementSize = 0.0
    var timelineMeasurementSentinel = 0.0
    var timelineMeasuredWidths: [String: Double] = [:]
    var textSelectionAnchor: (UUID, Int, Double)?
    var dragSign: (UUID, UUID, Int, Double)?
    var dragMoved = false
    var pointerWasLeft = false
    var logicalFrame: Double?
    var projection: Window?
    var projectionVideo: MediaPlayerElement?
    var previewImage: Image?
    var status = label("")
    var search = DialogueSearch()
    var dark: Bool { self.document.preferences.appearance == "dark" }
    var fps: Int { self.document.project.framesPerSecond }
    var scale: Double { self.document.preferences.pixelsPerSecond / Double(max(1, fps)) }
    var resources: URL { URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("Resources") }

    init() {
        window.title = "Cappella"
        try? window.appWindow.resize(SizeInt32(width: 1420, height: 800))
        media.videoOffset = self.document.preferences.videoOffsetMilliseconds / 1000
        buildLayout()
        installWindowChrome()
        root.sizeChanged.addHandler { [weak self] _, _ in self?.fitBandHeight() }
        self.document.changed = { [weak self] in self?.refresh() }
        media.failed = { [weak self] message in Task { @MainActor in await self?.showError(message) } }
        root.previewKeyDown.addHandler { [weak self] _, args in self?.keyDown(args) }
        bandContainer.sizeChanged.addHandler { [weak self] _, _ in self?.renderBand(); self?.updateTextEditor(); self?.refreshTimelineScrollbar() }
        bandContainer.pointerPressed.addHandler { [weak self] _, args in self?.pointerPressed(args) }
        bandContainer.pointerMoved.addHandler { [weak self] _, args in self?.pointerMoved(args) }
        bandContainer.pointerWheelChanged.addHandler { [weak self] _, args in self?.scrollTimeline(args) }
        bandContainer.pointerReleased.addHandler { [weak self] _, args in self?.pointerReleased(args) }
        bandContainer.pointerCanceled.addHandler { [weak self] _, _ in self?.cancelTimelinePointer() }
        bandContainer.pointerCaptureLost.addHandler { [weak self] _, _ in self?.cancelTimelinePointer() }
        bandContainer.rightTapped.addHandler { [weak self] _, args in self?.contextMenu(args) }
        vo.click.addHandler { [weak self] _, _ in guard let self else { return }; media.usingVI = false; media.applyAudio(); refreshClock() }
        vi.click.addHandler { [weak self] _, _ in guard let self else { return }; media.usingVI = true; media.applyAudio(); refreshClock() }
        window.appWindow.closing.addHandler { [weak self] _, args in
            guard let self, !closeApproved else { return }
            if self.document.dirty {
                args?.cancel = true
                guard !closePromptActive else { return }
                closePromptActive = true
                Task { @MainActor in
                    defer { self.closePromptActive = false }
                    if await self.mayReplace() { self.closeApproved = true; try? self.window.close() }
                }
            }
        }
        window.activated.addHandler { [weak self] _, args in
            if args?.windowActivationState == .deactivated { self?.endResize() }
        }
        media.playbackChanged = { [weak self] in self?.updatePlaybackRendering() }
        window.closed.addHandler { [weak self] _, _ in self?.shutdown() }
        // Only runs during a divider drag, including when WinUI consumes mouse
        // movement before the desktop pre-translation hook sees it.
        resizeTimer.interval = TimeSpan(duration: 80_000)
        resizeTimer.tick.addHandler { [weak self] _, _ in self?.pollResize() }
        caretTimer.interval = TimeSpan(duration: 5_000_000)
        caretTimer.tick.addHandler { [weak self] _, _ in
            guard let self, self.document.editing else { return }
            caretVisible.toggle(); renderEditorAdornments()
        }
        timer.interval = TimeSpan(duration: 10_000_000)
        timer.tick.addHandler { [weak self] _, _ in self?.pollAutosave() }
        try? timer.start()
        refresh()
    }
    func refresh() {
        guard !isClosed else { return }
        refreshMenuChecks()
        let title = self.document.title
        if title != lastWindowTitle { window.title = title; titleText.text = title; lastWindowTitle = title }
        if appliedDark != dark {
            refreshWindowChrome()
            refreshClockStyle()
            root.requestedTheme = dark ? .dark : .light
            root.background = ink(dark ? 0x202020 : 0xF6F7F8)
            let icon = resources.appendingPathComponent(dark ? "AppIconDark.ico" : "AppIcon.ico").path
            if FileManager.default.fileExists(atPath: icon) { try? window.appWindow.setIcon(icon) }
            appliedDark = dark
        }
        fitBandHeight()

        let visibility: WinUI.Visibility = media.hasVideo ? .visible : .collapsed
        if videoView.visibility != visibility { videoView.visibility = visibility }
        previewImage?.visibility = media.hasVideo ? .collapsed : .visible
        refreshScript(); refreshClock(); renderBand(); updateTextEditor()
    }
    func updatePlaybackRendering() {
        guard !isClosed else { return }
        refreshMenuChecks()
        lastRenderUptime = ProcessInfo.processInfo.systemUptime
        timelineClock.reset()
        if media.rate != 0, renderingSubscription == nil {
            renderingSubscription = CompositionTarget.rendering.addHandler { [weak self] _, _ in self?.tick() }
        } else if media.rate == 0 {
            renderingSubscription?.dispose(); renderingSubscription = nil
            if media.hasMedia {
                self.document.frame = self.document.project.mediaStartFrame +
                    Timeline.frame(at: media.position, fps: fps, playing: true)
            }
            playbackFrame = nil; logicalFrame = Double(self.document.frame)
            refreshClock()
            refreshScriptPlayback(); renderBand(reuse: true)
        }
    }
    func tick() {
        guard !isClosed else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        let elapsed = max(0, uptime - lastRenderUptime); lastRenderUptime = uptime
        if media.rate != 0 && !self.document.editing && !dialogShowing {
            if media.hasMedia && media.usesPlaybackClock && !media.waitingForReverseAudio {
                let seconds = max(0, timelineClock.position(sample: media.position, rate: media.rate,
                    advancing: media.isAdvancing, now: uptime))
                playbackFrame = Double(self.document.project.mediaStartFrame) + seconds * Double(fps)
                self.document.frame = self.document.project.mediaStartFrame + Timeline.frame(at: seconds, fps: fps, playing: true)
                logicalFrame = playbackFrame
                if media.rate < 0 {
                    media.synchronizeReverseVideo(Double(self.document.frame - self.document.project.mediaStartFrame) / Double(fps))
                    if seconds <= 0 { media.stop() }
                }
            } else {
                let next = (logicalFrame ?? Double(self.document.frame)) + elapsed * Double(fps) * media.rate
                logicalFrame = max(Double(self.document.project.mediaStartFrame), next)
                playbackFrame = logicalFrame
                let seconds = (logicalFrame! - Double(self.document.project.mediaStartFrame)) / Double(fps)
                self.document.frame = self.document.project.mediaStartFrame + Timeline.frame(at: seconds, fps: fps, playing: true)
                if media.hasMedia {
                    let seconds = Double(self.document.frame - self.document.project.mediaStartFrame) / Double(fps)
                    if media.rate < 0 { media.synchronizeReverseVideo(seconds) }
                    else { media.seek(seconds) }
                }
                if media.rate < 0 && next <= Double(self.document.project.mediaStartFrame) { media.stop() }
            }
            if !videoOnly && (displayedFrame != self.document.frame || displayedFPS != fps) { refreshClock() }
            refreshScriptPlayback(); renderBand(reuse: true)
        } else { renderBand(reuse: true) }
    }
    func pollAutosave() {
        guard !isClosed else { return }
        if media.rate == 0 { refreshTimelineScrollbar() }
        let now = Date()
        if !dialogShowing && !isResizing && now.timeIntervalSince(lastAutosavePoll) >= 1 {
            lastAutosavePoll = now
            do { try self.document.autoSave(at: now) } catch { status.text = error.localizedDescription }
        }
    }
    func seek(_ frame: Int) {
        timelineClock.reset(); bandMotion.invalidate()
        playbackFrame = nil
        self.document.frame = max(self.document.project.mediaStartFrame, frame)
        logicalFrame = Double(self.document.frame)
        media.seek(Double(self.document.frame - self.document.project.mediaStartFrame) / Double(fps))
        refreshClock(); refreshScriptPlayback(); renderBand()
    }
    func showError(_ message: String) async { _ = await dialog("Cappella", content: label(message), primary: "OK") }
    func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { Task { @MainActor in await self.showError(error.localizedDescription) } }
    }

}
