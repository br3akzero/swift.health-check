import Testing
import Foundation
import MCP
import GRDB
@testable import HealthCheck

@Test("search_documents matches text in chunks")
func searchDocumentsMatchesChunks() async throws {
    let db = try makeDB()
    let patientId = try insertPatient(db: db)
    let tools = QueryTools(db: db)
    let ts = timestamp()

    let docId = try await db.dbQueue.write { dbConn -> Int64 in
        let doc = try makeDocument(patientId: patientId).inserted(dbConn)
        try DocumentChunk(id: nil, documentId: doc.id!, chunkIndex: 0,
                          content: "Patient shows elevated glucose levels of 126 mg/dL",
                          pageNumber: 1, sectionHeading: "Lab Results",
                          tokenCount: 10, createdAt: ts).inserted(dbConn)
        try DocumentChunk(id: nil, documentId: doc.id!, chunkIndex: 1,
                          content: "Blood pressure is within normal range",
                          pageNumber: 1, sectionHeading: "Vitals",
                          tokenCount: 8, createdAt: ts).inserted(dbConn)
        return doc.id!
    }

    let result = try await tools.handle(CallTool.Parameters(name: "search_documents", arguments: [
        "query": .string("glucose"),
    ]))
    let arr = try #require(extractJSONArray(from: result))
    #expect(arr.count == 1)
    #expect((arr[0]["document_id"] as? Int64) == docId)
    #expect(arr[0]["section_heading"] as? String == "Lab Results")

    let excerpt = try #require(arr[0]["excerpt"] as? String)
    #expect(excerpt.lowercased().contains("glucose"))
}

@Test("get_document with include_chunks returns chunks")
func getDocumentWithChunks() async throws {
    let db = try makeDB()
    let patientId = try insertPatient(db: db)
    let tools = QueryTools(db: db)
    let ts = timestamp()

    let docId = try await db.dbQueue.write { dbConn -> Int64 in
        let doc = try makeDocument(patientId: patientId).inserted(dbConn)
        try DocumentSummary(id: nil, documentId: doc.id!, summaryType: "brief",
                            content: "Lab report summary", createdAt: ts).inserted(dbConn)
        try DocumentChunk(id: nil, documentId: doc.id!, chunkIndex: 0,
                          content: "Chunk one content", pageNumber: 1,
                          sectionHeading: nil, tokenCount: 5, createdAt: ts).inserted(dbConn)
        try DocumentChunk(id: nil, documentId: doc.id!, chunkIndex: 1,
                          content: "Chunk two content", pageNumber: 2,
                          sectionHeading: nil, tokenCount: 5, createdAt: ts).inserted(dbConn)
        return doc.id!
    }

    // Without chunks
    let resultNoChunks = try await tools.handle(CallTool.Parameters(name: "get_document", arguments: [
        "document_id": .int(Int(docId)),
    ]))
    let jsonNo = try #require(extractJSON(from: resultNoChunks))
    #expect(jsonNo["chunks"] == nil)
    let summaries = try #require(jsonNo["summaries"] as? [[String: Any]])
    #expect(summaries.count == 1)
    #expect(summaries[0]["content"] as? String == "Lab report summary")

    // With chunks
    let resultWithChunks = try await tools.handle(CallTool.Parameters(name: "get_document", arguments: [
        "document_id": .int(Int(docId)),
        "include_chunks": .bool(true),
    ]))
    let jsonWith = try #require(extractJSON(from: resultWithChunks))
    let chunks = try #require(jsonWith["chunks"] as? [[String: Any]])
    #expect(chunks.count == 2)
    #expect(chunks[0]["content"] as? String == "Chunk one content")
    #expect(chunks[1]["content"] as? String == "Chunk two content")
}

@Test("list_documents with type filter")
func listDocumentsFiltered() async throws {
    let db = try makeDB()
    let patientId = try insertPatient(db: db)
    let tools = QueryTools(db: db)
    let ts = timestamp()

    try await db.dbQueue.write { dbConn in
        try Document(id: nil, patientId: patientId, facilityId: nil, doctorId: nil,
                     filePath: "/tmp/lab.pdf", fileHash: "hash1", fileName: "lab.pdf",
                     documentDate: nil, documentType: "lab_report", tags: nil,
                     language: "en", pageCount: 1, processingStatus: "completed",
                     processingError: nil, rawText: nil, createdAt: ts, updatedAt: ts).inserted(dbConn)
        try Document(id: nil, patientId: patientId, facilityId: nil, doctorId: nil,
                     filePath: "/tmp/rx.pdf", fileHash: "hash2", fileName: "rx.pdf",
                     documentDate: nil, documentType: "prescription", tags: nil,
                     language: "en", pageCount: 1, processingStatus: "completed",
                     processingError: nil, rawText: nil, createdAt: ts, updatedAt: ts).inserted(dbConn)
    }

    let result = try await tools.handle(CallTool.Parameters(name: "list_documents", arguments: [
        "document_type": .string("lab_report"),
    ]))
    let arr = try #require(extractJSONArray(from: result))
    #expect(arr.count == 1)
    #expect(arr[0]["file_name"] as? String == "lab.pdf")
}
