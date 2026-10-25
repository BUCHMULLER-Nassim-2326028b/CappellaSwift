import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation

extension WindowsEditor {
    func buildLayout() {
        let menuRow = RowDefinition(); menuRow.height = GridLength(value: 0, gridUnitType: .auto)
        let mainRow = RowDefinition(); mainRow.height = GridLength(value: 1, gridUnitType: .star)
        let bandRow = RowDefinition(); bandRow.height = GridLength(value: max(120, self.document.preferences.bandHeight), gridUnitType: .pixel)
        let dividerRow = RowDefinition(); dividerRow.height = GridLength(value: 6, gridUnitType: .pixel)
        let scrollRow = RowDefinition(); scrollRow.height = GridLength(value: 16, gridUnitType: .pixel)
        root.rowDefinitions.append(menuRow); root.rowDefinitions.append(mainRow); root.rowDefinitions.append(dividerRow)
        root.rowDefinitions.append(scrollRow); root.rowDefinitions.append(bandRow)
        installTimelineScrollbar()
        try? Grid.setRow(timelineScrollbar, 3); root.children.append(timelineScrollbar)
        let menus = makeMenu(); try? Grid.setRow(menus, 0); root.children.append(menus)
        let main = Grid()
        let storedFraction = WindowsSettings.number(forKey: "layout.windows.leftFraction")
        let initialFraction = storedFraction.isFinite && storedFraction > 0 ? min(0.85, max(0.15, storedFraction)) : 0.445
        let leftColumn = ColumnDefinition(); leftColumn.width = GridLength(value: initialFraction, gridUnitType: .star)
        let dividerColumn = ColumnDefinition(); dividerColumn.width = GridLength(value: 6, gridUnitType: .pixel)
        let rightColumn = ColumnDefinition(); rightColumn.width = GridLength(value: 1 - initialFraction, gridUnitType: .star)
        main.columnDefinitions.append(leftColumn); main.columnDefinitions.append(dividerColumn); main.columnDefinitions.append(rightColumn)
        // Retain these Swift projections in the drag callbacks. XAML retaining
        // the native Grid does not retain its original Swift wrapper.
        let verticalDivider = makeResizeHandle(vertical: true, position: { leftColumn.actualWidth }, change: { [main] value in
            let available = max(1, main.actualWidth - 6), minimum = min(240, available * 0.4)
            let fraction = min(available - minimum, max(minimum, value)) / available
            leftColumn.width = GridLength(value: fraction, gridUnitType: .star)
            rightColumn.width = GridLength(value: 1 - fraction, gridUnitType: .star)
        }, finish: { [main, weak self] in
            self?.perform {
                try WindowsSettings.merge(["layout.windows.leftFraction": leftColumn.actualWidth / max(1, main.actualWidth - 6)])
            }
        })
        try? Grid.setColumn(verticalDivider, 1); main.children.append(verticalDivider)
        let left = Grid()
        let scriptRow = RowDefinition(); scriptRow.height = GridLength(value: 1, gridUnitType: .star)
        let savedClockHeight = WindowsSettings.number(forKey: "layout.windows.clockHeight")
        let clockRow = RowDefinition(); clockRow.height = GridLength(value: savedClockHeight.isFinite && savedClockHeight >= 76 ? savedClockHeight : 92, gridUnitType: .pixel)
        let clockDividerRow = RowDefinition(); clockDividerRow.height = GridLength(value: 6, gridUnitType: .pixel)
        left.rowDefinitions.append(scriptRow); left.rowDefinitions.append(clockDividerRow); left.rowDefinitions.append(clockRow)
        let clockDivider = makeResizeHandle(vertical: false, position: { -clockRow.actualHeight }, change: { [left] value in
            clockRow.height = GridLength(value: min(max(76, left.actualHeight - 100), max(76, -value)), gridUnitType: .pixel)
        }, finish: { [weak self] in
            self?.perform { try WindowsSettings.merge(["layout.windows.clockHeight": clockRow.actualHeight]) }
        })
        try? Grid.setRow(clockDivider, 1); left.children.append(clockDivider)
        main.sizeChanged.addHandler { [weak left] _, _ in
            guard let left, left.actualHeight > 0 else { return }
            let maximum = max(76, left.actualHeight - 100)
            if clockRow.actualHeight > maximum { clockRow.height = GridLength(value: maximum, gridUnitType: .pixel) }
        }
        let scroll = scriptScroll; scroll.content = script
        script.spacing = 15; script.padding = Thickness(left: 8, top: 16, right: 8, bottom: 16)
        left.children.append(scroll)
        let clock = makeClockPanel()

        try? Grid.setRow(clock, 2); left.children.append(clock)
        main.children.append(left)
        let videoPanel = Grid()
        let mire = Image()
        let path = resources.appendingPathComponent("Mire.jpg")
        if FileManager.default.fileExists(atPath: path.path) { mire.source = BitmapImage(Uri(path.absoluteString)) }
        mire.stretch = .uniformToFill; videoPanel.children.append(mire); previewImage = mire
        videoView.areTransportControlsEnabled = false
        videoView.stretch = .uniform
        videoPanel.background = ink(0)
        try? videoView.setMediaPlayer(media.video)
        videoPanel.children.append(videoView)
        try? Grid.setColumn(videoPanel, 2); main.children.append(videoPanel)
        try? Grid.setRow(main, 1); root.children.append(main)
        bandMotionLayer.renderTransform = bandTranslation
        band.useLayoutRounding = false
        bandRuler.isHitTestVisible = false
        bandContainer.children.append(bandBackdrop)
        bandMotionLayer.useLayoutRounding = false
        bandMotionLayer.children.append(bandRuler)
        bandMotionLayer.children.append(band)
        bandContainer.children.append(bandMotionLayer)
        bandOverlay.isHitTestVisible = false
        bandContainer.children.append(bandOverlay)
        bandContainer.children.append(editorLayer)
        try? Grid.setRow(bandContainer, 4); root.children.append(bandContainer)
        let bandDivider = makeResizeHandle(vertical: false, position: { -bandRow.actualHeight }, change: { [weak self] value in
            guard let self else { return }
            let height = min(max(120, root.actualHeight - 190), max(120, -value))
            self.document.preferences.bandHeight = height; appliedBandHeight = height
            bandRow.height = GridLength(value: height, gridUnitType: .pixel)
        }, finish: { [weak self] in self?.savePreferences() })
        try? Grid.setRow(bandDivider, 2); root.children.append(bandDivider)

        var savedLeft = leftColumn.width, savedDivider = dividerColumn.width, savedRight = rightColumn.width
        let hiddenRows = [dividerRow, scrollRow, bandRow]
        var savedHeights = hiddenRows.map { $0.height }
        applyVideoOnlyLayout = { [weak self] enabled in
            guard let self else { return }
            if enabled {
                savedLeft = leftColumn.width; savedDivider = dividerColumn.width; savedRight = rightColumn.width
                savedHeights = hiddenRows.map { $0.height }
                leftColumn.width = GridLength(value: 0, gridUnitType: .pixel)
                dividerColumn.width = GridLength(value: 0, gridUnitType: .pixel)
                rightColumn.width = GridLength(value: 1, gridUnitType: .star)
                for row in hiddenRows { row.height = GridLength(value: 0, gridUnitType: .pixel) }
            } else {
                leftColumn.width = savedLeft; dividerColumn.width = savedDivider; rightColumn.width = savedRight
                for (row, height) in zip(hiddenRows, savedHeights) { row.height = height }
            }
            let visibility: WinUI.Visibility = enabled ? .collapsed : .visible
            left.visibility = visibility; verticalDivider.visibility = visibility
            bandDivider.visibility = visibility; timelineScrollbar.visibility = visibility
            bandContainer.visibility = visibility
            if !enabled { appliedBandHeight = 0; fitBandHeight() }
        }
    }
    func installWindowChrome() {
        let captionRow = RowDefinition(); captionRow.height = GridLength(value: 32, gridUnitType: .pixel)
        let contentRow = RowDefinition(); contentRow.height = GridLength(value: 1, gridUnitType: .star)
        windowChrome.rowDefinitions.append(captionRow); windowChrome.rowDefinitions.append(contentRow)
        customTitleBar.height = 32
        let iconColumn = ColumnDefinition(); iconColumn.width = GridLength(value: 40, gridUnitType: .pixel)
        let textColumn = ColumnDefinition(); textColumn.width = GridLength(value: 1, gridUnitType: .star)
        customTitleBar.columnDefinitions.append(iconColumn); customTitleBar.columnDefinitions.append(textColumn)
        titleLogo.width = 24; titleLogo.height = 24; titleLogo.stretch = .uniform
        titleText.verticalAlignment = .center; titleText.textTrimming = .characterEllipsis
        try? Grid.setColumn(titleText, 1)
        customTitleBar.children.append(titleLogo); customTitleBar.children.append(titleText)
        windowChrome.children.append(customTitleBar)
        try? Grid.setRow(root, 1); windowChrome.children.append(root)
        window.content = windowChrome
        window.extendsContentIntoTitleBar = true
        try? window.setTitleBar(customTitleBar)
        windowChrome.sizeChanged.addHandler { [weak self] _, _ in self?.updateCaptionInsets() }
        windowChrome.loaded.addHandler { [weak self] _, _ in self?.updateCaptionInsets() }
        updateCaptionInsets()
    }
    func updateCaptionInsets() {
        let dpi = max(1, root.xamlRoot?.rasterizationScale ?? 1)
        let caption = window.appWindow.titleBar!
        customTitleBar.padding = Thickness(left: Double(caption.leftInset) / dpi, top: 0,
            right: max(138, Double(caption.rightInset) / dpi), bottom: 0)
    }
    func refreshWindowChrome() {
        func color(_ value: UInt32) -> UWP.Color {
            UWP.Color(a: 255, r: UInt8((value >> 16) & 255), g: UInt8((value >> 8) & 255), b: UInt8(value & 255))
        }
        windowChrome.requestedTheme = dark ? .dark : .light
        windowChrome.background = ink(dark ? 0x202020 : 0xF6F7F8)
        customTitleBar.background = ink(dark ? 0x202020 : 0xF6F7F8)
        titleText.foreground = ink(dark ? 0xF0F0F0 : 0x202020)
        let caption = window.appWindow.titleBar!
        let background = color(dark ? 0x202020 : 0xF6F7F8)
        let foreground = color(dark ? 0xF0F0F0 : 0x202020)
        caption.backgroundColor = background; caption.inactiveBackgroundColor = background
        caption.foregroundColor = foreground; caption.inactiveForegroundColor = color(dark ? 0x999999 : 0x777777)
        caption.buttonBackgroundColor = background; caption.buttonInactiveBackgroundColor = background
        caption.buttonForegroundColor = foreground; caption.buttonInactiveForegroundColor = caption.inactiveForegroundColor
        caption.buttonHoverBackgroundColor = color(dark ? 0x383838 : 0xE5E5E5)
        caption.buttonHoverForegroundColor = foreground
        caption.buttonPressedBackgroundColor = color(dark ? 0x484848 : 0xD8D8D8)
        caption.buttonPressedForegroundColor = foreground
        let logo = resources.appendingPathComponent(dark ? "CappellaLogo_dark.png" : "CappellaLogo.png")
        if FileManager.default.fileExists(atPath: logo.path) { titleLogo.source = BitmapImage(Uri(logo.absoluteString)) }
    }
    func fitBandHeight() {
        guard !videoOnly, root.actualHeight > 0, let row = root.rowDefinitions.getAt(4) else { return }
        let height = min(max(120, root.actualHeight - 190), max(120, self.document.preferences.bandHeight))
        if height != appliedBandHeight {
            row.height = GridLength(value: height, gridUnitType: .pixel)
            appliedBandHeight = height
        }
    }
    func makeResizeHandle(vertical: Bool, position: @escaping () -> Double,
                          change: @escaping (Double) -> Void, finish: @escaping () -> Void) -> Border {
        let handle = Border()
        handle.background = brush(0.5, 0.5, 0.5, alpha: 0.35)
        handle.protectedCursor = try? InputSystemCursor.create(vertical ? .sizeWestEast : .sizeNorthSouth)
        let region = WindowsResizeRegion(element: handle, vertical: vertical, position: position, change: change, finish: finish)
        let regionIndex = resizeRegions.count
        resizeRegions.append(region)
        // Also support WinUI pointer input when Windows delivers pointer events
        // instead of legacy mouse messages. The drag timer follows the cursor.
        handle.pointerPressed.addHandler { [weak self] _, args in
            guard let self, let args, let point = try? args.getCurrentPoint(root),
                  point.properties.isLeftButtonPressed else { return }
            guard resizeRegions.indices.contains(regionIndex) else { return }
            beginResize(resizeRegions[regionIndex]); args.handled = true
        }
        return handle
    }
}