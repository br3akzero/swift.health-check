import Testing
import Foundation
import MCP
import GRDB
@testable import HealthCheck

@Test("get_doctor includes linked facilities")
func doctorWithFacilities() async throws {
    let db = try makeDB()
    let tools = QueryTools(db: db)
    let ts = timestamp()

    let (doctorId, facilityId) = try await db.dbQueue.write { dbConn -> (Int64, Int64) in
        let doc = try Doctor(id: nil, firstName: "Jane", lastName: "Smith",
                             specialty: "Cardiology", createdAt: ts).inserted(dbConn)
        let fac = try Facility(id: nil, name: "City Hospital", facilityType: "hospital",
                               phone: "555-1234", address: "123 Main St",
                               website: nil, createdAt: ts).inserted(dbConn)
        try FacilityDoctor(facilityId: fac.id!, doctorId: doc.id!).inserted(dbConn)
        return (doc.id!, fac.id!)
    }

    let result = try await tools.handle(CallTool.Parameters(name: "get_doctor", arguments: [
        "doctor_id": .int(Int(doctorId)),
    ]))
    let json = try #require(extractJSON(from: result))

    #expect(json["first_name"] as? String == "Jane")
    #expect(json["specialty"] as? String == "Cardiology")

    let facilities = try #require(json["facilities"] as? [[String: Any]])
    #expect(facilities.count == 1)
    #expect(facilities[0]["name"] as? String == "City Hospital")
    #expect((facilities[0]["id"] as? Int64) == facilityId)
}

@Test("get_facility includes linked doctors")
func facilityWithDoctors() async throws {
    let db = try makeDB()
    let tools = QueryTools(db: db)
    let ts = timestamp()

    let (facilityId, doctorId) = try await db.dbQueue.write { dbConn -> (Int64, Int64) in
        let fac = try Facility(id: nil, name: "Downtown Clinic", facilityType: "clinic",
                               phone: nil, address: nil, website: nil, createdAt: ts).inserted(dbConn)
        let doc = try Doctor(id: nil, firstName: "Bob", lastName: "Jones",
                             specialty: "Family Medicine", createdAt: ts).inserted(dbConn)
        try FacilityDoctor(facilityId: fac.id!, doctorId: doc.id!).inserted(dbConn)
        return (fac.id!, doc.id!)
    }

    let result = try await tools.handle(CallTool.Parameters(name: "get_facility", arguments: [
        "facility_id": .int(Int(facilityId)),
    ]))
    let json = try #require(extractJSON(from: result))

    #expect(json["name"] as? String == "Downtown Clinic")
    #expect(json["facility_type"] as? String == "clinic")

    let doctors = try #require(json["doctors"] as? [[String: Any]])
    #expect(doctors.count == 1)
    #expect(doctors[0]["first_name"] as? String == "Bob")
    #expect((doctors[0]["id"] as? Int64) == doctorId)
}
