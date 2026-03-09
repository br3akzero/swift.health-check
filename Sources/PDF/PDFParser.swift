import PDFKit
import Vision

public struct PDFParser {
    public init() {}

    public func extract(from url: URL) throws -> AsyncThrowingStream<PageExtraction, Error> {
        guard let document = PDFDocument(url: url) else {
            throw PDFParserError.cannotOpenDocument
        }

        let actor = PDFDocumentActor(document)

        return AsyncThrowingStream { continuation in
            Task {
                let pageCount = await actor.pageCount

                for i in 0..<pageCount {
                    let pdfKitText = await actor.pageText(at: i) ?? ""

                    do {
                        let cgImage = try await actor.renderPageToImage(at: i)
                        let result = try await Self.extractDocumentVisionAPI(from: cgImage)

                        continuation.yield(PageExtraction(
                            pageNumber: i + 1,
                            pdfKitText: pdfKitText,
                            ocrText: result.text,
                            ocrConfidence: result.confidence,
                            tables: result.tables,
                            lists: result.lists,
                            paragraphs: result.paragraphs,
                            detectedData: result.detectedData
                        ))
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
        }
    }

    private static func extractDocumentVisionAPI(from cgImage: CGImage) async throws -> DocumentExtractionResult {
        let request = RecognizeDocumentsRequest()
        let observations = try await request.perform(on: cgImage)

        guard let doc = observations.first?.document else {
            return DocumentExtractionResult.empty
        }

        let text = doc.paragraphs.map { $0.transcript }.joined(separator: "\n")
        let paragraphs = doc.paragraphs.map { $0.transcript }

        let tables: [DocumentTable] = doc.tables.map { table in
            let rows = table.rows.map { row in
                row.map { $0.content.paragraphs.map { $0.transcript }.joined(separator: " ") }
            }
            return DocumentTable(rows: rows)
        }

        let lists: [DocumentList] = doc.lists.map { list in
            DocumentList(items: list.items.map { $0.content.paragraphs.map { $0.transcript }.joined(separator: " ") })
        }

        let detectedData: [DetectedDataItem] = []

        return DocumentExtractionResult(
            text: text,
            confidence: 1.0,
            tables: tables,
            lists: lists,
            paragraphs: paragraphs,
            detectedData: detectedData
        )
    }
}