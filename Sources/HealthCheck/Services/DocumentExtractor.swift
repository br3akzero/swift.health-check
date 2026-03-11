import Foundation
import PDF

protocol DocumentExtractor: Sendable {
    func extract(from url: URL) async throws -> [ReconciledPage]
}

struct PDFDocumentExtractor: DocumentExtractor {
    func extract(from url: URL) async throws -> [ReconciledPage] {
        let parser = PDFParser()
        let reconciler = TextReconciler()
        let stream = try parser.extract(from: url)

        var pages: [ReconciledPage] = []
        for try await extraction in stream {
            let reconciled = reconciler.reconcile(page: extraction)
            pages.append(reconciled)
        }

        return pages
    }
}
