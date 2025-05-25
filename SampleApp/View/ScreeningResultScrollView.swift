import Kingfisher
import ScaryCatScreeningKit
import SwiftUI

struct ScreeningResultScrollView: View {
    let title: String
    let results: [SCSIndividualScreeningResult]

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(results) { result in
                        ScreeningResultItemView(result: result)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct ScreeningResultItemView: View {
    let result: SCSIndividualScreeningResult

    private var accentColor: Color {
        result.isSafe ? .green : .red
    }

    private var features: [(featureName: String, confidence: Float)] {
        result.confidences
            .sorted { $0.value > $1.value }
            .map { (featureName: $0.key, confidence: $0.value) }
    }

    var body: some View {
        VStack {
            Image(uiImage: UIImage(cgImage: result.cgImage))
                .resizable()
                .scaledToFill()
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(accentColor, lineWidth: 2)
                )

            VStack(alignment: .leading, spacing: 4) {
                ForEach(features, id: \.featureName) { feature in
                    HStack {
                        Text(feature.featureName)
                            .font(.caption)
                            .foregroundColor(accentColor)
                        Text("(\(String(format: "%.1f", feature.confidence * 100))%)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accentColor.opacity(0.1))
            .cornerRadius(6)
        }
    }
}
