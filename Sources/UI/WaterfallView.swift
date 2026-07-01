import SwiftUI

/// Displays a pre-rendered waterfall UIImage. All spectrum processing happens
/// off-main-thread in SpectrumProcessor; this view only shows the result.
struct WaterfallView: View {
    let waterfallImage: UIImage?
    let rxFrequency: Int
    var iqSampleRateHz: Int = 78125
    var onTapFrequency: ((Int) -> Void)? = nil

    private var iqSampleRate: Float { Float(iqSampleRateHz) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width; let h = geo.size.height
            ZStack(alignment: .topLeading) {
                if let img = waterfallImage {
                    Image(uiImage: img).resizable().frame(width: w, height: h)
                } else {
                    Color.black
                }
                ForEach(freqLabels(forWidth: w), id: \.hz) { mark in
                    Text(mark.label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .background(Color.black.opacity(0.5))
                        .position(x: mark.xPos, y: h - 8)
                }
            }
            .background(Color.black)
            .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                let fOff = (Float(v.location.x / w) - 0.5) * iqSampleRate / 2.0
                onTapFrequency?(rxFrequency + Int(fOff))
            })
        }
    }

    private struct FreqMark { let label: String; let hz: Int; let xPos: CGFloat }

    private func freqLabels(forWidth w: CGFloat) -> [FreqMark] {
        let halfSpan = iqSampleRate / 2.0
        let span = halfSpan * 2
        let rawStep: Float
        if      span <=  50_000 { rawStep =  5_000 }
        else if span <= 100_000 { rawStep = 10_000 }
        else if span <= 200_000 { rawStep = 25_000 }
        else                    { rawStep = 50_000 }

        var marks: [FreqMark] = []
        var pos: Float = 0
        while pos <= halfSpan + 1 {
            marks.append(makeMark(offset: Int(pos), halfSpan: halfSpan, w: w))
            pos = (pos == 0) ? rawStep : pos + rawStep
        }
        var neg: Float = -rawStep
        while neg >= -halfSpan - 1 {
            marks.append(makeMark(offset: Int(neg), halfSpan: halfSpan, w: w))
            neg -= rawStep
        }
        marks.sort { $0.xPos < $1.xPos }
        return marks
    }

    private func makeMark(offset: Int, halfSpan: Float, w: CGFloat) -> FreqMark {
        let label: String
        if offset == 0 {
            label = String(format: "%.3f", Float(rxFrequency) / 1_000_000)
        } else if abs(offset) >= 1_000 {
            let sign = offset > 0 ? "+" : ""
            label = "\(sign)\(offset / 1_000)k"
        } else {
            let sign = offset > 0 ? "+" : ""
            label = "\(sign)\(offset)"
        }
        let xPos = CGFloat((Float(offset) + halfSpan) / (halfSpan * 2)) * w
        return FreqMark(label: label, hz: rxFrequency + offset, xPos: xPos)
    }
}
