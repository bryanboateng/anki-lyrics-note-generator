import Algorithms
import ArgumentParser
import Foundation
import Html
import OrderedCollections
import TabularData
import UniformTypeIdentifiers

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
	let urls = try FileManager.default.contentsOfDirectory(
		at: directoryURL,
		includingPropertiesForKeys: [.contentTypeKey],
		options: [.skipsHiddenFiles, .skipsPackageDescendants]
	)
	return urls.filter { url in
		(try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false &&
		(try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .text)) == true
	}
}

private func joinedTextNodesWithLineBreaks<S: Sequence>(from strings: S) -> Node
where S.Element: StringProtocol {
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

private func writeCSVRepresentation(of notes: [Note], inDirectory directoryURL: URL) throws {
	var notesDataFrame = DataFrame()
	notesDataFrame.append(column: Column(name: "front", contents: notes.map { render($0.front) }))
	notesDataFrame.append(column: Column(name: "back", contents: notes.map { render($0.back) }))

	try notesDataFrame.writeCSV(
		to: directoryURL
			.appending(component: "_notes")
			.appendingPathExtension("csv"),
		options: .init(includesHeader: false)
	)
}

func writeNotesCSV(for song: Song, inDirectory directoryURL: URL) throws {
	let title = song.title
	let lyrics = song.lyrics

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

	let notes: [Note] = [
		Note(front: .text("--START--"), back: .text(String(lyrics.first!)))
	] + prefixContextNotes + slidingWindowNotes + [
		Note(
			front: joinedTextNodesWithLineBreaks(from: lyrics.dropFirst(lyrics.count - contextSize)),
			back: .text("--END--")
		)
	]

	try writeCSVRepresentation(
		of: notesWithDuplicateFrontsAnnotated(from: OrderedSet(notes))
			.map { note in
				Note(
					front: .fragment([.small(.text(title)), .br, note.front]),
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
					.map { line in line.trimmingCharacters(in: .whitespacesAndNewlines) }
			)
		}

	for song in songs {
		try writeNotesCSV(for: song, inDirectory: arguments.sourceDirectoryURL)
	}
}

try main()
