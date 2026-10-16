import SwiftUI
import MobileCoreServices

struct AppSelector: View {
    @Binding var selectedBundleIdentifiers: Set<String>
    @StateObject private var appLoader = AppLoader()

    var body: some View {
        VStack {
            if appLoader.isLoading {
                ProgressView("Cargando aplicaciones...")
            } else if let error = appLoader.error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
            } else {
                List(appLoader.applications) { app in
                    HStack {
                        if let icon = app.icon {
                            Image(uiImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .cornerRadius(8)
                        }
                        VStack(alignment: .leading) {
                            Text(app.name)
                                .font(.headline)
                            Text(app.bundleIdentifier)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isSelected: Binding(
                            get: { selectedBundleIdentifiers.contains(app.bundleIdentifier) },
                            set: { isSelected in
                                if isSelected {
                                    selectedBundleIdentifiers.insert(app.bundleIdentifier)
                                } else {
                                    selectedBundleIdentifiers.remove(app.bundleIdentifier)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .padding()
    }
}

class AppLoader: ObservableObject {
    @Published var applications: [AppInfo] = []
    @Published var isLoading = true
    @Published var error: Error?

    init() {
        loadApplications()
    }

    func loadApplications() {
        isLoading = true
        error = nil

        DispatchQueue.global(qos: .background).async {
            do {
                let workspace = LSApplicationWorkspace.default()
                let allApps = workspace?.allApplications ?? []

                // Filter to only applications that have a bundle identifier and are not system daemons?
                var apps: [AppInfo] = []
                for proxy in allApps {
                    guard let bundleID = proxy.bundleIdentifier,
                          !bundleID.isEmpty else { continue }

                    // Skip system apps if desired? We'll include all for now.
                    let name = proxy.localizedName ?? bundleID

                    // Try to get icon
                    var icon: UIImage? = nil
                    if let iconURL = proxy.iconURL {
                        if let data = try? Data(contentsOf: iconURL),
                           let uiImage = UIImage(data: data) {
                            icon = uiImage
                        }
                    }

                    apps.append(AppInfo(bundleIdentifier: bundleID,
                                        name: name,
                                        icon: icon))
                }

                // Sort by name
                apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedLess }

                DispatchQueue.main.async {
                    self.applications = apps
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
}

struct AppInfo: Identifiable {
    let id = UUID()
    let bundleIdentifier: String
    let name: String
    let icon: UIImage?
}