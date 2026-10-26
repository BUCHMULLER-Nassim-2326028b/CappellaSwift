import Foundation
import CappellaCore
import WinUI
import UWP
import WindowsFoundation

@MainActor
final class WindowsReadingSurface {
    let root = Grid(), videoHost = Grid()
    private let canvas = Canvas(), band = Canvas(), sidebar = Canvas()
    private var views: [String: FrameworkElement] = [:]
    private var contents: [String: ReadingNode.Content] = [:]
    private var transforms: [String: CompositeTransform] = [:]
    private var layout: ReadingLayout?
    private var revision = UInt64.max
    private var speed = 0.0
    private var naturalWidths: [String: Double] = [:]
    private var lastWidth = 0.0, lastHeight = 0.0
    init() {
        root.background = ink(0); canvas.width = 1920; canvas.height = 1080
        canvas.horizontalAlignment = .left; canvas.verticalAlignment = .top
        root.children.append(canvas)
        place(videoHost, on: canvas, x: 0, y: 0, width: 1440, height: 810)
        for (layer, bounds) in [(band, ReadingLayout.band), (sidebar, ReadingLayout.sidebar)] {
            layer.width = 1920; layer.height = 1080; layer.isHitTestVisible = false
            let clip = RectangleGeometry()
            clip.rect = Rect(x: Float(bounds.x), y: Float(bounds.y), width: Float(bounds.width), height: Float(bounds.height))
            layer.clip = clip; canvas.children.append(layer)
        }
        root.sizeChanged.addHandler { [weak self] _, _ in self?.resize() }
    }
    private func resize() {
        let scale = min(root.actualWidth / 1920, root.actualHeight / 1080)
        guard scale > 0, root.actualWidth != lastWidth || root.actualHeight != lastHeight else { return }
        lastWidth = root.actualWidth; lastHeight = root.actualHeight
        let transform = CompositeTransform(); transform.scaleX = scale; transform.scaleY = scale
        transform.translateX = (root.actualWidth - 1920 * scale) / 2
        transform.translateY = (root.actualHeight - 1080 * scale) / 2
        canvas.renderTransform = transform
        let clip = RectangleGeometry(); clip.rect = Rect(x: 0, y: 0, width: Float(root.actualWidth), height: Float(root.actualHeight))
        root.clip = clip
    }
    func render(project: Project, revision: UInt64, pixelsPerSecond: Double, frame: Double) {
        if layout == nil || self.revision != revision || speed != pixelsPerSecond {
            layout = ReadingLayout(project: project, pixelsPerSecond: pixelsPerSecond)
            self.revision = revision; speed = pixelsPerSecond
        }
        guard let layout else { return }
        let nodes = layout.nodes(at: frame), ids = Set(nodes.map(\.id))
        for id in Array(views.keys) where !ids.contains(id) {
            if let view = views.removeValue(forKey: id) {
                for layer in [band, sidebar] {
                    if let index = layer.children.index(of: view) { layer.children.removeAt(UInt32(index)) }
                }
            }
            contents[id] = nil; transforms[id] = nil; naturalWidths[id] = nil
        }
        for node in nodes {
            let layer = node.layer == .band ? band : sidebar
            switch node.content {
            case .rectangle(let rect, let color):
                let shape: Rectangle
                if let old = views[node.id] as? Rectangle { shape = old }
                else { shape = Rectangle(); place(shape, on: layer, x: rect.x, y: rect.y); views[node.id] = shape }
                if contents[node.id] != node.content {
                    shape.fill = ink(color); shape.width = rect.width; shape.height = rect.height
                    try? Canvas.setLeft(shape, rect.x); try? Canvas.setTop(shape, rect.y)
                }
            case .text(let value, let x, let y, let size, let width, let color, let underline):
                let text: TextBlock
                if let old = views[node.id] as? TextBlock { text = old }
                else {
                    text = label("", size: size); text.fontFamily = FontFamily(ReadingLayout.font)
                    text.useLayoutRounding = false
                    let transform = CompositeTransform(); text.renderTransform = transform; transforms[node.id] = transform
                    place(text, on: layer, x: x, y: y); views[node.id] = text
                }
                // Moving a run does not re-measure it or recreate its XAML view.
                if text.text != value || text.fontSize != size {
                    text.fontSize = size
                    // Explicit dimensions from the previous run constrain Measure,
                    // including the sentinel, and otherwise collapse changing labels.
                    text.width = .nan; text.height = .nan
                    text.text = value + "\u{200B}|"; try? text.measure(uiSize(width: 100000, height: 1000))
                    let full = Double(text.desiredSize.width)
                    text.text = "\u{200B}|"; try? text.measure(uiSize(width: 100000, height: 1000))
                    let natural = max(0.1, full - Double(text.desiredSize.width))
                    text.text = value; text.width = natural; text.height = size * 1.5
                    naturalWidths[node.id] = natural
                }
                let natural = naturalWidths[node.id] ?? 1
                let stretch = width.map { $0 / natural } ?? 1
                if transforms[node.id]?.scaleX != stretch { transforms[node.id]?.scaleX = stretch }
                var styleChanged = true
                if let previous = contents[node.id], case .text(_, _, _, _, _, let previousColor, let previousUnderline) = previous {
                    styleChanged = previousColor != color || previousUnderline != underline
                }
                if styleChanged {
                    text.foreground = ink(color); text.textDecorations = underline ? .underline : .none
                }
                try? Canvas.setLeft(text, x); try? Canvas.setTop(text, y)
            }
            if let view = views[node.id] {
                let z: Int32 = node.id == "band" || node.id == "sidebar" ? -100 : node.id == "playhead" ? 100 : node.id.hasPrefix("shot:") || node.id.hasPrefix("loop:") ? 0 : 10
                try? Canvas.setZIndex(view, z)
            }
            contents[node.id] = node.content
        }
        resize()
    }
}

extension WindowsEditor {
    func installReadingSurface(videoPanel: Grid) {
        let surface = readingSurface
        surface.root.visibility = .collapsed
        try? Grid.setRow(surface.root, 1); try? Grid.setRowSpan(surface.root, 4)
        root.children.append(surface.root)
        applyReadingLayout = { [weak self] enabled in
            guard let self else { return }
            if enabled {
                if let index = videoPanel.children.index(of: videoView) { videoPanel.children.removeAt(UInt32(index)) }
                surface.videoHost.children.append(videoView)
            } else {
                surface.videoHost.children.clear(); videoPanel.children.append(videoView)
            }
            surface.root.visibility = enabled ? .visible : .collapsed
        }
    }
    func toggleReadingMode() {
        if isResizing { endResize() }
        self.document.finishEditing(); updateTextEditor()
        if videoOnly { videoOnly = false; applyVideoOnlyLayout?(false) }
        readingMode.toggle(); bandMotion.stop()
        applyReadingLayout?(readingMode)
        refresh()
    }
    func renderReading() {
        guard readingMode, !isClosed else { return }
        readingSurface.render(project: self.document.project, revision: self.document.revision,
            pixelsPerSecond: self.document.preferences.pixelsPerSecond, frame: bandDisplayFrame)
    }
}
