import MCP
import GRDB
import Foundation

struct IngestTools {
    let db: DatabaseManager

    var tools: [Tool] {
        [
            Tool(
                name: "ingest_document",
                description: "Ingests a PDF document: extracts text (PDFKit + Vision OCR), reconciles, chunks, and stores. Returns document ID and status. Detects duplicates by SHA-256 hash.",
                inputSchema: schema([
                    "file_path": .object([
                        "type": "string",
                        "description": "Absolute path to the PDF file"
                    ]),
                    "patient_id": .object([
                        "type": "integer",
                        "description": "ID of the patient this document belongs to"
                    ])
                ])
            ),
            Tool(
                name: "get_document_text",
                description: "Returns the raw text and chunks for a document. Use this to read document content before extracting clinical entities.",
                inputSchema: schema([
                    "document_id": .object([
                        "type": "integer",
                        "description": "ID of the document to retrieve text for"
                    ])
                ])
            ),
        ]
    }

    func handle(_ params: CallTool.Parameters) async throws -> CallTool.Result? {
        switch params.name {
        case "ingest_document":
            return try await ingestDocument(params)
        case "get_document_text":
            return try await getDocumentText(params)
        default:
            return nil
        }
    }
}

// MARK: - Tool Handlers

private extension IngestTools {
    func ingestDocument(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let args = params.arguments,
              let filePath = stringArg(args, "file_path"),
              let patientId = intArg(args, "patient_id") else {
            return .init(content: [.text("Missing required parameters: file_path (string), patient_id (integer)")], isError: true)
        }

        // Validate file
        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            return .init(content: [.text("File not found: \(filePath)")], isError: true)
        }
        guard fileURL.pathExtension.lowercased() == "pdf" else {
            return .init(content: [.text("File is not a PDF: \(fileURL.lastPathComponent)")], isError: true)
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
           let size = attrs[.size] as? Int64, size > 250 * 1024 * 1024 {
            return .init(content: [.text("File too large (\(size / 1024 / 1024) MB). Maximum is 250 MB.")], isError: true)
        }

        // Validate patient exists
        let patientExists = try await db.dbQueue.read { db in
            try Patient.fetchOne(db, key: patientId) != nil
        }
        guard patientExists else {
            return .init(content: [.text("Patient not found: \(patientId)")], isError: true)
        }

        let service = IngestService(db: db)
        let result: IngestResult
        do {
            result = try await service.ingest(filePath: filePath, patientId: patientId)
        } catch {
            // Try to mark the document as failed if it was created before the error
            try? await db.dbQueue.write { db in
                let errorMessage = "\(error)"
                try db.execute(
                    sql: """
                        UPDATE document SET processing_status = 'failed', processing_error = ?, updated_at = ?
                        WHERE file_path = ? AND processing_status = 'processing'
                        """,
                    arguments: [errorMessage, ISO8601DateFormatter().string(from: .now), filePath]
                )
            }
            return .init(content: [.text("Ingestion failed: \(error)")], isError: true)
        }

        let response: [String: Any] = [
            "document_id": result.documentId,
            "page_count": result.pageCount,
            "chunk_count": result.chunkCount,
            "status": result.status
        ]

        let data = try JSONSerialization.data(withJSONObject: response, options: .prettyPrinted)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        return .init(content: [.text(json)], isError: false)
    }

    func getDocumentText(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let args = params.arguments,
              let docId = intArg(args, "document_id") else {
            return .init(content: [.text("Missing required parameter: document_id (integer)")], isError: true)
        }

        let document = try await db.dbQueue.read { db in
            try Document.fetchOne(db, key: docId)
        }

        guard let document else {
            return .init(content: [.text("Document not found: \(docId)")], isError: true)
        }

        let chunks = try await db.dbQueue.read { db in
            try DocumentChunk
                .filter(Column("document_id") == docId)
                .order(Column("chunk_index"))
                .fetchAll(db)
        }

        var response: [String: Any] = [
            "document_id": docId,
            "file_name": document.fileName,
            "document_type": document.documentType,
            "processing_status": document.processingStatus,
            "page_count": document.pageCount,
        ]

        if let rawText = document.rawText {
            response["raw_text"] = rawText
        }

        let chunkData: [[String: Any]] = chunks.map { chunk in
            var entry: [String: Any] = [
                "chunk_index": chunk.chunkIndex,
                "content": chunk.content,
                "token_count": chunk.tokenCount,
            ]
            if let page = chunk.pageNumber { entry["page_number"] = page }
            if let heading = chunk.sectionHeading { entry["section_heading"] = heading }
            return entry
        }
        response["chunks"] = chunkData

        let data = try JSONSerialization.data(withJSONObject: response, options: .prettyPrinted)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        return .init(content: [.text(json)], isError: false)
    }
}
