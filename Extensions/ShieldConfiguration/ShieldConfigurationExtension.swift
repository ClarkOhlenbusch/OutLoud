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
        let phrase = SharedSettings.phrase

        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: outLoudBackground,
            icon: UIImage(systemName: "waveform.circle.fill")?.withTintColor(gold),
            title: .init(text: "Unlock with your voice", color: .white),
            subtitle: .init(
                text: "Say “\(phrase)”",
                color: UIColor.white.withAlphaComponent(0.72)
            ),
            primaryButtonLabel: .init(text: "Unlock", color: .black),
            primaryButtonBackgroundColor: gold,
            secondaryButtonLabel: .init(
                text: "Not now",
                color: UIColor.white.withAlphaComponent(0.68)
            )
        )
    }
}
