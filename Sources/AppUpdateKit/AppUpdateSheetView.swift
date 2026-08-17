import SwiftUI

/// The standard update prompt. Hosts present it through their own sheet
/// system; internally it dismisses via the environment, per house convention.
public struct AppUpdateSheetView: View {
    private let update: AppUpdatePresentation
    private let controller: AppUpdateController

    @Environment(\.dismiss) private var dismiss

    public init(update: AppUpdatePresentation, controller: AppUpdateController) {
        self.update = update
        self.controller = controller
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        Text(update.currentVersion)
                    } label: {
                        Text("Current Version", bundle: .module)
                    }
                    LabeledContent {
                        Text(update.latestVersion)
                    } label: {
                        Text("Latest Version", bundle: .module)
                    }
                }

                if let releaseNotes = update.releaseNotes,
                   !releaseNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Text(releaseNotes.trimmingCharacters(in: .whitespacesAndNewlines))
                    } header: {
                        Text("What's New", bundle: .module)
                    }
                }

                Section {
                    Button {
                        controller.ignoreThisVersion()
                        dismiss()
                    } label: {
                        Text("Skip This Version", bundle: .module)
                    }
                }
            }
            .navigationTitle(Text("Update Available", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        controller.remindLater()
                        dismiss()
                    } label: {
                        Text("Later", bundle: .module)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Link(destination: update.storeURL) {
                        Text("Update Now", bundle: .module)
                    }
                }
            }
        }
    }
}
