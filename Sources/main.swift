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

struct Song {
	let title: String
	let lyrics: [String]
}

struct NumberedLine {
	let i: Int
	let text: String
}

struct CoupletStep {
	let firstLine: NumberedLine
	let secondLine: NumberedLine
	let next: Next

	var frontKey: FrontKey {
		.init(from: self)
	}

	var nextKey: NextKey {
		switch self.next {
		case .line(let l): .line(l.text)
		case .end: .end
		}
	}

	enum Next {
		case line(NumberedLine)
		case end
	}

	struct FrontKey: Hashable {
		let firstText: String
		let secondText: String

		init(_ first: NumberedLine, _ second: NumberedLine) {
			self.firstText = first.text
			self.secondText = second.text
		}

		init(from step: CoupletStep) {
			self.init(step.firstLine, step.secondLine)
		}
	}

	enum NextKey: Hashable {
		case line(String)
		case end
	}
}

struct Note: Hashable {
	let front: Node
	let back: Node

	init(draft: Draft) {
		let a: Optional<Node> = if let disambiguationIndex = draft.disambiguationIndex {
			.small(.text(String(repeating: "★", count: disambiguationIndex)))
		} else {
			nil
		}
		self.front = .fragment(
			Array(
				[
					.small(.text(draft.title)),
					a,
					draft.front
				]
					.compacted()
					.interspersed(with: .br)
			)
		)
		self.back = draft.back
	}

	struct Draft {
		let title: String
		let disambiguationIndex: Int?
		let front: Node
		let back: Node
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

func node(for numberedLine: NumberedLine) -> Node {
	.fragment([
		.small(.small(.text((numberedLine.i + 1).formatted()))),
		.br,
		.text(numberedLine.text)
	])
}

func noteDrafts(for song: Song) -> [Note.Draft] {
	let numberedLines = song.lyrics
		.enumerated()
		.map(NumberedLine.init)

	let coupletSteps = numberedLines
		.windows(ofCount: 3)
		.map { window in
			CoupletStep(
				firstLine: window.first!,
				secondLine: window[window.index(after: window.startIndex)],
				next: .line(window.last!)
			)
		}
	+ [
		CoupletStep(
			firstLine: numberedLines[numberedLines.index(numberedLines.endIndex, offsetBy: -2)],
			secondLine: numberedLines.last!,
			next: .end
		)
	]

	let grouped = Dictionary(grouping: coupletSteps) { step in step.frontKey }

	var disambiguationIndexByFront: [CoupletStep.FrontKey: [CoupletStep.NextKey: Int]] = [:]
	for (front, steps) in grouped {
		var disambiguationIndexForNextKey: [CoupletStep.NextKey: Int] = [:]
		var nextDisambiguationIndex = 1

		for step in steps {
			let nextKey = step.nextKey
			if disambiguationIndexForNextKey[nextKey] == nil {
				disambiguationIndexForNextKey[nextKey] = nextDisambiguationIndex
				nextDisambiguationIndex += 1
			}
		}

		if disambiguationIndexForNextKey.count >= 2 {
			disambiguationIndexByFront[front] = disambiguationIndexForNextKey
		}
	}

	let coupletStepNoteDrafts: [Note.Draft] = coupletSteps.map { currentStep in
		return Note.Draft(
			title: song.title,
			disambiguationIndex: disambiguationIndexByFront[currentStep.frontKey]?[currentStep.nextKey],
			front: .fragment([
				node(for: currentStep.firstLine),
				.br,
				node(for: currentStep.secondLine)
			]),
			back: {
				switch currentStep.next {
				case .line(let line): node(for: line)
				case .end: .text("--END--")
				}
			}()
		)
	}


	return [
		Note.Draft (
			title: song.title,
			disambiguationIndex: nil,
			front: .text("--START--"),
			back: node(for: numberedLines[0])
		),
		Note.Draft (
			title: song.title,
			disambiguationIndex: nil,
			front: node(for: numberedLines[0]),
			back: node(for: numberedLines[1])
		)
	] + coupletStepNoteDrafts

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

func main() throws {
	let arguments = AnkiLyricsNoteGenerator.parseOrExit()

	let notes = try textFileURLs(at: arguments.sourceDirectoryURL)
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
		.flatMap(noteDrafts)
		.map(Note.init)

	try writeCSVRepresentation(
		of: notes,
		inDirectory: arguments.sourceDirectoryURL
	)
}

try main()
