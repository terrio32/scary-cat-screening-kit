import CoreGraphics
import CoreML
import Vision

public actor ScaryCatScreener {
    private struct SCSModelContainer: @unchecked Sendable {
        let visionModel: VNCoreMLModel
        let modelFileName: String
        let request: VNCoreMLRequest
    }

    private var ovrModels: [SCSModelContainer] = []
    private let enableLogging: Bool

    /// バンドルのリソースから全ての .mlmodelc ファイルをロードしてスクリーナーを初期化
    /// - Parameter enableLogging: デバッグログの出力を有効にするかどうか（デフォルト: false）
    public init(enableLogging: Bool = false) async throws {
        // まずプロパティを初期化
        self.enableLogging = enableLogging

        // リソースバンドルの取得
        let bundle = Bundle.module
        guard let resourceURL = bundle.resourceURL else {
            if enableLogging {
                print("[ScaryCatScreener] [Error] リソースバンドルが見つかりません")
            }
            throw ScaryCatScreenerError.resourceBundleNotFound
        }

        if enableLogging {
            print("[ScaryCatScreener] [Debug] リソースバンドル: \(bundle.bundlePath)")
            print("[ScaryCatScreener] [Debug] リソースURL: \(resourceURL.path)")
        }

        // .mlmodelcファイルの検索
        let modelFileURLs = try await findModelFiles(in: resourceURL)
        guard !modelFileURLs.isEmpty else {
            if self.enableLogging {
                print("[ScaryCatScreener] [Error] バンドルのリソース内に.mlmodelcファイルが存在しません")
            }
            throw ScaryCatScreenerError.modelNotFound
        }

        // モデルのロード
        let loadedModels = try await loadModels(from: modelFileURLs)
        guard !loadedModels.isEmpty else {
            throw ScaryCatScreenerError.modelNotFound
        }

        // 最終的なモデル配列を設定
        ovrModels = loadedModels

        if self.enableLogging {
            print(
                "[ScaryCatScreener] [Info] \(ovrModels.count)個のOvRモデルをロード完了: \(ovrModels.map(\.modelFileName).joined(separator: ", "))"
            )
        }
    }

    /// リソースディレクトリ内の.mlmodelcファイルを検索
    private func findModelFiles(in resourceURL: URL) async throws -> [URL] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.nameKey, .isDirectoryKey]

        if enableLogging {
            print("[ScaryCatScreener] [Debug] 検索ディレクトリ: \(resourceURL.path)")
        }

        guard let enumerator = fileManager.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: resourceKeys,
            options: .skipsHiddenFiles
        ) else {
            if enableLogging {
                print("[ScaryCatScreener] [Error] ディレクトリの列挙に失敗: \(resourceURL.path)")
            }
            throw ScaryCatScreenerError.modelLoadingFailed(originalError: ScaryCatScreenerError.modelNotFound)
        }

        var modelFileURLs: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "mlmodelc" {
            modelFileURLs.append(fileURL)
            if enableLogging {
                print("[ScaryCatScreener] [Debug] モデルファイルを検出: \(fileURL.lastPathComponent)")
            }
        }

        if enableLogging {
            print(
                "[ScaryCatScreener] [Debug] 検出されたモデル: \(modelFileURLs.map(\.lastPathComponent).joined(separator: ", "))"
            )
        }

        return modelFileURLs
    }

    /// モデルファイルからVisionモデルとリクエストを並列にロード
    private func loadModels(from modelFileURLs: [URL]) async throws -> [SCSModelContainer] {
        var collectedContainers: [SCSModelContainer] = []

        try await withThrowingTaskGroup(of: SCSModelContainer.self) { group in
            for url in modelFileURLs {
                group.addTask {
                    try await self.loadModel(from: url)
                }
            }

            // 完了したタスクの結果を収集
            for try await container in group {
                collectedContainers.append(container)
            }
        }

        return collectedContainers
    }

    /// 個別のモデルファイルからVisionモデルとリクエストをロード
    private func loadModel(from url: URL) async throws -> SCSModelContainer {
        // MLModelConfigurationの設定
        let config = MLModelConfiguration()
        config.computeUnits = .all

        // モデルのロードと設定
        let mlModel = try MLModel(contentsOf: url, configuration: config)
        let visionModel = try VNCoreMLModel(for: mlModel)

        // Visionリクエストの設定
        let request = VNCoreMLRequest(model: visionModel)
        #if targetEnvironment(simulator)
        if #available(iOS 17.0, *) {
            let allDevices = MLComputeDevice.allComputeDevices
            for device in allDevices {
                if device.description.contains("MLCPUComputeDevice") {
                    request.setComputeDevice(.some(device), for: .main)
                    break
                }
            }
        } else {
            request.usesCPUOnly = true
        }
        #endif
        request.imageCropAndScaleOption = .scaleFit

        return SCSModelContainer(
            visionModel: visionModel,
            modelFileName: url.deletingPathExtension().lastPathComponent,
            request: request
        )
    }

    // MARK: - Public Screening API

    private func screenSingleImage(
        _ imageData: Data,
        probabilityThreshold _: Float,
        enableLogging: Bool
    ) async throws -> [String: Float] {
        var confidences: [String: Float] = [:]

        try await withThrowingTaskGroup(of: (modelId: String, observations: [DetectedFeature]?).self) { group in
            for container in self.ovrModels {
                group.addTask {
                    do {
                        let handler = VNImageRequestHandler(data: imageData, options: [:])
                        try handler.perform([container.request])
                        guard let observations = container.request.results as? [VNClassificationObservation] else {
                            if enableLogging {
                                print("[ScaryCatScreener] [Warning] モデル\(container.modelFileName)の結果が不正な形式")
                            }
                            return (container.modelFileName, nil)
                        }
                        let mappedObservations = observations.map { (
                            featureName: $0.identifier,
                            confidence: $0.confidence
                        ) }
                        return (container.modelFileName, mappedObservations)
                    } catch {
                        if enableLogging {
                            print(
                                "[ScaryCatScreener] [Error] モデル \(container.modelFileName) のVisionリクエスト失敗: \(error.localizedDescription)"
                            )
                        }
                        throw ScaryCatScreenerError.predictionFailed(originalError: error)
                    }
                }
            }

            for try await result in group {
                guard let mappedObservations = result.observations else { continue }

                // すべての検出結果を収集
                for observation in mappedObservations where observation.featureName != "Rest" {
                    confidences[observation.featureName] = observation.confidence
                }
            }
        }

        return confidences
    }

    public func screen(
        imageDataList: [Data],
        probabilityThreshold: Float = 0.85,
        enableLogging: Bool = false
    ) async throws -> SCSOverallScreeningResults {
        // 各画像のスクリーニングを直列で実行
        var results: [SCSIndividualScreeningResult] = []
        for (index, imageData) in imageDataList.enumerated() {
            let confidences = try await screenSingleImage(
                imageData,
                probabilityThreshold: probabilityThreshold,
                enableLogging: enableLogging
            )
            results.append(SCSIndividualScreeningResult(
                imageData: imageData,
                confidences: confidences,
                probabilityThreshold: probabilityThreshold,
                originalIndex: index
            ))
        }

        let overallResults = SCSOverallScreeningResults(results: results)

        if enableLogging {
            print(overallResults.generateDetailedReport())
        }

        return overallResults
    }
}
