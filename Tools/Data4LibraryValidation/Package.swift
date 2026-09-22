// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Data4LibraryValidation",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "data4library-validation", targets: ["Data4LibraryValidation"])
    ],
    targets: [
        .executableTarget(
            name: "Data4LibraryValidation",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "Data4LibraryValidationTests",
            dependencies: ["Data4LibraryValidation"]
        )
    ]
)
