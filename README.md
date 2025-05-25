# ScaryCatScreeningKit

## プロジェクト概要

ScaryCatScreeningKitは、機械学習モデル（One-vs-Restアプローチを採用）を使用して画像を分類し、設定可能な確率の閾値に基づいてスクリーニングを行う機能を提供するライブラリです。

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/aktrh/scary-cat-screening-kit)

## 必要条件

- iOS 17.0以上
- Swift 6.0以上
- Xcode 15.0以上

## 設計

*   **`ScaryCatScreener.swift`**: 画像スクリーニングの主要なインターフェースとOne-vs-Rest分類ロジックを提供します。モデルの読み込み、画像処理を行います。
*   **`ScreeningDataTypes.swift`**: スクリーニングに関連する主要なデータ構造を定義します。
*   **`ScaryCatScreenerError.swift`**: 発生しうるエラーを定義します。

## ディレクトリ構成

```tree
.
├── SampleApp/
├── Sources/
│   ├── OvRModels/          
│   ├── ScreeningDataTypes.swift  
│   ├── ScaryCatScreenerError.swift
│   └── ScaryCatScreener.swift
├── Package.swift
├── project.yml
└── README.md
```

`SampleApp`の動作確認は、シミュレータではなく iPhone 16 などの実機で行うことを推奨します。シミュレータ環境では Neural Engine などの計算ユニットが使用できないため、スクリーニングの精度と速度が低下します。

### 利用方法

#### 1. インポート

`ScaryCatScreener` を利用するSwiftファイルで、必要なモジュールをインポートします。

```swift
import ScaryCatScreeningKit
```

#### 2. 初期化

`ScaryCatScreener` の初期化は、モデルのロードに失敗する可能性があるため、エラーをスローする可能性があるため、 `do-catch` ブロックを使用してエラーハンドリングを行うことを推奨します。

```swift
let screener: ScaryCatScreener

do {
    screener = try await ScaryCatScreener(enableLogging: true) // 初期化時のログ出力を有効にする
} catch let error as NSError {
    print("ScaryCatScreener の初期化に失敗しました: \(error.localizedDescription)")
    print("エラーコード: \(error.code), ドメイン: \(error.domain)")
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
        print("原因: \(underlying.localizedDescription)")
    }
}
```

#### 3. 画像のスクリーニング

`screen` メソッドは非同期 で行われ、エラーをスローする可能性があります。そのため、`async` コンテキスト内では `try await` を使用して呼び出す必要があります。

**パラメータ:**

-   `cgImages`: `[CGImage]` - スクリーニング対象の画像の配列。
-   `probabilityThreshold`: `Float` (デフォルト: `0.85`)
    -   この値は `0.0` から `1.0` の範囲で指定します。
    -   いずれかのモデルが画像を「安全でない」カテゴリに属すると判定した際の信頼度 (confidence) が、この閾値以上の場合、その画像は総合的に「安全でない」と見なされます。
-   `enableLogging`: `Bool` (デフォルト: `false`)
    -   `true` を指定すると、内部処理に関する詳細ログ（各画像のスクリーニングレポートなど）がコンソールに出力されます。

```swift
let cgImages: [CGImage] = [/* ... スクリーニングしたい画像の配列 ... */] 

Task {
    do {
        // `screener` は上記で初期化済みの ScaryCatScreener インスタンス
        // 信頼度が85%以上のものを「安全でない」カテゴリの判定基準とし、ログ出力を有効にする例
        let results = try await screener.screen(
            cgImages: cgImages, 
            probabilityThreshold: 0.85, 
            enableLogging: true
        )
        
        // 結果をSCSOverallScreeningResultsでラップ
        let screeningResults = SCSOverallScreeningResults(results: results)
        
        // 安全な画像のみを取得
        let safeImages: [CGImage] = screeningResults.safeResults.map(\.cgImage)
        
        // 危険な画像のみを取得
        let unsafeImages: [CGImage] = screeningResults.unsafeResults.map(\.cgImage)
        
        // レポートを出力
        print(screeningResults.generateDetailedReport())
        
    } catch let error as NSError {
        print("スクリーニング処理でエラーが発生しました: \(error.localizedDescription)")
        print("エラーコード: \(error.code), ドメイン: \(error.domain)")
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
            print("原因: \(underlying.localizedDescription)")
        }
    }
}
```

`screen(cgImages:probabilityThreshold:enableLogging:)` メソッドを使用して、複数の `CGImage` を一度にスクリーニングできます。各画像のスクリーニング結果は`SCSIndividualScreeningResult`として返され、`SCSOverallScreeningResults`でラップすることで、安全な画像の抽出や危険な画像の分析などが容易になります。

主要な構造は以下の通りです

```swift
public struct SCSIndividualScreeningResult: Identifiable {
    public var id = UUID()
    public var cgImage: CGImage
    public var confidences: [String: Float]
    public var probabilityThreshold: Float
    
    public var isSafe: Bool {
        !confidences.values.contains { $0 >= probabilityThreshold }
    }
}

public struct SCSOverallScreeningResults {
    public var results: [SCSIndividualScreeningResult]
    
    public var safeResults: [SCSIndividualScreeningResult] {
        results.filter { $0.isSafe }
    }
    
    public var unsafeResults: [SCSIndividualScreeningResult] {
        results.filter { !$0.isSafe }
    }
}
```

完全な実装は [Sources/ScreeningDataTypes.swift](Sources/ScreeningDataTypes.swift) を参照してください。

### エラーハンドリング

フレームワークは `ScaryCatScreenerError` enumを通じて包括的なエラーハンドリングシステムを実装しています。このエラー型は `ScaryCatScreenerError.swift` で定義されており、 `NSError` に変換して throw されます。初期化時およびスクリーニング処理中に発生する可能性のある具体的なエラーについては、「利用方法」セクションの例も参照してください。

| エラータイプ                       | 説明                                                         |
| -------------------------------- | ------------------------------------------------------------ |
| `resourceBundleNotFound`         | MLモデルを含むリソースバンドルが見つからない場合に発生します。     |
| `modelLoadingFailed(originalError:)` | MLモデルの読み込み中にエラーが発生した場合に発生します。           |
| `modelNotFound`                  | 必要なMLモデルファイルが見つからない場合に発生します。             |
| `predictionFailed(originalError:)`   | 画像分類中にエラーが発生した場合に発生します。                   |

