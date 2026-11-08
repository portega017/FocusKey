import UIKit
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
        let reason = FocusStatus.current().reason(matching: contains)
        let title = name.map { "\($0) está bloqueada" } ?? "Bloqueado por FocusKey"

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: UIColor.systemIndigo.withAlphaComponent(0.25),
            icon: UIImage(named: "shieldLogo"),
            title: ShieldConfiguration.Label(text: title, color: .label),
            subtitle: ShieldConfiguration.Label(text: reason, color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Volver a concentrarme", color: .white),
            primaryButtonBackgroundColor: .systemIndigo
        )
    }
}
