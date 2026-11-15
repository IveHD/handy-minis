import CoreGraphics
import Vision

struct CaptureTextLine {
    let characters: [Character]
    let boxes: [CGRect]
    let bounds: CGRect

    static func recognize(in image: CGImage, frame: CGRect) throws -> [Self] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"].filter(supported.contains)
        try VNImageRequestHandler(cgImage: image).perform([request])

        func convert(_ box: CGRect) -> CGRect {
            CGRect(x: frame.minX + box.minX * frame.width,
                   y: frame.minY + (1 - box.maxY) * frame.height,
                   width: box.width * frame.width, height: box.height * frame.height)
        }

        let lines = (request.results ?? []).compactMap { observation -> Self? in
            guard let candidate = observation.topCandidates(1).first, !candidate.string.isEmpty else { return nil }
            let string = candidate.string
            let bounds = convert(observation.boundingBox)
            let indices = Array(string.indices)
            let boxes = indices.map { index -> CGRect? in
                guard let box = try? candidate.boundingBox(for: index..<string.index(after: index)) else { return nil }
                return convert(box.boundingBox)
            }

            // Accurate Vision results can share one box across a word or a Chinese line.
            // Subdivide shared boxes so dragging can select a substring.
            var characters: [CGRect] = []
            var start = 0
            while start < boxes.count {
                var end = start + 1
                while end < boxes.count, boxes[end] == boxes[start] { end += 1 }
                let box = boxes[start] ?? CGRect(x: bounds.minX + bounds.width * CGFloat(start) / CGFloat(boxes.count),
                                                y: bounds.minY,
                                                width: bounds.width * CGFloat(end - start) / CGFloat(boxes.count),
                                                height: bounds.height)
                let width = box.width / CGFloat(end - start)
                for index in start..<end {
                    characters.append(CGRect(x: box.minX + CGFloat(index - start) * width,
                                             y: box.minY, width: width, height: box.height))
                }
                start = end
            }
            return Self(characters: Array(string), boxes: characters, bounds: bounds)
        }
        var rows: [[Self]] = []
        for line in lines.sorted(by: { $0.bounds.midY < $1.bounds.midY }) {
            if let previous = rows.last?.first,
               abs(previous.bounds.midY - line.bounds.midY) < min(previous.bounds.height, line.bounds.height) / 2 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { $0.sorted { $0.bounds.minX < $1.bounds.minX } }
    }
}

struct CaptureTextPosition: Comparable {
    let line: Int
    let character: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.line, lhs.character) < (rhs.line, rhs.character)
    }
}
