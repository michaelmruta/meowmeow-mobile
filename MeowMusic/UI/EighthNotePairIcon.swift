import SwiftUI

/// Compact missing-artwork glyph used in song rows, where the subtler
/// full-size watermark would not remain legible.
struct EighthNotePairIcon: View {
    var color: Color = Theme.orange

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let headW = w * 0.24
            let headH = h * 0.17
            let stemW = w * 0.05
            let leftHead = CGPoint(x: w * 0.32, y: h * 0.80)
            let rightHead = CGPoint(x: w * 0.68, y: h * 0.80)
            let stemTopY = h * 0.16

            Path { path in
                path.addEllipse(in: CGRect(x: leftHead.x - headW / 2, y: leftHead.y - headH / 2, width: headW, height: headH))
                path.addEllipse(in: CGRect(x: rightHead.x - headW / 2, y: rightHead.y - headH / 2, width: headW, height: headH))

                let leftStemX = leftHead.x + headW / 2 - stemW
                let rightStemX = rightHead.x + headW / 2 - stemW
                path.addRect(CGRect(x: leftStemX, y: stemTopY, width: stemW, height: leftHead.y - stemTopY))
                path.addRect(CGRect(x: rightStemX, y: stemTopY, width: stemW, height: rightHead.y - stemTopY))
                path.addRect(CGRect(
                    x: leftStemX,
                    y: stemTopY,
                    width: (rightStemX + stemW) - leftStemX,
                    height: h * 0.075
                ))
            }
            .fill(color)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
