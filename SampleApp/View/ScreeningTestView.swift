import Kingfisher
import ScaryCatScreeningKit
import SwiftUI

struct ScreeningTestView: View {
    @StateObject private var viewModel = ScreeningViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    ScreeningButton()

                    // 閾値情報の表示
                    VStack(alignment: .leading, spacing: 4) {
                        Text("スクリーニングの設定")
                            .font(.headline)
                        Text("危険と判定する閾値: \(String(format: "%.1f", viewModel.probabilityThreshold * 100))%")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !viewModel.fetchedImages.isEmpty {
                        Text("取得した画像: \(viewModel.fetchedImages.count)枚")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(viewModel.fetchedImages, id: \.url) { item in
                                    Image(uiImage: item.image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 100)
                                        .cornerRadius(8)
                                        .padding(.trailing, 4)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text("エラー: \(errorMessage)")
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding()
                            .multilineTextAlignment(.center)
                    }

                    if !viewModel.safeResults.isEmpty {
                        ScreeningResultScrollView(
                            title: "安全な画像",
                            results: viewModel.safeResults
                        )
                    }

                    if !viewModel.unsafeResults.isEmpty {
                        ScreeningResultScrollView(
                            title: "危険な画像",
                            results: viewModel.unsafeResults
                        )
                    }

                    Spacer()
                }
                .padding(.bottom)
            }
            .navigationTitle("Scary Cat Screener")
        }
    }

    @ViewBuilder
    private func screeningButton() -> some View {
        Button(
            action: {
                viewModel.fetchAndScreenImagesFromCatAPI(count: 5)
            },
            label: {
                HStack {
                    Image(systemName: "arrow.clockwise.icloud")
                    Text(
                        viewModel.isLoading && !viewModel.isScreenerReady ? "スクリーナー初期化中..." :
                            (viewModel.isLoading ? "処理中..." : "APIから猫画像を取得してスクリーニング")
                    )
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    viewModel.isLoading && !viewModel.isScreenerReady ? Color.orange :
                        (viewModel.isLoading ? Color.gray : Color.cyan)
                )
                .foregroundColor(.white)
                .cornerRadius(10)
                .animation(.easeOut(duration: 0.3), value: viewModel.isLoading)
                .animation(.easeOut(duration: 0.3), value: viewModel.isScreenerReady)
            }
        )
        .disabled(
            viewModel.isLoading || !viewModel.isScreenerReady
        )
        .padding(.horizontal)
        .padding(.top)
    }
}
