import SwiftUI

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(NLColor.muted)
            Spacer(minLength: 16)
            Text(value.isEmpty ? "-" : value)
                .foregroundColor(NLColor.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct DeleteConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NLSpacing.lg) {
            Text(title)
                .font(.title3.bold())
                .foregroundColor(NLColor.navy)
            Text(message)
                .foregroundColor(NLColor.muted)
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Delete") {
                    onDelete()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .tint(.red)
            }
        }
        .padding()
        .presentationDetents([.height(230)])
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(NLColor.navy)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
