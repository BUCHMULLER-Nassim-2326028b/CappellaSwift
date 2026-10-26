import SwiftUI
import AVFoundation
import CoreText
import CappellaCore

/// The same Core Text renderer paints the preview and the exported pixel buffer.
enum ReadingPainter {
    static func color(_ rgb: UInt32) -> CGColor {
        CGColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
    static func rect(_ value: ReadingRect) -> CGRect {
        CGRect(x: value.x, y: value.y, width: value.width, height: value.height)
    }
    static func draw(_ nodes: [ReadingNode], in context: CGContext) {
        for node in nodes {
            context.saveGState()
            context.clip(to: rect(node.layer == .band ? ReadingLayout.band : ReadingLayout.sidebar))
            switch node.content {
            case .rectangle(let bounds, let rgb):
                context.setFillColor(color(rgb)); context.fill(rect(bounds))
            case .text(let value, let x, let y, let size, let width, let rgb, let underline):
                let font = CTFontCreateWithName(ReadingLayout.font as CFString, size, nil)
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(rgb)
                ]))
                let natural = CTLineGetTypographicBounds(line, nil, nil, nil)
                if natural > 0 {
                    context.translateBy(x: x, y: y + CTFontGetAscent(font))
                    context.scaleBy(x: width.map { $0 / natural } ?? 1, y: -1)
                    context.textMatrix = .identity; context.textPosition = .zero
                    CTLineDraw(line, context)
                    if underline {
                        context.setStrokeColor(color(rgb)); context.setLineWidth(1.5)
                        context.move(to: CGPoint(x: 0, y: -4)); context.addLine(to: CGPoint(x: natural, y: -4)); context.strokePath()
                    }
                }
            }
            context.restoreGState()
        }
    }
}

struct ReadingView: View {
    let layout: ReadingLayout
    let frame: Double
    let player: AVPlayer
    var videoOffset = 0.0
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / ReadingLayout.width, geometry.size.height / ReadingLayout.height)
            ZStack(alignment: .topLeading) {
                NativeVideoView(player: player, timeOffset: videoOffset).frame(width: 1440, height: 810)
                Canvas { context, _ in
                    context.withCGContext { ReadingPainter.draw(layout.nodes(at: frame), in: $0) }
                }.frame(width: 1920, height: 1080).allowsHitTesting(false)
            }
            .frame(width: 1920, height: 1080, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: (geometry.size.width - 1920 * scale) / 2, y: (geometry.size.height - 1080 * scale) / 2)
        }.background(Color.black).clipped()
    }
}
