struct DocumentExtractionResult {
    let text: String
    let confidence: Float
    let tables: [DocumentTable]
    let lists: [DocumentList]
    let paragraphs: [String]
    let detectedData: [DetectedDataItem]

    static let empty = DocumentExtractionResult(
        text: "", confidence: 0.0, tables: [], lists: [], paragraphs: [], detectedData: []
    )
}
