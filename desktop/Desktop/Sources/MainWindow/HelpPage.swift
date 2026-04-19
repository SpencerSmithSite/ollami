import SwiftUI

struct HelpPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "questionmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Ollami Help")
                .font(.title2.weight(.semibold))

            Text("Ollami runs entirely on your machine. Report issues or check documentation at the project repository.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 400)

            Button("Open GitHub Repository") {
                if let url = URL(string: "https://github.com/SpencerSmithSite/Ollami") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
    }
}
