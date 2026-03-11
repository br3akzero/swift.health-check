import GRDB

struct VitalSign: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "vital_sign"

    var id: Int64?
    var patientId: Int64
    var encounterId: Int64?
    var vitalType: String
    var value: String
    var numericValue: Double?
    var numericValue2: Double?
    var unit: String?
    var measuredDate: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case encounterId = "encounter_id"
        case vitalType = "vital_type"
        case value
        case numericValue = "numeric_value"
        case numericValue2 = "numeric_value_2"
        case unit
        case measuredDate = "measured_date"
        case createdAt = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
