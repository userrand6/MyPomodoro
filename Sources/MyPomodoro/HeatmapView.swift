import AppKit
import PomodoroCore

/// Lightweight GitHub-style contribution heatmap rendered directly via AppKit/CoreGraphics.
@MainActor
final class HeatmapView: NSView {
    static let weeksCount = 19

    private static let cellSize: CGFloat = 11
    private static let cellSpacing: CGFloat = 2
    private static let labelWidth: CGFloat = 16
    private static let headerHeight: CGFloat = 16
    private static let headerGap: CGFloat = 5

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var grid: [[HeatmapDay?]] = []
    private var toolTipStrings: [String] = []

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let gridWidth = CGFloat(Self.weeksCount) * Self.cellSize + CGFloat(Self.weeksCount - 1) * Self.cellSpacing
        let gridHeight = 7 * Self.cellSize + 6 * Self.cellSpacing
        return NSSize(
            width: Self.labelWidth + gridWidth,
            height: Self.headerHeight + Self.headerGap + gridHeight
        )
    }

    func update(grid newGrid: [[HeatmapDay?]]) {
        guard newGrid != grid else { return }
        grid = newGrid
        rebuildToolTips()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawHeader()
        drawWeekdayLabels()
        drawCells()
    }

    private func drawHeader() {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        ("Last \(Self.weeksCount) weeks" as NSString).draw(at: NSPoint(x: 0, y: 1), withAttributes: titleAttrs)

        let swatchSize: CGFloat = 8
        let swatchGap: CGFloat = 2
        let moreStr = "More" as NSString
        let lessStr = "Less" as NSString
        let legendFont = NSFont.systemFont(ofSize: 9, weight: .regular)
        let legendAttrs: [NSAttributedString.Key: Any] = [
            .font: legendFont,
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        let moreWidth = moreStr.size(withAttributes: legendAttrs).width
        let lessWidth = lessStr.size(withAttributes: legendAttrs).width
        let swatchesWidth = 5 * swatchSize + 4 * swatchGap
        let totalLegendWidth = lessWidth + 4 + swatchesWidth + 4 + moreWidth
        var x = bounds.width - totalLegendWidth

        lessStr.draw(at: NSPoint(x: x, y: 1), withAttributes: legendAttrs)
        x += lessWidth + 4

        let swatchMinutes = [0, 15, 45, 90, 150]
        for mins in swatchMinutes {
            let rect = NSRect(x: x, y: 3, width: swatchSize, height: swatchSize)
            color(forMinutes: mins).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            x += swatchSize + swatchGap
        }

        x += 2
        moreStr.draw(at: NSPoint(x: x, y: 1), withAttributes: legendAttrs)
    }

    private func drawWeekdayLabels() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let topY = Self.headerHeight + Self.headerGap
        let labels: [(row: Int, text: String)] = [(1, "M"), (3, "W"), (5, "F")]

        for item in labels {
            let y = topY + CGFloat(item.row) * (Self.cellSize + Self.cellSpacing)
            (item.text as NSString).draw(at: NSPoint(x: 0, y: y), withAttributes: attrs)
        }
    }

    private func drawCells() {
        let topY = Self.headerHeight + Self.headerGap

        for (weekIdx, column) in grid.enumerated() {
            let x = Self.labelWidth + CGFloat(weekIdx) * (Self.cellSize + Self.cellSpacing)
            for (dayIdx, day) in column.enumerated() {
                guard let day else { continue }
                let y = topY + CGFloat(dayIdx) * (Self.cellSize + Self.cellSpacing)
                let rect = NSRect(x: x, y: y, width: Self.cellSize, height: Self.cellSize)
                color(forMinutes: day.minutes).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            }
        }
    }

    private func rebuildToolTips() {
        removeAllToolTips()
        toolTipStrings.removeAll(keepingCapacity: true)

        let topY = Self.headerHeight + Self.headerGap
        for (weekIdx, column) in grid.enumerated() {
            let x = Self.labelWidth + CGFloat(weekIdx) * (Self.cellSize + Self.cellSpacing)
            for (dayIdx, day) in column.enumerated() {
                guard let day else { continue }
                let y = topY + CGFloat(dayIdx) * (Self.cellSize + Self.cellSpacing)
                let rect = NSRect(x: x, y: y, width: Self.cellSize, height: Self.cellSize)
                let dateText = Self.dateFormatter.string(from: day.date)
                let unit = day.minutes == 1 ? "min" : "min"
                let index = toolTipStrings.count
                toolTipStrings.append("\(dateText): \(day.minutes) \(unit)")
                addToolTip(rect, owner: self, userData: UnsafeMutableRawPointer(bitPattern: index + 1))
            }
        }
    }

    @objc func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        guard let data else { return "" }
        let index = Int(bitPattern: data) - 1
        guard index >= 0, index < toolTipStrings.count else { return "" }
        return toolTipStrings[index]
    }

    private func color(forMinutes minutes: Int) -> NSColor {
        if minutes <= 0 {
            return .quaternaryLabelColor
        }
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            switch minutes {
            case 1..<30:
                return isDark
                    ? NSColor(srgbRed: 0.055, green: 0.267, blue: 0.161, alpha: 1.0)
                    : NSColor(srgbRed: 0.608, green: 0.914, blue: 0.659, alpha: 1.0)
            case 30..<60:
                return isDark
                    ? NSColor(srgbRed: 0.0, green: 0.427, blue: 0.196, alpha: 1.0)
                    : NSColor(srgbRed: 0.251, green: 0.769, blue: 0.388, alpha: 1.0)
            case 60..<120:
                return isDark
                    ? NSColor(srgbRed: 0.149, green: 0.651, blue: 0.255, alpha: 1.0)
                    : NSColor(srgbRed: 0.188, green: 0.631, blue: 0.306, alpha: 1.0)
            default:
                return isDark
                    ? NSColor(srgbRed: 0.224, green: 0.827, blue: 0.325, alpha: 1.0)
                    : NSColor(srgbRed: 0.129, green: 0.431, blue: 0.224, alpha: 1.0)
            }
        }
    }
}
