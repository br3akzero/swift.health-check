import Testing
import Foundation
import MCP
import GRDB
@testable import HealthCheck

@Test("get_patient_summary returns all sections")
func patientSummaryAllSections() async throws {
    let db = try makeDB()
    let patientId = try insertPatient(db: db)
    let tools = QueryTools(db: db)
    let ts = timestamp()

    try await db.dbQueue.write { dbConn in
        try Diagnosis(id: nil, patientId: patientId, encounterId: nil, icdCode: "E11.9",
                      description: "Type 2 diabetes", diagnosisDate: "2026-01-15",
                      status: "active", notes: nil, createdAt: ts).inserted(dbConn)
        try Medication(id: nil, patientId: patientId, diagnosisId: nil, doctorId: nil,
                       name: "Metformin", atcCode: nil, ndcCode: nil, dosage: "500mg",
                       frequency: "daily", route: "oral", startDate: "2026-01-01",
                       endDate: nil, isActive: true, notes: nil, createdAt: ts).inserted(dbConn)
        try Allergy(id: nil, patientId: patientId, allergen: "Penicillin",
                    allergenType: "drug", reaction: "rash", severity: "moderate",
                    onsetDate: nil, status: "active", createdAt: ts).inserted(dbConn)
        try Encounter(id: nil, patientId: patientId, facilityId: nil, doctorId: nil,
                      encounterDate: "2026-01-10", encounterType: "office_visit",
                      chiefComplaint: "Checkup", notes: nil, createdAt: ts).inserted(dbConn)
        try LabResult(id: nil, patientId: patientId, encounterId: nil, testName: "Glucose",
                      testCategory: nil, value: "126 mg/dL", numericValue: 126.0,
                      unit: "mg/dL", referenceRangeLow: nil, referenceRangeHigh: nil,
                      referenceRangeText: nil, flag: "high", testDate: "2026-01-10",
                      notes: nil, createdAt: ts).inserted(dbConn)
    }

    let result = try await tools.handle(CallTool.Parameters(name: "get_patient_summary", arguments: [
        "patient_id": .int(Int(patientId)),
    ]))
    let json = try #require(extractJSON(from: result))

    #expect(json["first_name"] as? String == "John")
    #expect(json["last_name"] as? String == "Doe")

    let diagnoses = try #require(json["active_diagnoses"] as? [[String: Any]])
    #expect(diagnoses.count == 1)
    #expect(diagnoses[0]["description"] as? String == "Type 2 diabetes")

    let meds = try #require(json["current_medications"] as? [[String: Any]])
    #expect(meds.count == 1)
    #expect(meds[0]["name"] as? String == "Metformin")

    let allergies = try #require(json["allergies"] as? [[String: Any]])
    #expect(allergies.count == 1)
    #expect(allergies[0]["allergen"] as? String == "Penicillin")

    let encounters = try #require(json["recent_encounters"] as? [[String: Any]])
    #expect(encounters.count == 1)

    let labs = try #require(json["recent_labs"] as? [[String: Any]])
    #expect(labs.count == 1)
    #expect(labs[0]["test_name"] as? String == "Glucose")
}

@Test("get_patient_summary not found returns error")
func patientSummaryNotFound() async throws {
    let db = try makeDB()
    let tools = QueryTools(db: db)

    let result = try await tools.handle(CallTool.Parameters(name: "get_patient_summary", arguments: [
        "patient_id": .int(999),
    ]))
    let json = try #require(extractJSON(from: result))
    #expect(json["error"] as? String == "Patient not found")
}

@Test("list_patients returns all ordered by last name")
func listPatientsOrdered() async throws {
    let db = try makeDB()
    let tools = QueryTools(db: db)
    let ts = timestamp()

    try await db.dbQueue.write { dbConn in
        try Patient(id: nil, firstName: "Zara", lastName: "Wilson", dateOfBirth: nil,
                    gender: nil, bloodType: nil, createdAt: ts, updatedAt: ts).inserted(dbConn)
        try Patient(id: nil, firstName: "Alice", lastName: "Adams", dateOfBirth: nil,
                    gender: nil, bloodType: nil, createdAt: ts, updatedAt: ts).inserted(dbConn)
    }

    let result = try await tools.handle(CallTool.Parameters(name: "list_patients", arguments: [:]))
    let arr = try #require(extractJSONArray(from: result))
    #expect(arr.count == 2)
    #expect(arr[0]["last_name"] as? String == "Adams")
    #expect(arr[1]["last_name"] as? String == "Wilson")
}
