import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let supportURL = URL(string: "mailto:support@uchu-neko.com")!
    private let privacyURL = URL(string: "https://uchu-neko.com/#privacy-policy")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image("AppIconDisplay")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Meow Music")
                                .font(.title2.bold())
                            Text(versionText)
                                .foregroundStyle(Theme.secondaryText)
                            Text("by Uchu-Neko")
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Theme.card)

                Section("Help & Privacy") {
                    Link(destination: supportURL) {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                    Link(destination: privacyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }
                .foregroundStyle(Theme.orange)
                .listRowBackground(Theme.card)

                Section {
                    Text("A free, distraction-free player for the music collection you own. No ads, subscriptions, or in-app purchases.")
                        .foregroundStyle(Theme.secondaryText)
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }
}
