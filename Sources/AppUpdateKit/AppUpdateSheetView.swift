import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The standard update prompt. Hosts present it through their own sheet
/// system; internally it dismisses via the environment, per house convention.
public struct AppUpdateSheetView: View {
    private let update: AppUpdatePresentation
    private let controller: AppUpdateController

    public init(update: AppUpdatePresentation, controller: AppUpdateController) {
        self.update = update
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            AppUpdateSheetCloseBar(controller: controller)
                .scenePadding(.horizontal)
                .padding(.top)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    AppUpdateSheetIcon(appName: update.appName, size: 100)
                        .padding(.top)
                        .padding(.bottom)

                    AppUpdateSheetCopy(
                        currentVersion: update.currentVersion,
                        latestVersion: update.latestVersion
                    )

                    if let notes = trimmedNotes {
                        AppUpdateSheetNotes(notes: notes)
                            .padding(.top)
                    }
                }
                .scenePadding(.horizontal)
                .padding(.bottom)
            }

            AppUpdateSheetActions(storeURL: update.storeURL, controller: controller)
                .scenePadding(.horizontal)
                .padding(.bottom)
        }
        .background(.background)
        #if os(iOS)
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.hidden)
        #endif
    }

    private var trimmedNotes: String? {
        guard let notes = update.releaseNotes?
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !notes.isEmpty
        else { return nil }
        return notes
    }
}

private struct AppUpdateSheetCloseBar: View {
    let controller: AppUpdateController

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Spacer()
            Button {
                controller.remindLater()
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .appUpdateGlassButtonStyle()
            .accessibilityLabel(Text("Close", bundle: .module))
        }
    }
}

private struct AppUpdateSheetIcon: View {
    let appName: String
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = HostAppIcon.image {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.20, style: .continuous))
            } else {
                Text(String(appName.prefix(1)).uppercased())
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: size, height: size)
                    .background(
                        .quaternary,
                        in: RoundedRectangle(cornerRadius: size * 0.20, style: .continuous)
                    )
            }
        }
    }
}

private struct AppUpdateSheetCopy: View {
    let currentVersion: String
    let latestVersion: String

    var body: some View {
        VStack(spacing: 8) {
            Text("New Version", bundle: .module)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tint)
            Text("A new version is here!", bundle: .module)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(
                "You're on v\(currentVersion). v\(latestVersion) is available.",
                bundle: .module
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AppUpdateSheetNotes: View {
    let notes: String

    var body: some View {
        Text(verbatim: notes)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
    }
}

private struct AppUpdateSheetActions: View {
    let storeURL: URL
    let controller: AppUpdateController

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack {
            Button {
                openURL(storeURL)
            } label: {
                Text("Update Now", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .appUpdateGlassProminentButtonStyle()
            .controlSize(.large)

            Button {
                controller.remindLater()
                dismiss()
            } label: {
                Text("Remind Me Later", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .appUpdateGlassButtonStyle()
            .controlSize(.large)
        }
    }
}

private enum HostAppIcon {
    static var image: Image? {
        #if canImport(UIKit)
        uiImage.map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
        nsImage.map { Image(nsImage: $0) }
        #else
        nil
        #endif
    }

    #if canImport(UIKit)
    private static var uiImage: UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any]
        else { return nil }

        if let name = primary["CFBundleIconName"] as? String,
           let image = UIImage(named: name) {
            return image
        }
        if let files = primary["CFBundleIconFiles"] as? [String] {
            for name in files.reversed() {
                if let image = UIImage(named: name) {
                    return image
                }
            }
        }
        return nil
    }
    #elseif canImport(AppKit)
    private static var nsImage: NSImage? {
        NSImage(named: NSImage.applicationIconName)
    }
    #endif
}

private extension View {
    @ViewBuilder
    func appUpdateGlassProminentButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func appUpdateGlassButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
