import ManagedSettings
import ManagedSettingsUI
import OSLog
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private static let lastMessageIndexKey = "lastShieldMessageIndex"

    private static let messages = [
        "I HOPE YOU’RE EXCITED TO WASTE YOUR TIME!",
        "LET’S DONATE OUR BRAINS TO THE SHAREHOLDERS!",
        "LET’S AVOID OUR RESPONSIBILITIES TOGETHER!",
        "QUICK! SOMEONE ONLINE MIGHT BE WRONG!",
        "YOUR SCREEN TIME WAS LOOKING WAY TOO HEALTHY!",
        "THE CONTENT MINES AREN’T GOING TO WORK THEMSELVES!",
        "SURELY THE NEXT VIDEO WILL FIX EVERYTHING!",
        "NOTHING NEW. BETTER CHECK AGAIN!",
        "GO ON. MAKE THE LITTLE NUMBERS GO UP!",
        "ANOTHER BRAVE JOURNEY INTO ABSOLUTELY NOTHING!",
        "YOUR LIFE CAN WAIT. THERE’S CONTENT!",
        "LET’S TURN FIVE MINUTES INTO FORTY!"
    ]

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

        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: .black,
            icon: makeVoiceMark(color: gold),
            title: .init(text: nextMessage(), color: .white),
            subtitle: nil,
            primaryButtonLabel: .init(text: "UNLOCK", color: .black),
            primaryButtonBackgroundColor: gold,
            secondaryButtonLabel: nil
        )
    }

    private func nextMessage() -> String {
        let defaults = SharedSettings.defaults
        let previousIndex = defaults.object(forKey: Self.lastMessageIndexKey) as? Int
        var index = Int.random(in: Self.messages.indices)

        if Self.messages.count > 1, index == previousIndex {
            index = (index + Int.random(in: 1..<Self.messages.count)) % Self.messages.count
        }

        defaults.set(index, forKey: Self.lastMessageIndexKey)
        return Self.messages[index]
    }

    private func makeVoiceMark(color: UIColor) -> UIImage {
        // Keep this in sync with VoiceMark in HomeView: the shield should feel
        // like an interruption from OutLoud, not a separate system product.
        let size = CGSize(width: 61, height: 42)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { _ in
            color.setFill()
            let heights: [CGFloat] = [14, 24, 34, 24, 14]
            let barWidth: CGFloat = 5
            let spacing: CGFloat = 4
            let totalWidth = CGFloat(heights.count) * barWidth
                + CGFloat(heights.count - 1) * spacing
            let startX = (size.width - totalWidth) / 2

            for (offset, height) in heights.enumerated() {
                let rect = CGRect(
                    x: startX + CGFloat(offset) * (barWidth + spacing),
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                UIBezierPath(roundedRect: rect, cornerRadius: barWidth / 2).fill()
            }
        }
        .withRenderingMode(.alwaysOriginal)
    }
}
