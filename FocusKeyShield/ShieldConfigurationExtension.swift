import UIKit
import SwiftUI
import ManagedSettings
import ManagedSettingsUI

/// Custom screen shown when the user opens a blocked app or website.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration(title: application.localizedDisplayName) { profile in
            application.token.map(profile.contains) ?? false
        }
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        configuration(title: application.localizedDisplayName) { profile in
            (application.token.map(profile.contains) ?? false) || (category.token.map(profile.contains) ?? false)
        }
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration(title: webDomain.domain) { profile in
            webDomain.token.map(profile.contains) ?? false
        }
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        configuration(title: webDomain.domain) { profile in
            (webDomain.token.map(profile.contains) ?? false) || (category.token.map(profile.contains) ?? false)
        }
    }

    private func configuration(title name: String?, contains: (FocusProfile) -> Bool) -> ShieldConfiguration {
        let status = FocusStatus.current()
        let reason = status.reason(matching: contains)
        let color = UIColor(status.profile(matching: contains)?.color ?? .indigo)
        let title = name.map { String(localized: "\($0) está bloqueada") } ?? String(localized: "Bloqueado por FocusKey")

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: color.withAlphaComponent(0.25),
            icon: UIImage(named: "shieldLogo"),
            title: ShieldConfiguration.Label(text: title, color: .label),
            subtitle: ShieldConfiguration.Label(text: reason + "\n\n" + FocusQuotes.current(), color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: String(localized: "Volver a concentrarme"), color: .white),
            primaryButtonBackgroundColor: color
        )
    }
}
