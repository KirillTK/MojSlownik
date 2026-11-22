import Foundation
import CoreGraphics
import ImageIO
import UIKit
import Vision

struct ScannedTextLine: Identifiable, Equatable {
    var id = UUID()
    let text: String
    let bounds: CGRect
}

struct ScannedTextBlock: Identifiable, Equatable {
    let id: String
    let lines: [ScannedTextLine]

    var bounds: CGRect {
        guard let first = lines.first else { return .zero }
        return lines.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
    }

    var text: String { ScannedTextSelection.text(from: lines) }
}

enum ScannedTextSelection {
    /// Returns nonempty recognized items in visual reading order, retaining repeated lines.
    static func text(from lines: [ScannedTextLine]) -> String {
        lines
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                if $0.bounds.minY != $1.bounds.minY { return $0.bounds.minY < $1.bounds.minY }
                if $0.bounds.minX != $1.bounds.minX { return $0.bounds.minX < $1.bounds.minX }
                return $0.id.uuidString < $1.id.uuidString
            }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
    }
}

enum ScannedTextBlockBuilder {
    private static let maximumLinesPerBlock = 3

    static func build(from lines: [ScannedTextLine]) -> [ScannedTextBlock] {
        let usable = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted(by: lineOrder)
        guard !usable.isEmpty else { return [] }

        var parent = Array(usable.indices)
        var componentSizes = Array(repeating: 1, count: usable.count)
        for left in usable.indices {
            for right in usable.indices where right > left {
                let leftRoot = root(of: left, parents: &parent)
                let rightRoot = root(of: right, parents: &parent)
                guard leftRoot != rightRoot,
                      componentSizes[leftRoot] + componentSizes[rightRoot] <= maximumLinesPerBlock,
                      shouldGroup(usable[left].bounds, usable[right].bounds) else { continue }
                parent[rightRoot] = leftRoot
                componentSizes[leftRoot] += componentSizes[rightRoot]
                componentSizes[rightRoot] = 0
            }
        }

        var groups: [Int: [ScannedTextLine]] = [:]
        for index in usable.indices {
            groups[root(of: index, parents: &parent), default: []].append(usable[index])
        }

        return groups.values.map { group in
            let orderedLines = group.sorted(by: lineOrder)
            let stableMemberIDs = orderedLines.map { $0.id.uuidString }.sorted()
            return ScannedTextBlock(id: stableMemberIDs.joined(separator: ":"), lines: orderedLines)
        }
        .sorted {
            if $0.bounds.minY != $1.bounds.minY { return $0.bounds.minY < $1.bounds.minY }
            if $0.bounds.minX != $1.bounds.minX { return $0.bounds.minX < $1.bounds.minX }
            return $0.id < $1.id
        }
    }

    static func toggled(_ blockID: String, in selection: Set<String>) -> Set<String> {
        var next = selection
        if !next.insert(blockID).inserted { next.remove(blockID) }
        return next
    }

    static func selectedText(from blocks: [ScannedTextBlock], IDs: Set<String>) -> String {
        blocks.filter { IDs.contains($0.id) }.map(\.text).joined(separator: "\n")
    }

    private static func shouldGroup(_ first: CGRect, _ second: CGRect) -> Bool {
        let lineHeight = max(first.height, second.height)
        let verticalGap = max(0, max(first.minY, second.minY) - min(first.maxY, second.maxY))
        guard verticalGap <= lineHeight * 1.35 else { return false }

        let horizontalGap = max(0, max(first.minX, second.minX) - min(first.maxX, second.maxX))
        return horizontalGap <= lineHeight * 1.5
    }

    private static func lineOrder(_ first: ScannedTextLine, _ second: ScannedTextLine) -> Bool {
        if first.bounds.minY != second.bounds.minY { return first.bounds.minY < second.bounds.minY }
        if first.bounds.minX != second.bounds.minX { return first.bounds.minX < second.bounds.minX }
        return first.id.uuidString < second.id.uuidString
    }

    private static func root(of index: Int, parents: inout [Int]) -> Int {
        if parents[index] != index { parents[index] = root(of: parents[index], parents: &parents) }
        return parents[index]
    }

}

enum ScannedImageTextRecognizer {
    enum RecognitionError: LocalizedError {
        case imageUnavailable

        var errorDescription: String? { String(localized: "Couldn’t read the camera frame image.") }
    }

    static func recognize(image: UIImage, viewportSize: CGSize,
                          languages: [String] = ["pl-PL", "ru-RU"]) async throws -> [ScannedTextLine] {
        guard let cgImage = image.cgImage else { throw RecognitionError.imageUnavailable }
        let orientation = image.imageOrientation.cgImageOrientation
        return try await Task.detached(priority: .userInitiated) {
            try recognize(cgImage: cgImage, orientation: orientation, viewportSize: viewportSize,
                           languages: languages)
        }.value
    }

    /// OCR codes of a workspace's languages (studied first), without repeats.
    static func ocrLanguages(for pair: LanguagePair) -> [String] {
        var codes = [pair.term.ocrCode]
        if pair.translation.ocrCode != pair.term.ocrCode { codes.append(pair.translation.ocrCode) }
        return codes
    }

    /// DataScanner accepts a language when the device supports any locale of the same language.
    static func dataScannerLanguages(wanted: [String], supported: [String]) -> [String] {
        wanted.filter { code in supported.contains { $0.hasPrefix(String(code.prefix(2))) } }
    }

    /// Wanted OCR codes the device supports, in order; empty means automatic detection.
    static func recognitionLanguages(wanted: [String], supported: [String]) -> [String] {
        wanted.filter(supported.contains)
    }

    static func recognize(cgImage: CGImage, orientation: CGImagePropertyOrientation,
                          viewportSize: CGSize, languages: [String] = ["pl-PL", "ru-RU"]) throws -> [ScannedTextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let preferred = recognitionLanguages(wanted: languages, supported: supported)
        if preferred.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = preferred
        }

        try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
        let imageSize = orientedImageSize(width: cgImage.width, height: cgImage.height, orientation: orientation)
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let bounds = aspectFillRect(observation.boundingBox, imageSize: imageSize, viewportSize: viewportSize)
            guard !bounds.isNull, !bounds.isEmpty else { return nil }
            return ScannedTextLine(
                id: observation.uuid,
                text: text,
                bounds: bounds
            )
        }
    }

    static func aspectFillRect(_ normalizedVisionRect: CGRect, imageSize: CGSize, viewportSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0 else { return .zero }
        let scale = max(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offsetX = (viewportSize.width - displayedSize.width) / 2
        let offsetY = (viewportSize.height - displayedSize.height) / 2
        let imageRect = CGRect(
            x: normalizedVisionRect.minX * imageSize.width,
            y: (1 - normalizedVisionRect.maxY) * imageSize.height,
            width: normalizedVisionRect.width * imageSize.width,
            height: normalizedVisionRect.height * imageSize.height
        )
        let mappedRect = CGRect(x: imageRect.minX * scale + offsetX, y: imageRect.minY * scale + offsetY,
                                width: imageRect.width * scale, height: imageRect.height * scale)
        return mappedRect.intersection(CGRect(origin: .zero, size: viewportSize))
    }

    private static func orientedImageSize(width: Int, height: Int, orientation: CGImagePropertyOrientation) -> CGSize {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            CGSize(width: height, height: width)
        default:
            CGSize(width: width, height: height)
        }
    }
}

private extension UIImage.Orientation {
    var cgImageOrientation: CGImagePropertyOrientation {
        switch self {
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        case .up: .up
        @unknown default: .up
        }
    }
}

/// Splits a recognized line into words and the text between them, keeping punctuation.
enum ScannedTextTokenizer {
    enum Token: Equatable {
        case word(String)
        case text(String)
    }

    private static let wordCharacters = CharacterSet.alphanumerics.union(
        .init(charactersIn: "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ'-")
    )

    static func tokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        var bufferingWord: Bool?

        for character in text {
            let isWordCharacter = character.unicodeScalars.allSatisfy(wordCharacters.contains)
            if bufferingWord != nil && bufferingWord != isWordCharacter {
                append(buffer, isWord: bufferingWord == true, to: &tokens)
                buffer = ""
            }
            bufferingWord = isWordCharacter
            buffer.append(character)
        }
        append(buffer, isWord: bufferingWord == true, to: &tokens)
        return tokens
    }

    static func words(in text: String) -> [String] {
        tokens(in: text).compactMap {
            guard case let .word(word) = $0, word.count > 1 else { return nil }
            return word
        }
    }

    /// Joins only explicit end-of-line hyphenation produced by OCR.
    /// Regular compound-word hyphens and dash punctuation remain untouched.
    static func joiningLineBreakHyphenation(in text: String) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard isLetter(character) else {
                result.append(character)
                index = text.index(after: index)
                continue
            }

            let hyphenIndex = text.index(after: index)
            guard hyphenIndex < text.endIndex,
                  isLineBreakHyphen(text[hyphenIndex]) else {
                result.append(character)
                index = hyphenIndex
                continue
            }

            var nextLetterIndex = text.index(after: hyphenIndex)
            guard nextLetterIndex < text.endIndex else {
                result.append(character)
                index = hyphenIndex
                continue
            }
            // Swift treats CRLF as one Character, so LF and CRLF are both single separators.
            guard text[nextLetterIndex] == "\n" || text[nextLetterIndex] == "\r\n" else {
                result.append(character)
                index = hyphenIndex
                continue
            }
            nextLetterIndex = text.index(after: nextLetterIndex)

            guard nextLetterIndex < text.endIndex, isLetter(text[nextLetterIndex]) else {
                result.append(character)
                index = hyphenIndex
                continue
            }

            result.append(character)
            index = nextLetterIndex
        }
        return result
    }

    private static func append(_ value: String, isWord: Bool, to tokens: inout [Token]) {
        guard !value.isEmpty else { return }
        tokens.append(isWord ? .word(value) : .text(value))
    }

    private static func isLetter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(CharacterSet.letters.contains)
    }

    private static func isLineBreakHyphen(_ character: Character) -> Bool {
        character == "-" || character == "\u{00AD}"
    }
}
