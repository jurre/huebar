import SwiftUI

struct ColorWheelView: View {
    @Binding var xy: CIEXYColor
    let onChanged: (CIEXYColor) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            let thumbSize: CGFloat = 26

            ZStack {
                Canvas { context, canvasSize in
                    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    let r = min(canvasSize.width, canvasSize.height) / 2

                    let ringCount = max(Int(r / 2), 20)
                    let segmentCount = 72

                    for ring in 0..<ringCount {
                        let saturation = Double(ring) / Double(ringCount - 1)
                        let innerR = CGFloat(ring) / CGFloat(ringCount) * r
                        let outerR = CGFloat(ring + 1) / CGFloat(ringCount) * r

                        for seg in 0..<segmentCount {
                            let hue = Double(seg) / Double(segmentCount)
                            let startAngle = Angle.degrees(hue * 360 - 90)
                            let endAngle = Angle.degrees((hue + 1.0 / Double(segmentCount)) * 360 - 90)

                            var path = Path()
                            path.addArc(center: center, radius: outerR, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                            path.addArc(center: center, radius: innerR, startAngle: endAngle, endAngle: startAngle, clockwise: true)
                            path.closeSubpath()

                            context.fill(path, with: .color(Color(hue: hue, saturation: saturation, brightness: 1.0)))
                        }
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())

                Circle()
                    .fill(thumbColor)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .strokeBorder(.white, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .position(thumbPosition(radius: radius, thumbSize: thumbSize))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let center = CGPoint(x: size / 2, y: size / 2)
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y
                        let distance = sqrt(dx * dx + dy * dy)
                        let maxR = size / 2

                        let clampedDist = min(distance, maxR)
                        let saturation = Double(clampedDist / maxR)

                        var angle = atan2(dx, -dy)
                        if angle < 0 { angle += 2 * .pi }
                        let hue = angle / (2 * .pi)

                        let newXY = CIEXYColor.fromHSB(hue: hue, saturation: saturation)
                        xy = newXY
                        onChanged(newXY)
                    }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var thumbColor: Color {
        xy.displayColor()
    }

    private func thumbPosition(radius: CGFloat, thumbSize: CGFloat) -> CGPoint {
        let hsb = xy.toHSB()
        let angle = hsb.hue * 2 * .pi
        let dist = hsb.saturation * radius
        let center = CGPoint(x: radius, y: radius)
        return CGPoint(
            x: center.x + CGFloat(sin(angle)) * CGFloat(dist),
            y: center.y - CGFloat(cos(angle)) * CGFloat(dist)
        )
    }
}
