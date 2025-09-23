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

private struct Note: Hashable {
	let front: Node
	let back: Node

	init(draft: Draft) {
		self.front = .fragment(
			Array(
				(
					[.small(.text(draft.title))]
					+
					draft.promptAndAnswer.prompt
						.map(Node.text)
				)
				.interspersed(with: .br)
			)
		)
		self.back = .text(draft.promptAndAnswer.answer)
	}

	struct Draft {
		let title: String
		let promptAndAnswer: PromptAndAnswer

		struct PromptAndAnswer: Hashable {
			let prompt: [String]
			let answer: String
		}
	}
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

private func noteDrafts(for song: Song) -> [Note.Draft] {
	var promptAndAnswers: [Note.Draft.PromptAndAnswer] = []

	let lines = song.lyrics + ["--END--"]
	for lineIndex in 0..<lines.count {
		if lineIndex == 0 {
			promptAndAnswers.append(
				Note.Draft.PromptAndAnswer(
					prompt: ["--START--"],
					answer: lines[lineIndex]
				)
			)
		} else {
			let windowSize = shortestUniqueWindowSize(in: lines, endingAt: lineIndex) ?? lineIndex
			promptAndAnswers.append(
				Note.Draft.PromptAndAnswer(
					prompt: Array(lines.window(ofCount: windowSize, endingAt: lineIndex)!),
					answer: lines[lineIndex]
				)
			)
		}
	}

	return promptAndAnswers
		.uniqued()
		.map { promptAndAnswer in
			Note.Draft(
				title: song.title,
				promptAndAnswer: promptAndAnswer
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

private func writeCSVRepresentation(of notes: [Note], inDirectory directoryURL: URL) throws {
	let fileContent = notes
		.map { note in
			"\(quoteCSVFieldIfNeeded(render(note.front))),\(quoteCSVFieldIfNeeded(render(note.back)))"
		}
		.joined(separator: "\n")
	try fileContent.write(
		to: directoryURL
			.appending(component: "_notes")
			.appendingPathExtension("csv"),
		atomically: true,
		encoding: .utf8
	)
}

private func main() throws {
	let arguments = AnkiLyricsNoteGenerator.parseOrExit()

	let notes = try textFileURLs(at: arguments.sourceDirectoryURL)
		.map { url in
			let title = url.deletingPathExtension().lastPathComponent

			let lines = try String(contentsOf: url, encoding: .utf8)
				.split(separator: "\n")
				.map(String.init)

			guard !lines.isEmpty else {
				fatalError("Song \"\(title)\" has no lines.")
			}

			return Song(title: title, lyrics: lines)
		}
		.flatMap(noteDrafts)
		.map(Note.init)

	try writeCSVRepresentation(
		of: notes,
		inDirectory: arguments.sourceDirectoryURL
	)
}

try main()
