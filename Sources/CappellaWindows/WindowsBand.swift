import Foundation
import WinSDK
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation

struct WindowsBandState: Equatable {
    var revision: UInt64
    var track: Int
    var selection: Foundation.UUID?
    var sign: Foundation.UUID?
    var editing: Bool
    var preferences: ApplicationPreferences
}

struct WindowsRulerState: Equatable {
    var origin: Int
    var center: Int
    var width: Double
    var height: Double
    var scale: Double
    var fps: Int
    var dark: Bool
    var visible: Bool
}

extension WindowsEditor {
    var bandDisplayFrame: Double {
        // The document holds the current whole frame; motion keeps its fraction.
        // Comparing a rounded value here quantizes half of every frame interval.
        if let playbackFrame, playbackFrame >= Double(self.document.frame) - 1e-8,
           playbackFrame < Double(self.document.frame + 1) + 1e-8 { return playbackFrame }
        return Double(self.document.frame)
    }
    func renderBand(reuse: Bool = false) {
        guard !isClosed, !videoOnly else { return }
        let width = bandContainer.actualWidth, height = bandContainer.actualHeight
        guard width > 0, height > 0 else { return }
        let position = bandDisplayFrame
        let state = WindowsBandState(revision: self.document.revision, track: self.document.track,
            selection: self.document.selection, sign: self.document.signSelection,
            editing: self.document.editing, preferences: self.document.preferences)
        let invalid = bandState != state || width != bandCacheWidth || height != bandCacheHeight
        let lane = height / 4, center = width / 2
        if invalid {
            bandState = state; bandCacheWidth = width; bandCacheHeight = height
            // Index geometry once per edit/layout, never measure offscreen text
            // or scan the whole project during steady playback.
            bandIndexedCues = self.document.project.cues.filter { (0..<4).contains($0.track) }
                .sorted { $0.start < $1.start }
                .map { (cue: $0, end: timelineCueEndFrame($0)) }
            bandPrefixEnds.removeAll(keepingCapacity: true)
            var furthest = -Double.infinity
            for entry in bandIndexedCues {
                furthest = max(furthest, entry.end); bandPrefixEnds.append(furthest)
            }
            bandOriginFrame = Int(position)
            band.children.clear(); bandCueViews.removeAll(); bandMarkerViews.removeAll()
            bandBackdrop.children.clear(); bandOverlay.children.clear()
            bandMotion.invalidate(); lastBandPopulation = -.infinity
            let clip = RectangleGeometry()
            clip.rect = WindowsFoundation.Rect(x: 0, y: 0, width: Float(width), height: Float(height))
            bandContainer.clip = clip
            for track in 0..<4 {
                let selected = self.document.track == track
                rectangle(on: bandBackdrop, x: 0, y: Double(track) * lane, width: width, height: lane,
                    color: ink(dark ? (selected ? 0x555555 : 0x303030) : (selected ? 0xFAFAFA : 0xA8A8A8)))
                if self.document.preferences.showGrid {
                    rectangle(on: bandBackdrop, x: 0, y: Double(track) * lane, width: width, height: 0.5,
                        color: ink(dark ? 0x777777 : 0x555555))
                }
            }
            rectangle(on: bandOverlay, x: center - 1, y: 0, width: 2, height: height, color: ink(0xC40000))
        } else if abs((Double(bandOriginFrame) - position) * scale) > 65_536 {
            // Rebase coordinates without rebuilding text; bound floating-point error
            // during long sessions while retaining the same visible objects.
            let nextOrigin = Int(position), delta = Double(bandOriginFrame - nextOrigin) * scale
            for view in Array(bandCueViews.values) + Array(bandMarkerViews.values) {
                if let left = try? Canvas.getLeft(view) { try? Canvas.setLeft(view, left + delta) }
            }
            bandOriginFrame = nextOrigin; bandMotion.invalidate()
        }
        let speed = timelineSpeed
        bandMotion.update(bandMotionLayer, offset: (Double(bandOriginFrame) - position) * scale,
            speed: speed, fallback: bandTranslation)
        updateRuler(width: width, height: height, position: position)
        let now = ProcessInfo.processInfo.systemUptime
        guard invalid || !reuse || now - lastBandPopulation >= 0.1 else { return }
        lastBandPopulation = now
        // Prefetch outside the viewport. Only entering/leaving cues change the tree;
        // nothing already visible is periodically destroyed and measured again.
        let from = position - width * 1.5 / scale, to = position + width * 1.5 / scale
        var low = 0, high = bandIndexedCues.count
        while low < high {
            let middle = low + (high - low) / 2
            if bandPrefixEnds[middle] < from { low = middle + 1 } else { high = middle }
        }
        let first = low
        high = bandIndexedCues.count
        while low < high {
            let middle = low + (high - low) / 2
            if Double(bandIndexedCues[middle].cue.start) <= to { low = middle + 1 } else { high = middle }
        }
        let entries = bandIndexedCues[first..<low].filter { $0.end >= from }
        let cues = entries.map(\.cue)
        let cueIDs = Set(cues.map(\.id))
        for id in Array(bandCueViews.keys) where !cueIDs.contains(id) {
            if let view = bandCueViews.removeValue(forKey: id) { detachBandView(view) }
        }
        for entry in entries where bandCueViews[entry.cue.id] == nil {
            let cue = entry.cue
            let view = makeBandCue(cue, lane: lane)
            place(view, on: band, x: center + Double(cue.start - bandOriginFrame) * scale, y: 0,
                width: max(1, (entry.end - Double(cue.start)) * scale), height: height)
            bandCueViews[cue.id] = view
        }
        var markerIDs = Set<Foundation.UUID>()
        if self.document.preferences.showDetection {
            let groups: [([Marker], Bool)] = [(self.document.project.shots, false), (self.document.project.loops, true)]
            for (markers, isLoop) in groups {
                for marker in markers where Double(marker.frame) >= from && Double(marker.frame) <= to {
                    markerIDs.insert(marker.id)
                    guard bandMarkerViews[marker.id] == nil else { continue }
                    let view = Canvas()
                    rectangle(on: view, x: isLoop ? -2 : -3, y: 0, width: isLoop ? 4 : 6, height: height,
                        color: ink(isLoop ? 0x0069C7 : 0x666666))
                    if isLoop {
                        let badge = Border(); badge.background = ink(0x0069C7)
                        badge.child = label(marker.label, size: 13, color: ink(0xFFFFFF))
                        place(badge, on: view, x: -8, y: height - 21, width: 22, height: 21)
                    }
                    // Shot bars stay behind role labels and phrase content.
                    try? Canvas.setZIndex(view, isLoop ? 1 : -1)
                    place(view, on: band, x: center + Double(marker.frame - bandOriginFrame) * scale, y: 0,
                        width: 1, height: height)
                    bandMarkerViews[marker.id] = view
                }
            }
        }
        for id in Array(bandMarkerViews.keys) where !markerIDs.contains(id) {
            if let view = bandMarkerViews.removeValue(forKey: id) { detachBandView(view) }
        }
    }
    var timelineSpeed: Double {
        guard !self.document.editing, !dialogShowing, media.rate != 0 else { return 0 }
        if media.hasMedia && media.usesPlaybackClock && !media.waitingForReverseAudio && !media.isAdvancing { return 0 }
        return -scale * Double(fps) * media.rate
    }
    func detachBandView(_ view: Canvas) {
        if let index = band.children.index(of: view) { band.children.removeAt(UInt32(index)) }
    }
    func makeBandCue(_ cue: Cue, lane: Double) -> Canvas {
        let view = Canvas(), y = Double(cue.track) * lane
        if self.document.preferences.showDetection {
            let role = self.document.project.roles.first { $0.id == cue.roleID }
            let name = label(role?.name ?? "Sans rôle", size: 10, color: ink(0xFFFFFF))
            let badge = Border(); badge.background = ink(0); badge.child = name
            try? name.measure(uiSize(width: 500, height: 20))
            place(badge, on: view, x: -Double(name.desiredSize.width) - 8, y: y,
                width: Double(name.desiredSize.width) + 6, height: 15)
        }
        do { // Draw the same stretched glyphs during reading and editing.
            let color = readingColor(cue.roleID), font = FontFamily(fontFamily)
            for segment in Timeline.segments(cue, editing: self.document.editing && self.document.selection == cue.id) {
                let textWidth = Double(segment.end - segment.start) * scale
                guard textWidth > 0 else { continue }
                let text = label(segment.text, size: self.document.preferences.fontSize, color: color)
                text.fontFamily = font; text.fontStyle = .italic
                text.useLayoutRounding = false
                text.textDecorations = cue.voice == "off" ? .underline : .none
                try? text.measure(uiSize(width: 100_000, height: lane))
                // Include the space before an intermediate sign in the stretch
                // denominator, so it remains a visible gap before the next run.
                let naturalWidth = measureTimelineText(segment.text), naturalHeight = Double(text.desiredSize.height)
                guard naturalWidth > 0 else { continue }
                let transform = CompositeTransform(); transform.scaleX = segment.naturalWidth ? 1 : textWidth / naturalWidth
                text.renderTransform = transform; text.protectedCursor = bandTextCursor
                place(text, on: view, x: Double(segment.start - cue.start) * scale,
                    y: y + max(0, (lane - naturalHeight) / 2), width: naturalWidth, height: naturalHeight)
            }
        }
        if self.document.preferences.showGrid {
            for sign in cue.visibleAnchors {
                let x = Double(sign.frame - cue.start) * scale
                let color = sign.kind.hasPrefix("in_") ? ink(0x00D800) : sign.kind.hasPrefix("out_") ? ink(0xED1515) : ink(dark ? 0xFFFFFF : 0x111111)
                // Filled vector silhouettes; no font-dependent arrows or bars.
                // One geometry per contour also keeps overlapping contours solid.
                for contour in SyncSignGeometry.outlines(for: sign.kind) {
                    guard let first = contour.first else { continue }
                    let geometry = PathGeometry(), figure = PathFigure()
                    figure.isFilled = true; figure.isClosed = true
                    figure.startPoint = Point(x: Float(first.x * 0.72), y: Float(first.y * 0.72))
                    for point in contour.dropFirst() {
                        let segment = LineSegment()
                        segment.point = Point(x: Float(point.x * 0.72), y: Float(point.y * 0.72))
                        figure.segments.append(segment)
                    }
                    geometry.figures.append(figure)
                    let mark = WinUI.Path(); mark.data = geometry; mark.fill = color
                    mark.isHitTestVisible = false
                    place(mark, on: view, x: x - 7.2, y: y + lane - 20, width: 14.4, height: 18)
                }
                if sign.id == self.document.signSelection {
                    let outline = Border(); outline.borderBrush = ink(0x328BFF)
                    outline.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
                    place(outline, on: view, x: x - 7, y: y + lane - 22, width: 15, height: 22)
                }
            }
        }
        return view
    }
    func updateRuler(width: Double, height: Double, position: Double) {
        // Grid and phrases inherit one compositor translation. Geometry is
        // expressed in the same frame coordinates, with no independent clock.
        let span = max(max(1, fps), Int(width / scale))
        let centerFrame = Int(floor(position / Double(span))) * span
        let state = WindowsRulerState(origin: bandOriginFrame, center: centerFrame,
            width: width, height: height, scale: scale,
            fps: fps, dark: dark, visible: self.document.preferences.showGrid)
        guard state != rulerState else { return }
        rulerState = state; bandRuler.children.clear()
        guard state.visible else { return }
        let lane = height / 4
        let halfFrames = span * 2 + max(1, fps)
        let geometry = PathGeometry()
        // Use stable subdivisions so repeating the one-second pattern is seamless.
        let minimumStep = max(1, Int(4 / scale))
        let step = (1...max(1, fps)).first { $0 >= minimumStep && fps % $0 == 0 } ?? 1
        let first = centerFrame - halfFrames
        for frame in stride(from: first - first % step, through: centerFrame + halfFrames, by: step) {
            let x = Float(width / 2 + Double(frame - bandOriginFrame) * scale)
            for track in 0..<4 {
                let y = Float(Double(track) * lane)
                let figure = PathFigure(); figure.isFilled = false
                figure.startPoint = Point(x: x, y: y)
                let segment = LineSegment(); segment.point = Point(x: x, y: y + (frame % fps == 0 ? 7 : 2))
                figure.segments.append(segment); geometry.figures.append(figure)
            }
        }
        let ruler = WinUI.Path(); ruler.data = geometry
        ruler.stroke = ink(dark ? 0x999999 : 0x666666); ruler.strokeThickness = 0.5
        ruler.isHitTestVisible = false
        place(ruler, on: bandRuler, x: 0, y: 0, width: width, height: height)
    }
    var fontFamily: String {
        if self.document.preferences.fontName == ApplicationPreferences.defaultFontName {
            return "ms-appx:///Resources/PreludeFLF-Italic.ttf#PreludeFLF"
        }
        return ["Apple Chancery", "Snell Roundhand", "Segoe Script"].contains(self.document.preferences.fontName) ? "Monotype Corsiva" : self.document.preferences.fontName
    }
    func readingColor(_ roleID: Foundation.UUID?) -> SolidColorBrush {
        let role = self.document.project.roles.first { $0.id == roleID }
        let palette: [UInt32] = [0x0070C0, 0xD52020, 0x008020, 0x8030A0, 0xBB6500, 0x008090]
        let stored = role?.hexColor.flatMap { UInt32($0.replacingOccurrences(of: "#", with: ""), radix: 16) }
        let value = stored ?? role.map { palette[abs($0.color) % palette.count] } ?? 0
        if !dark { return ink(value) }
        if value == 0 { return ink(0xFFFFFF) }
        return brush(Double((value >> 16) & 255) / 255 * 0.55 + 0.45, Double((value >> 8) & 255) / 255 * 0.55 + 0.45, Double(value & 255) / 255 * 0.55 + 0.45)
    }
    func hit(_ point: Point) -> (Cue?, SyncSign?, Int, Int) {
        let lane = max(1, bandContainer.actualHeight / 4)
        let track = min(3, max(0, Int(Double(point.y) / lane)))
        let target = Int((bandDisplayFrame + (Double(point.x) - bandContainer.actualWidth / 2) / scale).rounded())
        let cue = self.document.project.cues.last { $0.track == track && $0.start <= target && timelineCueEndFrame($0) >= Double(target) }
        let sign = cue?.visibleAnchors.first { abs(Double($0.frame - target) * scale) < 7 && Double(point.y) >= Double(track + 1) * lane - 23 }
        return (cue, sign, track, target)
    }
    func pointerPressed(_ args: PointerRoutedEventArgs?) {
        guard let args, let point = try? args.getCurrentPoint(bandContainer), point.properties.isLeftButtonPressed else { return }
        let (cue, sign, _, _) = hit(point.position)
        dragMoved = false; pointerWasLeft = true
        if cue == nil { timelineLastClick = nil }
        if let cue, let sign { timelineLastClick = nil; dragSign = (cue.id, sign.id, sign.frame, Double(point.position.x)) }
        else if let cue {
            media.stop()
            if !self.document.editing || self.document.selection != cue.id {
                self.document.beginEditing(cue, at: self.document.frame)
                updateTextEditor(focus: true)
            }
            guard let input = textEditor else { return }
            let offset = timelineOffset(cue, atX: Double(point.position.x))
            let now = ProcessInfo.processInfo.systemUptime
            let x = Double(point.position.x), y = Double(point.position.y)
            let dpi = max(1, root.xamlRoot?.rasterizationScale ?? 1)
            let toleranceX = Double(GetSystemMetrics(Int32(SM_CXDOUBLECLK))) / (2 * dpi)
            let toleranceY = Double(GetSystemMetrics(Int32(SM_CYDOUBLECLK))) / (2 * dpi)
            let extending = GetKeyState(Int32(VK_SHIFT)) < 0
            if !extending, let previous = timelineLastClick, previous.cue == cue.id,
               now - previous.time <= Double(GetDoubleClickTime()) / 1000,
               abs(x - previous.x) <= toleranceX, abs(y - previous.y) <= toleranceY {
                timelineLastClick = nil
                let word = DialogueTextSelection.wordRange(in: cue.text, at: offset)
                timelineSelectionOrigin = word.lowerBound
                textSelectionAnchor = (cue.id, word.lowerBound, x)
                let a = utf16Offset(in: cue.text, scalar: word.lowerBound)
                let b = utf16Offset(in: cue.text, scalar: word.upperBound)
                try? input.select(Int32(a), Int32(b - a))
                _ = try? bandContainer.capturePointer(args.pointer)
                focusTimelineInput(input)
                args.handled = true
                return
            }
            timelineLastClick = (cue.id, now, x, y)
            let anchor = extending ? (timelineSelectionOrigin ?? self.document.caret) : offset
            timelineSelectionOrigin = anchor
            textSelectionAnchor = (cue.id, anchor, Double(point.position.x))
            let a = utf16Offset(in: cue.text, scalar: min(anchor, offset))
            let b = utf16Offset(in: cue.text, scalar: max(anchor, offset))
            try? input.select(Int32(a), Int32(b - a))
            _ = try? bandContainer.capturePointer(args.pointer)
            focusTimelineInput(input)
            args.handled = true
        }
    }
    func cancelTimelinePointer() {
        textSelectionAnchor = nil; dragSign = nil; dragMoved = false; pointerWasLeft = false
    }
    func pointerMoved(_ args: PointerRoutedEventArgs?) {
        guard let args, let point = try? args.getCurrentPoint(bandContainer) else { return }
        if let (cueID, anchor, startX) = textSelectionAnchor, point.properties.isLeftButtonPressed,
           let cue = self.document.selectedCue, cue.id == cueID, let input = textEditor {
            guard abs(Double(point.position.x) - startX) > 2 else { return }
            dragMoved = true; timelineLastClick = nil
            let offset = timelineOffset(cue, atX: Double(point.position.x))
            let a = utf16Offset(in: cue.text, scalar: min(anchor, offset))
            let b = utf16Offset(in: cue.text, scalar: max(anchor, offset))
            try? input.select(Int32(a), Int32(b - a)); args.handled = true
            return
        }
        if let (cueID, signID, initialFrame, x) = dragSign, point.properties.isLeftButtonPressed {
            let delta = Double(point.position.x) - x
            if abs(delta) > 3 {
                dragMoved = true; self.document.selection = cueID; self.document.signSelection = signID
                perform { try self.document.mutateCue { Timeline.moveSign(in: &$0, id: signID, to: max(0, initialFrame + Int((delta / scale).rounded()))) } }
            }
        }
    }
    func pointerReleased(_ args: PointerRoutedEventArgs?) {
        let selectedInput = textSelectionAnchor != nil ? textEditor : nil
        defer {
            if textSelectionAnchor != nil { try? bandContainer.releasePointerCaptures() }
            textSelectionAnchor = nil; dragSign = nil; dragMoved = false; pointerWasLeft = false
            if let selectedInput { focusTimelineInput(selectedInput) }
        }
        guard pointerWasLeft, !dragMoved, textSelectionAnchor == nil, let args, let point = try? args.getCurrentPoint(bandContainer), !point.properties.isRightButtonPressed else { return }
        let (cue, _, track, target) = hit(point.position)
        media.stop()
        if let cue {
            self.document.beginEditing(cue, at: target)
            self.document.caret = timelineOffset(cue, atX: Double(point.position.x))
            updateTextEditor(focus: true)
        }
        else { self.document.selectTrack(track); updateTextEditor() }
    }
}
