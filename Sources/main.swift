import Algorithms
import ArgumentParser
import Foundation
import Html

private struct AnkiLyricsNoteGenerator: ParsableArguments {
	@Argument(
		help: ArgumentHelp(
			"Directory containing plain-text lyrics (one file per song)",
			valueName: "source-directory"
		),
		completion: .directory, transform: URL.init(fileURLWithPath:)
	)
	var sourceDirectoryURL: URL
}

private struct Song {
	let title: String
	let lyrics: [String]
}

struct PromptAndAnswer: Hashable {
	let prompt: [String]
	let answer: String
}

private struct Note: Hashable {
	let front: Node
	let back: Node
}

private extension BidirectionalCollection {
	/// The `count` elements immediately *before* `end`.
	/// Returns `nil` if there aren't enough elements.
	func window(ofCount count: Int, endingAt endIndex: Index) -> SubSequence? {
		guard count > 0, endIndex != self.endIndex else { return nil }
		guard let startIndex = self.index(endIndex, offsetBy: -count, limitedBy: startIndex),
				distance(from: startIndex, to: endIndex) == count
		else { return nil }
		return self[startIndex..<endIndex]
	}
}

private func textFileURLs(at directoryURL: URL) throws -> [URL] {
	return try FileManager.default.contentsOfDirectory(
		at: directoryURL,
		includingPropertiesForKeys: [.isDirectoryKey],
		options: [.skipsHiddenFiles, .skipsPackageDescendants]
	)
	.filter { url in
		let urlIsOfDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
		return !urlIsOfDirectory && url.pathExtension.lowercased() == "txt"
	}
}

private func windowUniquelyDeterminesElement<C: BidirectionalCollection>(
	in collection: C,
	endingAt index: C.Index,
	windowSize: Int
) -> Bool where C.Element: Equatable {
	guard let window = collection.window(ofCount: windowSize, endingAt: index) else {
		return false
	}

	var otherIndex = collection.index(
		collection.startIndex,
		offsetBy: windowSize,
		limitedBy: collection.endIndex
	) ?? collection.endIndex
	while otherIndex != collection.endIndex {
		if otherIndex != index,
			let otherWindow = collection.window(ofCount: windowSize, endingAt: otherIndex),
			otherWindow.elementsEqual(window),
			collection[otherIndex] != collection[index] {
			return false
		}
		otherIndex = collection.index(after: otherIndex)
	}
	return true
}

private func shortestUniqueWindowSize(
	in items: [String],
	endingAt endIndex: Int
) -> Int? {
	guard items.indices.contains(endIndex), endIndex > 0 else { return nil }

	for windowSize in 1...endIndex {
		if windowUniquelyDeterminesElement(in: items, endingAt: endIndex, windowSize: windowSize) {
			return windowSize
		}
	}
	return nil
}

private func notes(for song: Song) -> [Note] {
	var promptAndAnswers: [PromptAndAnswer] = []

	let lines = song.lyrics + ["--END--"]
	for lineIndex in 0..<lines.count {
		if lineIndex == 0 {
			promptAndAnswers.append(
				PromptAndAnswer(
					prompt: ["--START--"],
					answer: lines[lineIndex]
				)
			)
		} else {
			let windowSize = shortestUniqueWindowSize(in: lines, endingAt: lineIndex) ?? lineIndex
			promptAndAnswers.append(
				PromptAndAnswer(
					prompt: Array(lines.window(ofCount: windowSize, endingAt: lineIndex)!),
					answer: lines[lineIndex]
				)
			)
		}
	}

	return promptAndAnswers
		.uniqued()
		.map { promptAndAnswer in
			Note(
				front: .fragment(
					Array(
						(
							[.small(.text(song.title))]
							+
							promptAndAnswer.prompt
								.map(Node.text)
						)
						.interspersed(with: .br)
					)
				),
				back: .text(promptAndAnswer.answer)
			)
		}
}

private func quoteCSVFieldIfNeeded(_ value: String) -> String {
	guard !value.isEmpty else { return value }

	let quotingIsNeeded =  value.contains(",")
	|| value.contains("\"")
	|| value.first?.isWhitespace == true
	|| value.last?.isWhitespace == true
	|| value.contains { character in character.isNewline }

	return if quotingIsNeeded {
		"\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
	} else {
		value
	}
}

private func writeCSVRepresentation(of notes: [Note], to url: URL) throws {
	let fileContent = notes
		.map { note in
			"\(quoteCSVFieldIfNeeded(render(note.front))),\(quoteCSVFieldIfNeeded(render(note.back)))"
		}
		.joined(separator: "\n")
	try fileContent.write(
		to: url,
		atomically: true,
		encoding: .utf8
	)
}

private func writeNotesCSV(for song: Song, inDirectory directoryURL: URL) throws {
	try writeCSVRepresentation(
		of: notes(for: song),
		to: directoryURL
			.appending(component: song.title)
			.appendingPathExtension("csv")
	)
}

private func main() throws {
	let arguments = AnkiLyricsNoteGenerator.parseOrExit()

	for url in try textFileURLs(at: arguments.sourceDirectoryURL) {
		let title = url.deletingPathExtension().lastPathComponent

		let lines = try String(contentsOf: url, encoding: .utf8)
			.split(separator: "\n")
			.map { line in
				line.trimmingCharacters(in: .whitespacesAndNewlines)
			}
			.filter { line in
				!line.isEmpty
			}

		if lines.isEmpty {
			print("Skipping song \"\(title)\" (no lyrics found).")
			continue
		}

		try writeNotesCSV(
			for: Song(title: title, lyrics: lines),
			inDirectory: arguments.sourceDirectoryURL
		)

	}
}

try main()
