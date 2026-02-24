import Foundation
import SwiftUI
import CloudKit
import AuthenticationServices

@MainActor
class AppViewModel: ObservableObject {
    @Published var properties: [RentalProperty] = []
    @Published var timeEntries: [TimeEntry] = []
    @Published var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @Published var iCloudSynced = false
    @Published var isInitializing = true
    @Published var lastSyncDate: Date?
    @Published var isSignedIn = false
    @Published var userName: String = ""
    
    // Timer state
    @Published var isTimerRunning = false
    @Published var timerStartTime: Date?
    @Published var timerPropertyId: UUID?
    @Published var timerCategory: ActivityCategory = .repairs
    
    // Data persistence
    private let propertiesKey = "LandlordHours.properties"
    private let entriesKey = "LandlordHours.entries"
    private let timerKey = "LandlordHours.timer"
    
    // CloudKit - lazy init to avoid blocking UI
    private lazy var container: CKContainer = {
        CKContainer(identifier: "iCloud.com.openclaw.landlordhours")
    }()
    private var database: CKDatabase { container.privateCloudDatabase }
    
    init() {
        loadData()
        loadTimerState()
        checkSignInState()
        // Show branded splash screen for 1.5s, then animate into the app
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.4)) {
                self.isInitializing = false
            }
        }
        // iCloud check after splash
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            Task {
                await self.checkiCloudStatusAsync()
            }
        }
    }
    
    func checkSignInState() {
        if UserDefaults.standard.string(forKey: "appleUserId") != nil {
            isSignedIn = true
            userName = UserDefaults.standard.string(forKey: "appleUserName") ?? "User"
        } else if UserDefaults.standard.string(forKey: "emailUserId") != nil {
            isSignedIn = true
            userName = UserDefaults.standard.string(forKey: "emailUserName") ?? "User"
        }
    }

    func signIn() {
        isSignedIn = true
        if let name = UserDefaults.standard.string(forKey: "appleUserName"), !name.isEmpty {
            userName = name
        } else if let name = UserDefaults.standard.string(forKey: "emailUserName"), !name.isEmpty {
            userName = name
        } else {
            userName = "User"
        }
    }
    
    func signOut() {
        UserDefaults.standard.removeObject(forKey: "appleUserId")
        UserDefaults.standard.removeObject(forKey: "appleUserName")
        UserDefaults.standard.removeObject(forKey: "appleUserEmail")
        isSignedIn = false
        userName = ""
    }
    
    // MARK: - Subscription Features
    func canAddProperty() -> Bool {
        if SubscriptionManager.shared.isPro { return true }
        return properties.count < 1
    }
    
    func canAddTimeEntry() -> Bool {
        return true // Open for all users
    }

    func canAttachPhotos() -> Bool {
        return true // Open for all users
    }
    
    func canExportPDF() -> Bool {
        return SubscriptionManager.shared.isPro
    }
    
    func getUpgradeMessage() -> String {
        if !canAddProperty() {
            return "Upgrade to Pro to add unlimited properties"
        }
        if !canAddTimeEntry() {
            return "Upgrade to Pro for unlimited time entries"
        }
        return "Upgrade to Pro for unlimited access"
    }
    
    // MARK: - iCloud Sync
    func checkiCloudStatus() {
        // Sync version - calls async version
        Task {
            await checkiCloudStatusAsync()
        }
    }
    
    private func checkiCloudStatusAsync() async {
        do {
            let status = try await container.accountStatus()
            await MainActor.run {
                self.iCloudSynced = (status == .available)
            }
        } catch {
            print("CloudKit account status error: \(error)")
            await MainActor.run {
                self.iCloudSynced = false
            }
        }
    }
    
    func syncToiCloud() {
        guard iCloudSynced else { return }
        
        // Save properties
        for property in properties {
            savePropertyToCloud(property)
        }
        
        // Save time entries
        for entry in timeEntries {
            saveEntryToCloud(entry)
        }
        
        lastSyncDate = Date()
    }
    
    func syncToiCloudAsync() async {
        guard iCloudSynced else { return }
        
        // Save properties
        for property in properties {
            await savePropertyToCloudAsync(property)
        }
        
        // Save time entries
        for entry in timeEntries {
            await saveEntryToCloudAsync(entry)
        }
        
        await MainActor.run {
            lastSyncDate = Date()
        }
    }
    
    private func savePropertyToCloudAsync(_ property: RentalProperty) async {
        let record = CKRecord(recordType: "Property", recordID: CKRecord.ID(recordName: property.id.uuidString))
        record["name"] = property.name
        record["address"] = property.address
        record["propertyType"] = property.propertyType.rawValue
        record["createdAt"] = property.createdAt
        
        do {
            _ = try await database.save(record)
        } catch {
            print("CloudKit save error: \(error.localizedDescription)")
        }
    }
    
    private func saveEntryToCloudAsync(_ entry: TimeEntry) async {
        let record = CKRecord(recordType: "TimeEntry", recordID: CKRecord.ID(recordName: entry.id.uuidString))
        record["propertyId"] = entry.propertyId.uuidString
        record["participant"] = entry.participant.rawValue
        record["category"] = entry.category.rawValue
        record["hours"] = entry.hours
        record["date"] = entry.date
        record["notes"] = entry.notes
        record["createdAt"] = entry.createdAt
        
        do {
            _ = try await database.save(record)
        } catch {
            print("CloudKit save error: \(error.localizedDescription)")
        }
    }
    
    private func savePropertyToCloud(_ property: RentalProperty) {
        let record = CKRecord(recordType: "Property", recordID: CKRecord.ID(recordName: property.id.uuidString))
        record["name"] = property.name
        record["address"] = property.address
        record["propertyType"] = property.propertyType.rawValue
        record["createdAt"] = property.createdAt
        
        database.save(record) { _, error in
            if let error = error {
                print("CloudKit save error: \(error.localizedDescription)")
            }
        }
    }
    
    private func saveEntryToCloud(_ entry: TimeEntry) {
        let record = CKRecord(recordType: "TimeEntry", recordID: CKRecord.ID(recordName: entry.id.uuidString))
        record["propertyId"] = entry.propertyId.uuidString
        record["participant"] = entry.participant.rawValue
        record["category"] = entry.category.rawValue
        record["hours"] = entry.hours
        record["date"] = entry.date
        record["notes"] = entry.notes
        record["createdAt"] = entry.createdAt
        
        database.save(record) { _, error in
            if let error = error {
                print("CloudKit save error: \(error.localizedDescription)")
            }
        }
    }
    
    func loadFromiCloud() {
        guard iCloudSynced else { return }
        
        // Load properties
        let propertyQuery = CKQuery(recordType: "Property", predicate: NSPredicate(value: true))
        database.fetch(withQuery: propertyQuery) { [weak self] result in
            if case .success(let matchResults) = result {
                for (_, recordResult) in matchResults.matchResults {
                    if case .success(let record) = recordResult {
                        if let name = record["name"] as? String,
                           let address = record["address"] as? String,
                           let typeRaw = record["propertyType"] as? String,
                           let type = PropertyType(rawValue: typeRaw),
                           let idString = record.recordID.recordName as String?,
                           let id = UUID(uuidString: idString) {
                            let property = RentalProperty(id: id, name: name, address: address, propertyType: type)
                            Task { @MainActor in
                                if !(self?.properties.contains(where: { $0.id == property.id }) ?? false) {
                                    self?.properties.append(property)
                                    self?.saveData()
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Load time entries
        let entryQuery = CKQuery(recordType: "TimeEntry", predicate: NSPredicate(value: true))
        database.fetch(withQuery: entryQuery) { [weak self] result in
            if case .success(let matchResults) = result {
                for (_, recordResult) in matchResults.matchResults {
                    if case .success(let record) = recordResult {
                        if let propertyIdString = record["propertyId"] as? String,
                           let propertyId = UUID(uuidString: propertyIdString),
                           let participantRaw = record["participant"] as? String,
                           let participant = Participant(rawValue: participantRaw),
                           let categoryRaw = record["category"] as? String,
                           let category = ActivityCategory(rawValue: categoryRaw),
                           let hours = record["hours"] as? Double,
                           let date = record["date"] as? Date,
                           let idString = record.recordID.recordName as String?,
                           let id = UUID(uuidString: idString) {
                            let notes = record["notes"] as? String ?? ""
                            Task { @MainActor in
                                guard let propertyName = self?.properties.first(where: { $0.id == propertyId })?.name else { return }
                                let entry = TimeEntry(id: id, propertyId: propertyId, participant: participant, category: category, hours: hours, date: date, notes: notes)
                                if !(self?.timeEntries.contains(where: { $0.id == entry.id }) ?? false) {
                                    self?.timeEntries.append(entry)
                                    self?.saveData()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    func loadFromiCloudAsync() async {
        guard iCloudSynced else { return }
        
        // Load properties
        let propertyQuery = CKQuery(recordType: "Property", predicate: NSPredicate(value: true))
        do {
            let propertyResult = try await database.records(matching: propertyQuery)
            for (_, recordResult) in propertyResult.matchResults {
                if case .success(let record) = recordResult {
                    if let name = record["name"] as? String,
                       let address = record["address"] as? String,
                       let typeRaw = record["propertyType"] as? String,
                       let type = PropertyType(rawValue: typeRaw),
                       let idString = record.recordID.recordName as String?,
                       let id = UUID(uuidString: idString) {
                        let property = RentalProperty(id: id, name: name, address: address, propertyType: type)
                        await MainActor.run {
                            if !self.properties.contains(where: { $0.id == property.id }) {
                                self.properties.append(property)
                            }
                        }
                    }
                }
            }
        } catch {
            print("CloudKit fetch error: \(error)")
        }
        
        // Load time entries
        let entryQuery = CKQuery(recordType: "TimeEntry", predicate: NSPredicate(value: true))
        do {
            let entryResult = try await database.records(matching: entryQuery)
            for (_, recordResult) in entryResult.matchResults {
                if case .success(let record) = recordResult {
                    if let propertyIdString = record["propertyId"] as? String,
                       let propertyId = UUID(uuidString: propertyIdString),
                       let participantRaw = record["participant"] as? String,
                       let participant = Participant(rawValue: participantRaw),
                       let categoryRaw = record["category"] as? String,
                       let category = ActivityCategory(rawValue: categoryRaw),
                       let hours = record["hours"] as? Double,
                       let date = record["date"] as? Date,
                       let idString = record.recordID.recordName as String?,
                       let id = UUID(uuidString: idString) {
                        let notes = record["notes"] as? String ?? ""
                        let propertyName = self.properties.first { $0.id == propertyId }?.name ?? "Unknown"
                        let entry = TimeEntry(id: id, propertyId: propertyId, participant: participant, category: category, hours: hours, date: date, notes: notes)
                        await MainActor.run {
                            if !self.timeEntries.contains(where: { $0.id == entry.id }) {
                                self.timeEntries.append(entry)
                            }
                        }
                    }
                }
            }
            await MainActor.run {
                self.saveData()
            }
        } catch {
            print("CloudKit fetch error: \(error)")
        }
    }
    
    // MARK: - Property Management
    func addProperty(name: String, address: String, type: PropertyType) {
        let property = RentalProperty(name: name, address: address, propertyType: type)
        properties.append(property)
        saveData()
    }
    
    func updateProperty(_ property: RentalProperty) {
        if let index = properties.firstIndex(where: { $0.id == property.id }) {
            properties[index] = property
            saveData()
        }
    }
    
    func deleteProperty(_ property: RentalProperty) {
        properties.removeAll { $0.id == property.id }
        timeEntries.removeAll { $0.propertyId == property.id }
        saveData()
    }
    
    // MARK: - Time Entry Management
    func addTimeEntry(
        propertyId: UUID,
        participant: Participant,
        category: ActivityCategory,
        hours: Double,
        date: Date,
        notes: String,
        attachments: [TimeAttachment] = []
    ) {
        let entry = TimeEntry(
            propertyId: propertyId,
            participant: participant,
            category: category,
            hours: hours,
            date: date,
            notes: notes,
            attachments: attachments
        )
        timeEntries.append(entry)
        saveData()
    }
    
    func deleteTimeEntry(_ entry: TimeEntry) {
        timeEntries.removeAll { $0.id == entry.id }
        saveData()
    }
    
    // MARK: - Timer Functions
    func startTimer(propertyId: UUID, category: ActivityCategory) {
        isTimerRunning = true
        timerStartTime = Date()
        timerPropertyId = propertyId
        timerCategory = category
        saveTimerState()
    }
    
    func stopTimer(participant: Participant, notes: String = "") {
        guard isTimerRunning,
              let startTime = timerStartTime,
              let propertyId = timerPropertyId else { return }
        
        let hours = Date().timeIntervalSince(startTime) / 3600.0
        
        addTimeEntry(
            propertyId: propertyId,
            participant: participant,
            category: timerCategory,
            hours: hours,
            date: startTime,
            notes: notes
        )
        
        isTimerRunning = false
        timerStartTime = nil
        timerPropertyId = nil
        saveTimerState()
    }
    
    func cancelTimer() {
        isTimerRunning = false
        timerStartTime = nil
        timerPropertyId = nil
        saveTimerState()
    }
    
    var timerElapsedTime: TimeInterval {
        guard let startTime = timerStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    // MARK: - REPS Calculations
    func entriesForYear(_ year: Int) -> [TimeEntry] {
        let calendar = Calendar.current
        return timeEntries.filter { calendar.component(.year, from: $0.date) == year }
    }
    
    func totalHoursForParticipant(_ participant: Participant, year: Int) -> Double {
        entriesForYear(year)
            .filter { $0.participant == participant && $0.countsForREPS }
            .reduce(0) { $0 + $1.hours }
    }
    
    func totalHoursAllParticipants(year: Int) -> Double {
        entriesForYear(year)
            .filter { $0.countsForREPS }
            .reduce(0) { $0 + $1.hours }
    }
    
    func totalHoursForProperty(_ propertyId: UUID) -> Double {
        timeEntries
            .filter { $0.propertyId == propertyId && $0.countsForREPS }
            .reduce(0) { $0 + $1.hours }
    }
    
    func hoursForProperty(_ property: RentalProperty, year: Int) -> Double {
        entriesForYear(year)
            .filter { $0.propertyId == property.id && $0.countsForREPS }
            .reduce(0) { $0 + $1.hours }
    }
    
    func progressTo750Hours(participant: Participant, year: Int) -> Double {
        let hours = totalHoursForParticipant(participant, year: year)
        return min(hours / REPSRequirements.annualHourThreshold, 1.0)
    }
    
    func meets50PercentRule(year: Int) -> Bool {
        let selfHours = totalHoursForParticipant(.selfParticipant, year: year)
        let spouseHours = totalHoursForParticipant(.spouse, year: year)
        let totalHours = selfHours + spouseHours
        
        guard totalHours > 0 else { return false }
        
        let selfPercentage = selfHours / totalHours
        let spousePercentage = spouseHours / totalHours
        
        return selfPercentage <= REPSRequirements.workingTimePercentage || 
               spousePercentage <= REPSRequirements.workingTimePercentage
    }
    
    // MARK: - Persistence
    private func saveData() {
        if let propertiesData = try? JSONEncoder().encode(properties) {
            UserDefaults.standard.set(propertiesData, forKey: propertiesKey)
        }
        if let entriesData = try? JSONEncoder().encode(timeEntries) {
            UserDefaults.standard.set(entriesData, forKey: entriesKey)
        }
    }
    
    private func loadData() {
        if let propertiesData = UserDefaults.standard.data(forKey: propertiesKey),
           let decoded = try? JSONDecoder().decode([RentalProperty].self, from: propertiesData) {
            properties = decoded
        }
        if let entriesData = UserDefaults.standard.data(forKey: entriesKey),
           let decoded = try? JSONDecoder().decode([TimeEntry].self, from: entriesData) {
            timeEntries = decoded
        }
    }
    
    private func saveTimerState() {
        if let startTime = timerStartTime {
            UserDefaults.standard.set(startTime, forKey: "timerStartTime")
        }
        UserDefaults.standard.set(isTimerRunning, forKey: timerKey)
        if let propertyId = timerPropertyId {
            UserDefaults.standard.set(propertyId.uuidString, forKey: "timerPropertyId")
        }
    }
    
    private func loadTimerState() {
        isTimerRunning = UserDefaults.standard.bool(forKey: timerKey)
        if let startTime = UserDefaults.standard.object(forKey: "timerStartTime") as? Date {
            timerStartTime = startTime
        }
        if let propertyIdStr = UserDefaults.standard.string(forKey: "timerPropertyId"),
           let propertyId = UUID(uuidString: propertyIdStr) {
            timerPropertyId = propertyId
        }
    }
}
