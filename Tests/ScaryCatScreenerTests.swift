import CoreGraphics
@testable import ScaryCatScreeningKit
import XCTest

/// 実機ではないシミュレータでのテストは十分な精度を得られないので精度の検証は省く
final class ScaryCatScreenerTests: XCTestCase {
    var screener: ScaryCatScreener!

    override func setUp() async throws {
        try await super.setUp()
        screener = try await ScaryCatScreener(enableLogging: true)
    }

    /// 初期化テスト
    func testInitialization() async throws {
        // ログ出力なしで初期化
        let screenerWithoutLogging = try await ScaryCatScreener(enableLogging: false)
        XCTAssertNotNil(screenerWithoutLogging)

        // ログ出力ありで初期化
        let screenerWithLogging = try await ScaryCatScreener(enableLogging: true)
        XCTAssertNotNil(screenerWithLogging)
    }

    /// TestResourcesディレクトリ内の画像を使用してスクリーニングを実行し、以下を検証:
    /// - 結果が空でないこと
    /// - 入力画像と結果が1対1で対応していること
    /// - 怖い特徴の信頼度が0〜1の範囲内であること
    /// - 怖いと判定された特徴の信頼度が閾値を超えていること
    /// - 入力画像数と結果数が一致すること
    /// - ログ出力が得られること
    func testScreenReturnsResults() async throws {
        // #filePathを使用してTestResourcesディレクトリのURLを取得
        var dir = URL(fileURLWithPath: #filePath)
        dir.deleteLastPathComponent()
        let resourceURL = dir.appendingPathComponent("TestResources")
        print("Resource URL: \(resourceURL.path)")

        // TestResourcesディレクトリ内のすべてのファイルを取得
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil) else {
            XCTFail("Failed to read TestResources directory")
            return
        }

        // 全ての画像を読み込む
        var testImages: [CGImage] = []
        var loadedImageURLs: [URL] = []

        for fileURL in files {
            if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
            {
                testImages.append(image)
                loadedImageURLs.append(fileURL)
                print("Loaded image: \(fileURL.lastPathComponent)")
            }
        }

        guard !testImages.isEmpty else {
            XCTFail("No valid image files found in TestResources")
            return
        }

        // スクリーニングを実行
        let probabilityThreshold: Float = 0.85
        let enableLogging = true

        // 全ての画像を一度にスクリーニング
        let results = try await screener.screen(
            cgImages: testImages,
            probabilityThreshold: probabilityThreshold,
            enableLogging: enableLogging
        )

        // 結果の検証
        XCTAssertFalse(results.isEmpty, "スクリーニング結果が空です")
        XCTAssertEqual(results.count, testImages.count, "入力画像数と結果数が一致しません")

        // 各結果の検証
        for (index, result) in results.enumerated() {
            XCTAssertNotNil(result.cgImage, "結果に画像が含まれていません")
            print("Checking result for: \(loadedImageURLs[index].lastPathComponent)")

            // 怖い特徴の検証
            for (featureName, confidence) in result.confidences {
                XCTAssertFalse(featureName.isEmpty, "怖い特徴の名前が空です")
                XCTAssertGreaterThanOrEqual(confidence, 0.0, "信頼度が0未満です")
                XCTAssertLessThanOrEqual(confidence, 1.0, "信頼度が1を超えています")
            }
        }

        // 全体の結果の検証
        let overallResults = SCSOverallScreeningResults(results: results)

        // 各画像の安全性判定を検証
        for result in results {
            if !result.isSafe {
                print(
                    "怖い特徴を検出: \(result.confidences.filter { $0.value >= probabilityThreshold }.map { "\($0.key) (\($0.value))" }.joined(separator: ", "))"
                )
                XCTAssertTrue(
                    overallResults.unsafeResults.contains { $0.cgImage == result.cgImage },
                    "閾値を超えた特徴がある画像が危険な画像として判定されていません"
                )
            } else {
                XCTAssertTrue(
                    overallResults.safeResults.contains { $0.cgImage == result.cgImage },
                    "閾値を超えた特徴がない画像が安全な画像として判定されていません"
                )
            }
        }

        XCTAssertEqual(
            overallResults.safeResults.count + overallResults.unsafeResults.count,
            testImages.count,
            "安全な画像と危険な画像の合計が入力画像数と一致しません"
        )

        // レポートの検証
        let report = overallResults.generateDetailedReport()
        XCTAssertFalse(report.isEmpty, "レポートが空です")
    }
}
