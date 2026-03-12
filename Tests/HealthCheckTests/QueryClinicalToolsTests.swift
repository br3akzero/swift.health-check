import Testing
import Foundation
import MCP
import GRDB
@testable import HealthCheck

@Test("get_lab_history with test_name filter")
func labHistoryFiltered() async throws {
    let db = try makeDB()
    let patientId = try insertPatient(db: db)
    let tools = QueryTools(db: db)
    let ts = timestamp()

    try await db.dbQueue.write { dbConn in
        try LabResult(id: nil, patientId: patientId, encounterId: nil, testName: "Glucose",
                      testCategory: nil, value: "126", numericValue: 126.0, unit: "mg/dL",
                      referenceRangeLow: nil, referenceRangeHigh: nil, referenceRangeText: nil,
                      flag: "high", testDate: "2026-01-15", notes: nil, createdAt: ts).inserted(dbConn)
        try LabResult(id: nil, patientId: patientId, encounterId: nil, testName: "HbA1c",
                      testCategory: nil, value: "7.2", numericValue: 7.2, unit: "%",
                      referenceRangeLow: nil, referenceRangeHigh: nil, referenceRangeText: nil,
                      flag: nil, testDate: "2026-01-15", notes: nil, createdAt: ts).inserted(dbConn)
        try LabResult(id: nil, patientId: patientId, encounterId: nil, testName: "Glucose",
                      testCategory: nil, value: "110", numericValue: 110.0, unit: "mg/dL",
                      referenceRangeLow: nil, referenceRangeHigh: nil, referenceRangeText: nil,
                      flag: nil, testDate: "2026-02-15", notes: nil, createdAt: ts).inserted(dbConn)
    }

    let result = try await tools.handle(CallTool.Parameters(name: "get_lab_history", arguments: [
        "patient_id": .int(Int(patientId)),
        "test_name": .string("Glucose"),
    ]))
    let arr = try #require(extractJSONArray(from: result))
    #expect(arr.count == 2)
    #expect(arr.allSatisfy { $0["test_name"] as? String == "Glucose" })
}

@Test("get_medication_list active_only filter")
func medicationListActiveOnly() async throws {
    let db = try makeDB()
    let patientId = try insertPatient(db: db)
    let tools = QueryTools(db: db)
    let ts = timestamp()

    try await db.dbQueue.write { dbConn in
        try Medication(id: nil, patientId: patientId, diagnosisId: nil, doctorId: nil,
                       name: "Metformin", atcCode: nil, ndcCode: nil, dosage: "500mg",
                       frequency: "daily", route: "oral", startDate: "2026-01-01",
                       endDate: nil, isActive: true, notes: nil, createdAt: ts).inserted(dbConn)
        try Medication(id: nil, patientId: patientId, diagnosisId: nil, doctorId: nil,
                       name: "Ibuprofen", atcCode: nil, ndcCode: nil, dosage: "200mg",
                       frequency: "as needed", route: "oral", startDate: "2025-06-01",
                       endDate: "2025-12-01", isActive: false, notes: nil, createdAt: ts).inserted(dbConn)
    }

    let result = try await tools.handle(CallTool.Parameters(name: "get_medication_list", arguments: [
        "patient_id": .int(Int(patientId)),
        "active_only": .bool(true),
    ]))
    let arr = try #require(extractJSONArray(from: result))
    #expect(arr.count == 1)
    #expect(arr[0]["name"] as? String == "Metformin")
}

@Test("get_medication_list includes prescribing doctor and diagnosis")
func medicationListWithJoins() async throws {
    let db = try makeDB()
    let patientId = try insertPatient(db: db)
    let tools = QueryTools(db: db)
    let ts = timestamp()

    let (doctorId, diagnosisId) = try await db.dbQueue.write { dbConn -> (Int64, Int64) in
        let doc = try Doctor(id: nil, firstName: "Jane", lastName: "Smith",
                             specialty: "Endocrinology", createdAt: ts).inserted(dbConn)
        let diag = try Diagnosis(id: nil, patientId: patientId, encounterId: nil, icdCode: "E11.9",
                                 description: "Type 2 diabetes", diagnosisDate: "2026-01-01",
                                 status: "active", notes: nil, createdAt: ts).inserted(dbConn)
        return (doc.id!, diag.id!)
    }

    try await db.dbQueue.write { dbConn in
        try Medication(id: nil, patientId: patientId, diagnosisId: diagnosisId, doctorId: doctorId,
                       name: "Metformin", atcCode: nil, ndcCode: nil, dosage: "500mg",
                       frequency: "daily", route: "oral", startDate: "2026-01-01",
                       endDate: nil, isActive: true, notes: nil, createdAt: ts).inserted(dbConn)
    }

    let result = try await tools.handle(CallTool.Parameters(name: "get_medication_list", arguments: [
        "patient_id": .int(Int(patientId)),
    ]))
    let arr = try #require(extractJSONArray(from: result))
    #expect(arr.count == 1)
    #expect(arr[0]["prescribing_doctor"] as? String == "Jane Smith")
    #expect(arr[0]["diagnosis"] as? String == "Type 2 diabetes")
}

@Test("get_encounter with linked clinical data")
func encounterWithLinkedData() async throws {
    let db = try makeDB()
    let patientId = try insertPatient(db: db)
    let tools = QueryTools(db: db)
    let ts = timestamp()

    let encounterId = try await db.dbQueue.write { dbConn -> Int64 in
        let enc = try Encounter(id: nil, patientId: patientId, facilityId: nil, doctorId: nil,
                                encounterDate: "2026-01-10", encounterType: "office_visit",
                                chiefComplaint: "Checkup", notes: nil, createdAt: ts).inserted(dbConn)
        try Diagnosis(id: nil, patientId: patientId, encounterId: enc.id, icdCode: nil,
                      description: "Hypertension", diagnosisDate: "2026-01-10",
                      status: "active", notes: nil, createdAt: ts).inserted(dbConn)
        try LabResult(id: nil, patientId: patientId, encounterId: enc.id, testName: "BP Panel",
                      testCategory: nil, value: "Normal", numericValue: nil, unit: nil,
                      referenceRangeLow: nil, referenceRangeHigh: nil, referenceRangeText: nil,
                      flag: nil, testDate: "2026-01-10", notes: nil, createdAt: ts).inserted(dbConn)
        try VitalSign(id: nil, patientId: patientId, encounterId: enc.id,
                      vitalType: "blood_pressure", value: "120/80", numericValue: 120.0,
                      numericValue2: 80.0, unit: "mmHg", measuredDate: "2026-01-10",
                      createdAt: ts).inserted(dbConn)
        return enc.id!
    }

    let result = try await tools.handle(CallTool.Parameters(name: "get_encounter", arguments: [
        "encounter_id": .int(Int(encounterId)),
    ]))
    let json = try #require(extractJSON(from: result))

    #expect(json["encounter_type"] as? String == "office_visit")
    let diagnoses = try #require(json["diagnoses"] as? [[String: Any]])
    #expect(diagnoses.count == 1)
    let labs = try #require(json["lab_results"] as? [[String: Any]])
    #expect(labs.count == 1)
    let vitals = try #require(json["vital_signs"] as? [[String: Any]])
    #expect(vitals.count == 1)
}

@Test("get_diagnosis with status filter")
func diagnosisStatusFilter() async throws {
    let db = try makeDB()
    let patientId = try insertPatient(db: db)
    let tools = QueryTools(db: db)
    let ts = timestamp()

    try await db.dbQueue.write { dbConn in
        try Diagnosis(id: nil, patientId: patientId, encounterId: nil, icdCode: nil,
                      description: "Hypertension", diagnosisDate: "2026-01-01",
                      status: "active", notes: nil, createdAt: ts).inserted(dbConn)
        try Diagnosis(id: nil, patientId: patientId, encounterId: nil, icdCode: nil,
                      description: "Common cold", diagnosisDate: "2025-12-01",
                      status: "resolved", notes: nil, createdAt: ts).inserted(dbConn)
    }

    let result = try await tools.handle(CallTool.Parameters(name: "get_diagnosis", arguments: [
        "patient_id": .int(Int(patientId)),
        "status": .string("active"),
    ]))
    let arr = try #require(extractJSONArray(from: result))
    #expect(arr.count == 1)
    #expect(arr[0]["description"] as? String == "Hypertension")
}

@Test("get_allergies returns all for patient")
func allergiesReturned() async throws {
    let db = try makeDB()
    let patientId = try insertPatient(db: db)
    let tools = QueryTools(db: db)
    let ts = timestamp()

    try await db.dbQueue.write { dbConn in
        try Allergy(id: nil, patientId: patientId, allergen: "Penicillin",
                    allergenType: "drug", reaction: "rash", severity: "severe",
                    onsetDate: nil, status: "active", createdAt: ts).inserted(dbConn)
        try Allergy(id: nil, patientId: patientId, allergen: "Peanuts",
                    allergenType: "food", reaction: "anaphylaxis", severity: "moderate",
                    onsetDate: nil, status: "active", createdAt: ts).inserted(dbConn)
    }

    let result = try await tools.handle(CallTool.Parameters(name: "get_allergies", arguments: [
        "patient_id": .int(Int(patientId)),
    ]))
    let arr = try #require(extractJSONArray(from: result))
    #expect(arr.count == 2)
}

@Test("get_immunization_history ordered by date")
func immunizationHistoryOrdered() async throws {
    let db = try makeDB()
    let patientId = try insertPatient(db: db)
    let tools = QueryTools(db: db)
    let ts = timestamp()

    try await db.dbQueue.write { dbConn in
        try Immunization(id: nil, patientId: patientId, vaccineName: "Flu",
                         vaccineCode: nil, doseNumber: 1, administrationDate: "2025-10-01",
                         administeredBy: nil, lotNumber: nil, site: nil, notes: nil,
                         createdAt: ts).inserted(dbConn)
        try Immunization(id: nil, patientId: patientId, vaccineName: "COVID-19",
                         vaccineCode: nil, doseNumber: 3, administrationDate: "2026-01-15",
                         administeredBy: nil, lotNumber: nil, site: nil, notes: nil,
                         createdAt: ts).inserted(dbConn)
    }

    let result = try await tools.handle(CallTool.Parameters(name: "get_immunization_history", arguments: [
        "patient_id": .int(Int(patientId)),
    ]))
    let arr = try #require(extractJSONArray(from: result))
    #expect(arr.count == 2)
    #expect(arr[0]["vaccine_name"] as? String == "COVID-19")
    #expect(arr[1]["vaccine_name"] as? String == "Flu")
}
