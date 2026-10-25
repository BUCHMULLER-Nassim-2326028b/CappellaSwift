import Foundation
import WinUI
import WinAppSDK
import UWP
import WinSDK
import WindowsFoundation

struct WindowsResizeRegion {
    let element: Border
    let vertical: Bool
    let position: () -> Double
    let change: (Double) -> Void
    let finish: () -> Void
}

extension WindowsEditor {
    func beginResize(_ region: WindowsResizeRegion) {
        guard !isClosed, !dialogShowing, !isResizing else { return }
        var cursor = POINT()
        guard GetCursorPos(&cursor) else { return }
        resizeRegion = region
        resizeOrigin = region.vertical ? Double(cursor.x) : Double(cursor.y)
        resizeValue = region.position()
        resizeDPI = max(1, root.xamlRoot?.rasterizationScale ?? 1)
        resizeCoordinate = resizeOrigin
        isResizing = true
        // XAML can consume pointer movement, or take capture away from a native
        // HWND. Poll the cursor during this drag independently of either path.
        try? resizeTimer.start()
    }
    func pollResize() {
        guard isResizing, !isClosed else { return }
        updateResize()
        if GetAsyncKeyState(Int32(VK_LBUTTON)) >= 0 { endResize() }
    }
    func updateResize() {
        guard let region = resizeRegion else { return }
        var cursor = POINT()
        guard GetCursorPos(&cursor) else { return }
        let coordinate = region.vertical ? Double(cursor.x) : Double(cursor.y)
        guard coordinate != resizeCoordinate else { return }
        resizeCoordinate = coordinate
        region.change(resizeValue + (coordinate - resizeOrigin) / resizeDPI)
    }
    func endResize() {
        guard let region = resizeRegion else { return }
        resizeRegion = nil; isResizing = false; resizeCoordinate = nil
        try? resizeTimer.stop()
        region.finish()
    }
    func resizeRegionAtCursor() -> WindowsResizeRegion? {
        guard let hwnd = GetActiveWindow() else { return nil }
        var point = POINT()
        guard GetCursorPos(&point), ScreenToClient(hwnd, &point) else { return nil }
        let dpi = max(1, root.xamlRoot?.rasterizationScale ?? 1)
        guard let transform = try? root.transformToVisual(windowChrome),
              let origin = try? transform.transformPoint(Point()) else { return nil }
        let x = Double(point.x) / dpi - Double(origin.x)
        let y = Double(point.y) / dpi - Double(origin.y)
        for region in resizeRegions {
            guard let transform = try? region.element.transformToVisual(root),
                  let p = try? transform.transformPoint(Point()) else { continue }
            let padding = 3.0
            if x >= Double(p.x) - padding && x <= Double(p.x) + region.element.actualWidth + padding &&
               y >= Double(p.y) - padding && y <= Double(p.y) + region.element.actualHeight + padding {
                return region
            }
        }
        return nil
    }
    func handleDesktopMessage(_ message: MSG) -> Bool {
        guard !isClosed else { return false }
        switch message.message {
        case UINT(WM_LBUTTONDOWN):
            if let region = resizeRegionAtCursor(), !dialogShowing {
                beginResize(region); return true
            }
        case UINT(WM_MOUSEMOVE), UINT(WM_POINTERUPDATE):
            if isResizing { updateResize(); return true }
        case UINT(WM_LBUTTONUP), UINT(WM_POINTERUP):
            if isResizing { updateResize(); endResize(); return true }
        case UINT(WM_CANCELMODE):
            endResize()
        case UINT(WM_KEYUP), UINT(WM_SYSKEYUP):
            if handledDesktopKeys.remove(UInt(message.wParam)) != nil { return true }
            if !dialogShowing, !timelineTextHasFocus, message.wParam == WPARAM(VK_MENU) { return true }
        case UINT(WM_KEYDOWN), UINT(WM_SYSKEYDOWN):
            guard !dialogShowing else { return false }
            let key = Int(message.wParam)
            let ctrl = GetKeyState(Int32(VK_CONTROL)) < 0
            let alt = GetKeyState(Int32(VK_MENU)) < 0
            let shift = GetKeyState(Int32(VK_SHIFT)) < 0
            if alt && !ctrl && key == Int(VK_F4) { return false }
            if key == Int(VK_MENU), !timelineTextHasFocus { return true }
            let repeated = (message.lParam & (1 << 30)) != 0
            if handleShortcut(key: key, ctrl: ctrl, alt: alt, shift: shift, isRepeat: repeated) {
                handledDesktopKeys.insert(UInt(message.wParam)); dismissMenus(); return true
            }
            if !timelineTextHasFocus && (message.message == UINT(WM_SYSKEYDOWN) || [9, 13, 32, 37, 38, 39, 40, 121].contains(key)) {
                handledDesktopKeys.insert(UInt(message.wParam)); return true
            }
        case UINT(WM_SYSCHAR):
            // Menus are opened by mouse. Alt+letter must not activate one while
            // an editor shortcut or transport command is being used.
            if !dialogShowing && !timelineTextHasFocus { return true }
        default: break
        }
        return false
    }
    var timelineTextHasFocus: Bool {
        guard self.document.editing, let input = textEditor else { return false }
        return input.focusState != .unfocused
    }
    func dismissMenus() {
        guard let xamlRoot = root.xamlRoot,
              let popups = try? VisualTreeHelper.getOpenPopupsForXamlRoot(xamlRoot) else { return }
        for index in 0..<Int(popups.size) {
            popups.getAt(UInt32(index))?.isOpen = false
        }
    }
    func shutdown() {
        guard !isClosed else { return }
        isClosed = true
        endResize()
        resizeRegions.removeAll()
        self.document.changed = nil; media.failed = nil; media.playbackChanged = nil
        try? activeDialog?.hide(); activeDialog = nil
        try? timer.stop(); try? caretTimer.stop()
        renderingSubscription?.dispose(); renderingSubscription = nil
        bandMotion.stop()
        media.stop()
        try? projectionVideo?.setMediaPlayer(nil)
        try? projection?.close(); projection = nil; projectionVideo = nil
        try? videoView.setMediaPlayer(nil)
        media.dispose()
        let callback = onClosed; onClosed = nil; callback?()
    }
}