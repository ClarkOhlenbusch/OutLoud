import ManagedSettings
import ManagedSettingsUI
import OSLog
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        OutLoudLog.screenTime.debug("Providing shield configuration")
        let gold = UIColor(red: 0.96, green: 0.76, blue: 0.25, alpha: 1)
        let outLoudBackground = UIColor(red: 0.025, green: 0.022, blue: 0.04, alpha: 1)

        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: outLoudBackground,
            icon: makeVoiceOrbIcon(accent: gold),
            title: .init(text: "OutLoud blocked this app", color: .white),
            subtitle: nil,
            primaryButtonLabel: .init(text: "Unlock", color: .black),
            primaryButtonBackgroundColor: gold,
            secondaryButtonLabel: nil
        )
    }

    private func makeVoiceOrbIcon(accent: UIColor) -> UIImage {
        let size = CGSize(width: 160, height: 160)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let orbRect = CGRect(x: 12, y: 12, width: 136, height: 136)

            context.setShadow(
                offset: .zero,
                blur: 22,
                color: accent.withAlphaComponent(0.42).cgColor
            )
            context.setFillColor(accent.withAlphaComponent(0.16).cgColor)
            context.fillEllipse(in: orbRect)
            context.setShadow(offset: .zero, blur: 0, color: nil)

            context.saveGState()
            context.addEllipse(in: orbRect.insetBy(dx: 7, dy: 7))
            context.clip()

            let colors = [
                UIColor.white.withAlphaComponent(0.48).cgColor,
                accent.withAlphaComponent(0.92).cgColor,
                accent.withAlphaComponent(0.24).cgColor
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.48, 1]
            ) {
                context.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: 56, y: 48),
                    startRadius: 2,
                    endCenter: center,
                    endRadius: 72,
                    options: .drawsAfterEndLocation
                )
            }
            context.restoreGState()

            context.setStrokeColor(accent.withAlphaComponent(0.34).cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: orbRect.insetBy(dx: 5, dy: 5))

            let heights: [CGFloat] = [28, 46, 64, 46, 28]
            let barWidth: CGFloat = 8
            let spacing: CGFloat = 8
            let totalWidth = CGFloat(heights.count) * barWidth
                + CGFloat(heights.count - 1) * spacing
            var x = center.x - totalWidth / 2

            UIColor.white.withAlphaComponent(0.92).setFill()
            for height in heights {
                let rect = CGRect(
                    x: x,
                    y: center.y - height / 2,
                    width: barWidth,
                    height: height
                )
                UIBezierPath(roundedRect: rect, cornerRadius: barWidth / 2).fill()
                x += barWidth + spacing
            }
        }
        .withRenderingMode(.alwaysOriginal)
    }
}
