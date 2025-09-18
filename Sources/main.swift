import Algorithms
import ArgumentParser
import Foundation
import Html
import OrderedCollections
import NonEmpty

struct AnkiLyricsNoteGenerator: ParsableArguments {
	@Argument(
		help: ArgumentHelp(
			"Directory containing plain-text lyrics (one file per song)",
			valueName: "source-directory"
		),
		completion: .directory, transform: URL.init(fileURLWithPath:)
	)
	var sourceDirectoryURL: URL
}

struct Note: Hashable {
	let front: Node
	let back: Node
}

struct Song {
	let title: String
	let lyrics: [NonEmpty<String>]
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

private func joinedTextNodesWithLineBreaks<S: Sequence, T: StringProtocol>(from strings: S) -> Node
where S.Element == NonEmpty<T> {
	return Node.fragment(
		Array(
			strings
				.map { string in
					Node.text(String(string))
				}
				.interspersed(with: .br)
		)
	)
}

private func notesWithDuplicateFrontsAnnotated(from notes: some Collection<Note>) -> [Note] {
	var remainingOccurrenceCountByFront = Dictionary(grouping: notes) { note in
		note.front
	}
		.mapValues(\.count)
		.filter { (_, occurrenceCount) in
			occurrenceCount > 1
		}

	var annotatedNotes: [Note] = []
	for note in notes.reversed() {
		if let remainingOccurrenceCount = remainingOccurrenceCountByFront[note.front] {
			annotatedNotes.insert(
				Note(
					front: Node.fragment([.small(.small(.text(String(remainingOccurrenceCount)))), .br, note.front]),
					back: note.back
				),
				at: 0
			)
			remainingOccurrenceCountByFront[note.front] = remainingOccurrenceCount - 1
		} else {
			annotatedNotes.insert(note, at: 0)
		}
	}

	return annotatedNotes
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

func notes(for lyrics: [NonEmpty<String>]) -> [Note] {
	let contextSize = min(2, lyrics.count)

	let prefixContextNotes = (1..<(contextSize)).map { prefixLength in
		let nextLineIndex = lyrics.index(lyrics.startIndex, offsetBy: prefixLength)
		return Note(
			front: joinedTextNodesWithLineBreaks(from: lyrics[lyrics.startIndex..<nextLineIndex]),
			back: .text(String(lyrics[nextLineIndex]))
		)
	}

	let slidingWindowNotes = lyrics
		.windows(ofCount: contextSize + 1)
		.map { window in
			Note(
				front: joinedTextNodesWithLineBreaks(from: window.dropLast()),
				back: .text(String(window.last!))
			)
		}

	return [
		Note(front: .text("--START--"), back: .text(String(lyrics.first!)))
	] + prefixContextNotes + slidingWindowNotes + [
		Note(
			front: joinedTextNodesWithLineBreaks(from: lyrics.dropFirst(lyrics.count - contextSize)),
			back: .text("--END--")
		)
	]
}

func writeNotesCSV(for song: Song, inDirectory directoryURL: URL) throws {
	try writeCSVRepresentation(
		of: notesWithDuplicateFrontsAnnotated(
				from: OrderedSet(
					notes(for: song.lyrics)
				)
			)
			.map { note in
				Note(
					front: .fragment([.small(.text(song.title)), .br, note.front]),
					back: note.back
				)
			},
		inDirectory: directoryURL
	)
}

func main() throws {
	let arguments = AnkiLyricsNoteGenerator.parseOrExit()

	let songs = try textFileURLs(at: arguments.sourceDirectoryURL)
		.map { url in
			Song(
				title: url.deletingPathExtension().lastPathComponent,
				lyrics: try String(contentsOf: url, encoding: .utf8)
					.split(separator: "\n")
					.compactMap { line in
						let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
						if let first = trimmedLine.first {
							var nonEmptyTrimmedLine = NonEmpty<String>(first)
							nonEmptyTrimmedLine.append(contentsOf: trimmedLine.dropFirst())
							return nonEmptyTrimmedLine
						} else {
							return nil
						}
					}
			)
		}

	for song in songs {
		try writeNotesCSV(for: song, inDirectory: arguments.sourceDirectoryURL)
	}
}

try main()
