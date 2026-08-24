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
        let iconConfiguration = UIImage.SymbolConfiguration(pointSize: 54, weight: .medium)
        let voiceIcon = UIImage(
            systemName: "waveform.circle.fill",
            withConfiguration: iconConfiguration
        )?.withTintColor(gold, renderingMode: .alwaysOriginal)

        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: outLoudBackground,
            icon: voiceIcon,
            title: .init(text: "OutLoud blocked this app", color: .white),
            subtitle: nil,
            primaryButtonLabel: .init(text: "Unlock", color: .black),
            primaryButtonBackgroundColor: gold,
            secondaryButtonLabel: nil
        )
    }
}
