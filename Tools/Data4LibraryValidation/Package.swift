// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Data4LibraryValidation",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "data4library-validation", targets: ["Data4LibraryValidation"]),
        .executable(name: "nlk-isbn-validation", targets: ["NLKISBNValidation"]),
        .executable(name: "kakao-book-validation", targets: ["KakaoBookValidation"])
    ],
    targets: [
        .target(name: "ValidationCore"),
        .executableTarget(
            name: "Data4LibraryValidation",
            dependencies: ["ValidationCore"],
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "NLKISBNValidation",
            dependencies: ["ValidationCore"]
        ),
        .executableTarget(
            name: "KakaoBookValidation",
            dependencies: ["ValidationCore"]
        ),
        .testTarget(
            name: "Data4LibraryValidationTests",
            dependencies: ["Data4LibraryValidation", "ValidationCore"]
        ),
        .testTarget(
            name: "NLKISBNValidationTests",
            dependencies: ["NLKISBNValidation", "ValidationCore"]
        ),
        .testTarget(
            name: "KakaoBookValidationTests",
            dependencies: ["KakaoBookValidation", "ValidationCore"]
        )
    ]
)
