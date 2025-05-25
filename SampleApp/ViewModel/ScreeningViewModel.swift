import Combine
import Kingfisher
import ScaryCatScreeningKit
import SwiftUI

struct CatImageResponse: Decodable, Identifiable {
    let id: String
    let url: String
    let width: Int?
    let height: Int?
}

@MainActor
class ScreeningViewModel: ObservableObject {
    private let enableLogging = true
    public let probabilityThreshold: Float = 0.85

    @Published private(set) var fetchedImages: [(url: URL, image: UIImage)] = []
    @Published private(set) var safeResults: [SCSIndividualScreeningResult] = []
    @Published private(set) var unsafeResults: [SCSIndividualScreeningResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isScreenerReady = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var screeningSummary: String = ""

    private var screener: ScaryCatScreener?
    private let imageDownloader: ImageDownloader
    private let imageCache: ImageCache

    init() {
        // キャッシュの設定
        imageCache = ImageCache.default
        imageCache.memoryStorage.config.expiration = .days(1)
        imageCache.diskStorage.config.expiration = .days(1)
        imageCache.memoryStorage.config.totalCostLimit = 500 * 1024 * 1024 // 500MB
        imageCache.diskStorage.config.sizeLimit = 500 * 1024 * 1024 // 500MB

        // ダウンローダーの設定
        imageDownloader = ImageDownloader.default
        imageDownloader.downloadTimeout = 15

        Task {
            do {
                self.screener = try await ScaryCatScreener(enableLogging: enableLogging)
                self.isScreenerReady = true
            } catch {
                self.errorMessage = "スクリーナーの初期化に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    func fetchAndScreenImagesFromCatAPI(count: Int) {
        Task {
            isLoading = true
            errorMessage = nil
            fetchedImages = []
            safeResults = []
            unsafeResults = []
            screeningSummary = ""

            do {
                // Cat APIから画像URLを取得
                guard let url = URL(string: "https://api.thecatapi.com/v1/images/search?limit=\(count)") else {
                    throw NSError(
                        domain: "ScreeningViewModel",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"]
                    )
                }
                let (data, _) = try await URLSession.shared.data(from: url)
                let responses = try JSONDecoder().decode([CatImageResponse].self, from: data)

                guard let screener = self.screener else {
                    throw NSError(
                        domain: "ScreeningViewModel",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Screener not initialized"]
                    )
                }

                // 画像を直列でダウンロード
                var cgImages: [CGImage] = []
                for response in responses {
                    guard let url = URL(string: response.url) else { continue }

                    do {
                        // Kingfisherを使用して画像をダウンロード
                        let image = try await withCheckedThrowingContinuation { continuation in
                            KingfisherManager.shared.retrieveImage(
                                with: url,
                                options: [
                                    .cacheOriginalImage,
                                    .cacheMemoryOnly,
                                    .backgroundDecode,
                                ]
                            ) { result in
                                switch result {
                                    case let .success(value):
                                        continuation.resume(returning: value.image)
                                    case let .failure(error):
                                        continuation.resume(throwing: error)
                                }
                            }
                        }

                        guard let cgImage = image.cgImage else { continue }

                        fetchedImages.append((url: url, image: image))
                        cgImages.append(cgImage)
                    } catch {
                        print("画像のダウンロードに失敗: \(error.localizedDescription)")
                        continue
                    }
                }

                // すべての画像をクリーニング
                let results = try await screener.screen(
                    cgImages: cgImages,
                    probabilityThreshold: probabilityThreshold,
                    enableLogging: enableLogging
                )

                let screeningResults = SCSOverallScreeningResults(results: results)
                safeResults = screeningResults.safeResults
                unsafeResults = screeningResults.unsafeResults
                screeningSummary = screeningResults.generateDetailedReport()

            } catch {
                self.errorMessage = "エラーが発生しました: \(error.localizedDescription)"
            }

            isLoading = false
        }
    }
}
