//
//  CloudKit.swift
//  dose
//
//  Created by Víctor Peña Romero on 17/08/24.
//

import Foundation
import Capacitor
import CloudKit

@objc(CloudKitPlugin)
public class CloudKitPlugin: CAPPlugin, CAPBridgedPlugin {
    
    public let identifier = "CloudKitPlugin"
    public let jsName = "CloudKitPlugin"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "createRecord", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "fetchRecords", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateRecord", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "deleteRecord", returnType: CAPPluginReturnPromise)
    ]
    
    @objc func createRecord(_ call: CAPPluginCall) {
        guard let recordType = call.options["recordType"] as? String else {
            call.reject("Must provide recordType")
            return
        }
        guard let fields = call.options["fields"] as? [String: Any] else {
            call.reject("Must provide fields")
            return
        }
        
        let record = createAndConfigureRecord(recordType: recordType, fields: fields)
        
        CKContainer.default().privateCloudDatabase.save(record) { savedRecord, error in
            DispatchQueue.main.async {
                if let error = error {
                    call.reject("Error saving record: \(error.localizedDescription)")
                    return
                }
                
                if let savedRecord = savedRecord {
                    call.resolve(["recordName": savedRecord.recordID.recordName])
                } else {
                    call.reject("Failed to save record for unknown reasons")
                }
            }
        }
    }
    
    @objc func fetchRecords(_ call: CAPPluginCall) {
            guard let recordType = call.options["recordType"] as? String else {
                call.reject("Must provide recordType")
                return
            }
            
            let predicate: NSPredicate
            if let predicateString = call.options["predicate"] as? String {
                if predicateString.contains("==") {
                    if let referenceId = call.options["referenceId"] as? String {
                        let recordID = CKRecord.ID(recordName: referenceId)
                        predicate = NSPredicate(format: predicateString, recordID)
                    } else {
                        predicate = NSPredicate(format: predicateString)
                    }
                } else {
                    predicate = NSPredicate(format: predicateString)
                }
            } else {
                predicate = NSPredicate(value: true)
            }
        
            let query = CKQuery(recordType: recordType, predicate: predicate)
            
            CKContainer.default().privateCloudDatabase.perform(query, inZoneWith: nil) { records, error in
                DispatchQueue.main.async {
                    if let error = error {
                        call.reject("Error fetching records: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let records = records else {
                        call.resolve(["records": []])
                        return
                    }
                    
                    let recordData = records.map { self.serializeRecord($0) }
                    
                    call.resolve(["records": recordData])
                }
            }
    }
    
    @objc func updateRecord(_ call: CAPPluginCall) {
            guard let recordID = call.options["recordId"] as? String else {
                call.reject("Must provide recordID")
                return
            }
            guard let fields = call.options["fields"] as? [String: Any] else {
                call.reject("Must provide fields")
                return
            }
            
            let recordIDObject = CKRecord.ID(recordName: recordID)
            
            CKContainer.default().privateCloudDatabase.fetch(withRecordID: recordIDObject) { record, error in
                DispatchQueue.main.async {
                    if let error = error {
                        call.reject("Error fetching record: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let record = record else {
                        call.reject("Record not found")
                        return
                    }
                    
                    for (key, value) in fields {
                        record.setValue(value, forKey: key)
                    }
                    
                    CKContainer.default().privateCloudDatabase.save(record) { savedRecord, error in
                        if let error = error {
                            call.reject("Error updating record: \(error.localizedDescription)")
                            return
                        }
                        
                        if let savedRecord = savedRecord {
                            call.resolve(["recordName": savedRecord.recordID.recordName])
                        } else {
                            call.reject("Failed to update record for unknown reasons")
                        }
                    }
                }
            }
    }
    
    @objc func deleteRecord(_ call: CAPPluginCall) {
            guard let recordID = call.options["recordId"] as? String else {
                call.reject("Must provide recordID")
                return
            }
            
            let recordIDObject = CKRecord.ID(recordName: recordID)
            
            CKContainer.default().privateCloudDatabase.delete(withRecordID: recordIDObject) { deletedRecordID, error in
                DispatchQueue.main.async {
                    if let error = error {
                        call.reject("Error deleting record: \(error.localizedDescription)")
                        return
                    }
                    
                    if let deletedRecordID = deletedRecordID {
                        call.resolve(["deletedRecordID": deletedRecordID.recordName])
                    } else {
                        call.reject("Failed to delete record for unknown reasons")
                    }
                }
            }
    }
    
    private func createAndConfigureRecord(recordType: String, fields: [String: Any]) -> CKRecord {
        let record = CKRecord(recordType: recordType)
        
        for (key, value) in fields {
            if let referenceData = value as? [String: Any],
               let recordIDString = referenceData["recordId"] as? String {
                let recordID = CKRecord.ID(recordName: recordIDString)
                let reference = CKRecord.Reference(recordID: recordID, action: .deleteSelf)
                record.setValue(reference, forKey: key)
            } else {
                record.setValue(value, forKey: key)
            }
        }
        
        return record
    }
    
    private func serializeRecord(_ record: CKRecord) -> [String: Any] {
        var data = [String: Any]()
        data["id"] = record.recordID.recordName
        data["creationDate"] = ISO8601DateFormatter().string(from: record.creationDate ?? Date())
        
        for key in record.allKeys() {
            if let value = record[key] as? String {
                data[key] = value
            } else if let value = record[key] as? Int {
                data[key] = value
            } else if let value = record[key] as? Double {
                data[key] = value
            } else if let value = record[key] as? Date {
                data[key] = ISO8601DateFormatter().string(from: value)
            } else if let reference = record[key] as? CKRecord.Reference {
                data[key] = reference.recordID.recordName
            } else {
                print("Warning: Value for key '\(key)' in record '\(record.recordID.recordName)' is not serializable to JSON. Value type: \(type(of: record[key] ?? "nil"))")
                data[key] = nil
            }
        }
        
        return data
    }
}
