import CoreGraphics
import Foundation
import Vision

/// 検出された特徴（クラス名と信頼度のペア）
public typealias DetectedFeature = (featureName: String, confidence: Float)

/// 個別の画像のスクリーニング結果
public struct SCSIndividualScreeningResult: Identifiable {
    public var id = UUID()
    public var cgImage: CGImage
    public var confidences: [String: Float]
    public var probabilityThreshold: Float

    public var isSafe: Bool {
        !confidences.values.contains { $0 >= probabilityThreshold }
    }

    public init(
        cgImage: CGImage,
        confidences: [String: Float],
        probabilityThreshold: Float
    ) {
        self.cgImage = cgImage
        self.confidences = confidences
        self.probabilityThreshold = probabilityThreshold
    }

    /// 詳細なレポートを生成
    public func generateDetailedReport() -> String {
        let features = confidences
            .sorted { $0.value > $1.value }
            .map { "  \($0.key): \(String(format: "%.0f", $0.value * 100))%" }
            .joined(separator: "\n")

        return "安全: \(isSafe ? "はい" : "いいえ")\n特徴:\n\(features)"
    }
}

/// 複数のスクリーニング結果を管理する構造体
public struct SCSOverallScreeningResults {
    public var results: [SCSIndividualScreeningResult]

    public var safeResults: [SCSIndividualScreeningResult] {
        results.filter(\.isSafe)
    }

    public var unsafeResults: [SCSIndividualScreeningResult] {
        results.filter { !$0.isSafe }
    }

    public init(results: [SCSIndividualScreeningResult]) {
        self.results = results
    }

    /// 詳細なレポートを生成
    public func generateDetailedReport() -> String {
        results.enumerated().map { index, result in
            """
            --------------------------------
            【画像 \(index + 1)】
            \(result.generateDetailedReport())
            --------------------------------
            """
        }.joined(separator: "\n")
    }
}
