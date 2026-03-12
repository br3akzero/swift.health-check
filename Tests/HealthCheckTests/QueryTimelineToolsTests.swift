import Testing
import Foundation
import MCP
import GRDB
@testable import HealthCheck

@Test("get_health_timeline returns all events sorted by date")
func timelineAllEvents() async throws {
    let db = try makeDB()
    let patientId = try insertPatient(db: db)
    let tools = QueryTools(db: db)
    let ts = timestamp()

    try await db.dbQueue.write { dbConn in
        try Encounter(id: nil, patientId: patientId, facilityId: nil, doctorId: nil,
                      encounterDate: "2026-01-10", encounterType: "office_visit",
                      chiefComplaint: nil, notes: nil, createdAt: ts).inserted(dbConn)
        try Diagnosis(id: nil, patientId: patientId, encounterId: nil, icdCode: nil,
                      description: "Hypertension", diagnosisDate: "2026-02-01",
                      status: "active", notes: nil, createdAt: ts).inserted(dbConn)
        try LabResult(id: nil, patientId: patientId, encounterId: nil, testName: "Glucose",
                      testCategory: nil, value: "126", numericValue: 126.0, unit: "mg/dL",
                      referenceRangeLow: nil, referenceRangeHigh: nil, referenceRangeText: nil,
                      flag: nil, testDate: "2025-12-01", notes: nil, createdAt: ts).inserted(dbConn)
        try Medication(id: nil, patientId: patientId, diagnosisId: nil, doctorId: nil,
                       name: "Lisinopril", atcCode: nil, ndcCode: nil, dosage: "10mg",
                       frequency: "daily", route: "oral", startDate: "2026-02-05",
                       endDate: nil, isActive: true, notes: nil, createdAt: ts).inserted(dbConn)
    }

    let result = try await tools.handle(CallTool.Parameters(name: "get_health_timeline", arguments: [
        "patient_id": .int(Int(patientId)),
    ]))
    let arr = try #require(extractJSONArray(from: result))
    #expect(arr.count == 4)

    // Verify sorted descending by date
    #expect(arr[0]["date"] as? String == "2026-02-05")
    #expect(arr[0]["event_type"] as? String == "medication")
    #expect(arr[1]["date"] as? String == "2026-02-01")
    #expect(arr[1]["event_type"] as? String == "diagnosis")
    #expect(arr[3]["date"] as? String == "2025-12-01")
    #expect(arr[3]["event_type"] as? String == "lab")
}

@Test("get_health_timeline event_types filter")
func timelineEventTypesFilter() async throws {
    let db = try makeDB()
    let patientId = try insertPatient(db: db)
    let tools = QueryTools(db: db)
    let ts = timestamp()

    try await db.dbQueue.write { dbConn in
        try Encounter(id: nil, patientId: patientId, facilityId: nil, doctorId: nil,
                      encounterDate: "2026-01-10", encounterType: "office_visit",
                      chiefComplaint: nil, notes: nil, createdAt: ts).inserted(dbConn)
        try Diagnosis(id: nil, patientId: patientId, encounterId: nil, icdCode: nil,
                      description: "Hypertension", diagnosisDate: "2026-02-01",
                      status: "active", notes: nil, createdAt: ts).inserted(dbConn)
        try LabResult(id: nil, patientId: patientId, encounterId: nil, testName: "Glucose",
                      testCategory: nil, value: "126", numericValue: 126.0, unit: "mg/dL",
                      referenceRangeLow: nil, referenceRangeHigh: nil, referenceRangeText: nil,
                      flag: nil, testDate: "2025-12-01", notes: nil, createdAt: ts).inserted(dbConn)
    }

    let result = try await tools.handle(CallTool.Parameters(name: "get_health_timeline", arguments: [
        "patient_id": .int(Int(patientId)),
        "event_types": .string("lab,diagnosis"),
    ]))
    let arr = try #require(extractJSONArray(from: result))
    #expect(arr.count == 2)

    let types = Set(arr.compactMap { $0["event_type"] as? String })
    #expect(types == ["lab", "diagnosis"])
}
