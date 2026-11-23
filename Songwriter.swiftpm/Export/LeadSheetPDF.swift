import UIKit

/// Renders the chart (lead sheet) to an A4 PDF.
enum LeadSheetPDF {
    static func render(song: Song) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let margin: CGFloat = 48
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        let ink = UIColor(hex: 0x17202E)
        let ink2 = UIColor(hex: 0x4F5B6D)
        let red = UIColor(hex: 0xC2362B)
        let lineColor = UIColor(hex: 0xB8C3D3)
        func font(_ names: [String], _ size: CGFloat, bold: Bool = false) -> UIFont {
            for n in names { if let f = UIFont(name: n, size: size) { return f } }
            return bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        }
        let titleFont = font(["Spectral-MediumItalic"], 26)
        let subFont = font(["Spectral-Italic"], 12)
        let chordFont = font(["BarlowCondensed-Bold"], 15, bold: true)
        let chordSmall = font(["BarlowCondensed-Bold"], 9.5, bold: true)
        let lyricFont = font(["Spectral-Regular"], 11)
        let labelFont = font(["Barlow-SemiBold"], 11, bold: true)
        let nameFont = font(["Spectral-Italic"], 13)

        let lines = ChartLayout.lines(for: song)
        let contentWidth = page.width - margin * 2
        let barWidth = contentWidth / 4.0

        let data = renderer.pdfData { ctx in
            var y: CGFloat = margin
            func newPage() {
                ctx.beginPage()
                y = margin
            }
            newPage()
            (song.title as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: titleFont, .foregroundColor: ink])
            y += 36
            let sub = "Key of \(song.key.displayName)   \u{2022}   \(Int(song.tempo.rounded())) bpm   \u{2022}   \(song.timeSignature.label)"
            (sub as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: subFont, .foregroundColor: ink2])
            y += 28

            for line in lines {
                let hasBars = !line.bars.isEmpty
                var needed: CGFloat = hasBars ? 40 : 18
                if line.showSectionHeader { needed += 26 }
                if !line.lyric.isEmpty && hasBars { needed += 16 }
                if y + needed > page.height - margin { newPage() }

                if line.showSectionHeader {
                    let s = song.sections[line.sectionIndex]
                    let box = CGRect(x: margin, y: y, width: 20, height: 20)
                    let path = UIBezierPath(roundedRect: box, cornerRadius: 3)
                    red.setStroke()
                    path.lineWidth = 1.2
                    path.stroke()
                    let letter = s.letter as NSString
                    let ls = letter.size(withAttributes: [.font: labelFont])
                    letter.draw(at: CGPoint(x: box.midX - ls.width / 2, y: box.midY - ls.height / 2),
                                withAttributes: [.font: labelFont, .foregroundColor: red])
                    (s.name as NSString).draw(at: CGPoint(x: margin + 28, y: y + 1), withAttributes: [.font: nameFont, .foregroundColor: ink])
                    y += 28
                }
                if hasBars {
                    let rowTop = y
                    let rowHeight: CGFloat = 28
                    for (i, bar) in line.bars.enumerated() {
                        let x0 = margin + CGFloat(i) * barWidth
                        // bar lines
                        lineColor.setStroke()
                        let l = UIBezierPath()
                        l.move(to: CGPoint(x: x0, y: rowTop))
                        l.addLine(to: CGPoint(x: x0, y: rowTop + rowHeight))
                        l.lineWidth = 0.8
                        l.stroke()
                        let beatsPerBar = song.beatsPerBar
                        for c in bar.chords {
                            let cx = x0 + 6 + CGFloat(c.beatInBar / beatsPerBar) * (barWidth - 8)
                            let p = c.chord.displayParts
                            let main = (p.root + p.main) as NSString
                            main.draw(at: CGPoint(x: cx, y: rowTop + 6), withAttributes: [.font: chordFont, .foregroundColor: ink])
                            var advance = main.size(withAttributes: [.font: chordFont]).width
                            if !p.ext.isEmpty {
                                (p.ext as NSString).draw(at: CGPoint(x: cx + advance, y: rowTop + 3), withAttributes: [.font: chordSmall, .foregroundColor: ink])
                                advance += (p.ext as NSString).size(withAttributes: [.font: chordSmall]).width
                            }
                            if let b = p.bass {
                                ("/" + b as NSString).draw(at: CGPoint(x: cx + advance, y: rowTop + 8), withAttributes: [.font: chordSmall, .foregroundColor: ink])
                            }
                        }
                    }
                    let endX = margin + CGFloat(line.bars.count) * barWidth
                    let l = UIBezierPath()
                    l.move(to: CGPoint(x: endX, y: rowTop))
                    l.addLine(to: CGPoint(x: endX, y: rowTop + rowHeight))
                    l.lineWidth = 0.8
                    lineColor.setStroke()
                    l.stroke()
                    y += rowHeight + 2
                    if !line.lyric.isEmpty {
                        (line.lyric as NSString).draw(at: CGPoint(x: margin + 4, y: y), withAttributes: [.font: lyricFont, .foregroundColor: ink2])
                        y += 16
                    }
                    y += 8
                } else {
                    (line.lyric as NSString).draw(at: CGPoint(x: margin + 4, y: y), withAttributes: [.font: lyricFont, .foregroundColor: ink2])
                    y += 16
                }
            }
        }
        return data
    }
}
