#if canImport(SwiftUI)
import SwiftUI

/// View presenting usage instructions and tips for best results.
struct InstructionView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                instructionSection(
                    title: "Getting Started",
                    items: [
                        "Find a well-lit environment with soft, even lighting on your face.",
                        "Hold your device at eye level and ensure the front camera has an unobstructed view.",
                        "Stay still for a few seconds while the system locks onto your face and forehead."
                    ]
                )

                instructionSection(
                    title: "During Measurement",
                    items: [
                        "Relax your facial muscles and avoid talking or exaggerated expressions.",
                        "Maintain a steady distance from the camera-about 12–18 inches works well.",
                        "Follow the on-screen progress indicator and wait for the measurement to complete."
                    ]
                )

                instructionSection(
                    title: "Tips for Best Results",
                    items: [
                        "Avoid strong backlighting or rapidly changing lighting conditions.",
                        "If measurements seem unstable, pause briefly and reposition so your forehead is centered.",
                        "For consistency, measure at similar times of day and rest for a minute before starting."
                    ]
                )

                instructionSection(
                    title: "Safety & Notes",
                    items: [
                        "This tool does not provide medical diagnoses, please consult a professional for health concerns.",
                        "Motion or facial coverings can interfere with signal quality; remove accessories if possible.",
                        "Keep the app updated to benefit from the latest accuracy and stability improvements."
                    ]
                )
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Instructions")
        .background(Color("Background").ignoresSafeArea())
    }

    @ViewBuilder
    private func instructionSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Label {
                        Text(item)
                            .font(.body)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }
}

#Preview {
    InstructionView()
}
#endif
