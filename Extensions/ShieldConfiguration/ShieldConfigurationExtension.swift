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
        let phrase = SharedSettings.phrase

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.055, green: 0.05, blue: 0.075, alpha: 0.96),
            icon: UIImage(systemName: "waveform.circle.fill")?.withTintColor(gold),
            title: .init(text: "Pause before you open this.", color: .white),
            subtitle: .init(
                text: "Tap once. OutLoud will listen for “\(phrase)”.",
                color: UIColor.white.withAlphaComponent(0.76)
            ),
            primaryButtonLabel: .init(text: "Start the pause", color: .black),
            primaryButtonBackgroundColor: gold,
            secondaryButtonLabel: .init(text: "Go back", color: .white)
        )
    }
}
