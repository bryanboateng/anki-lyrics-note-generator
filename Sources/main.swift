import Algorithms
import ArgumentParser
import Foundation
import Html
import OrderedCollections

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
	let lyrics: [String]
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

private func joinedTextNodesWithLineBreaks<S: Sequence>(from strings: S) -> Node
where S.Element == String {
	return Node.fragment(
		Array(
			strings
				.map(Node.text)
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


func notes(for lyrics: [String]) -> [Note] {
	let slidingWindowNotes = lyrics
		.windows(ofCount: 3)
		.map { window in
			Note(
				front: joinedTextNodesWithLineBreaks(from: window.dropLast()),
				back: .text(window.last!)
			)
		}

	return [
		Note(front: .text("--START--"), back: .text(lyrics[0])),
		Note(
			front: .text(lyrics[0]),
			back: .text(lyrics[1])
		)
	] + slidingWindowNotes + [
		Note(
			front: joinedTextNodesWithLineBreaks(from: lyrics.suffix(2)),
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
			let title = url.deletingPathExtension().lastPathComponent

			let lines = try String(contentsOf: url, encoding: .utf8)
				.split(separator: "\n")
				.map(String.init)

			guard lines.count >= 2 else {
				fatalError("Song \"\(title)\" has less than two lines.")
			}

			return Song(title: title, lyrics: lines)
		}

	for song in songs {
		try writeNotesCSV(for: song, inDirectory: arguments.sourceDirectoryURL)
	}
}

try main()
