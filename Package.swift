// swift-tools-version: 6.0

import PackageDescription

let package = Package(
	name: "anki-lyrics-note-generator",
	platforms: [.macOS(.v13)],
	dependencies: [
		.package(
			url: "https://github.com/apple/swift-algorithms.git",
			.upToNextMajor(from: "1.2.0")
		),
		.package(
			url: "https://github.com/apple/swift-argument-parser.git",
			.upToNextMajor(from: "1.6.1")
		),
		.package(
			url: "https://github.com/apple/swift-collections.git",
			.upToNextMajor(from: "1.2.0")
		),
		.package(
			url: "https://github.com/pointfreeco/swift-html",
			.upToNextMajor(from: "0.4.0")
		),
	],
	targets: [
		.executableTarget(
			name: "AnkiLyricsNoteGenerator",
			dependencies: [
				.product(name: "Algorithms", package: "swift-algorithms"),
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "Collections", package: "swift-collections"),
				.product(name: "Html", package: "swift-html"),
			]
		),
	]
)
