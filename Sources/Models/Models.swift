import Foundation

// MARK: - Property Entity
enum PropertyType: String, Codable, CaseIterable {
    case ltr = "LTR"
    case str = "STR"
    
    var displayName: String {
        rawValue
    }
    
    var fullName: String {
        switch self {
        case .ltr: return "Long-Term Rental"
        case .str: return "Short-Term Rental"
        }
    }
    
    var icon: String {
        switch self {
        case .ltr: return "house.fill"
        case .str: return "building.2.fill"
        }
    }
}

struct RentalProperty: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var address: String
    var propertyType: PropertyType
    var createdAt: Date
    
    init(id: UUID = UUID(), name: String, address: String, propertyType: PropertyType) {
        self.id = id
        self.name = name
        self.address = address
        self.propertyType = propertyType
        self.createdAt = Date()
    }
    
    var shortAddress: String {
        let components = address.components(separatedBy: ",")
        return components.first ?? address
    }
}

// MARK: - Activity Types (IRS-Approved)
enum ActivityCategory: String, Codable, CaseIterable {
    // Material Participation Activities (IRS-approved)
    case repairs = "Repairs & Maintenance"
    case management = "Property Management"
    case leasing = "Leasing & Tenant Relations"
    case bookkeeping = "Bookkeeping & Financial"
    case legal = "Legal & Compliance"
    case insurance = "Insurance & Claims"
    case travel = "Travel to Property"
    case renovations = "Renovations & Improvements"
    
    // Investor-Level Tasks (don't count for REPS)
    case investing = "Investing Decisions"
    case financing = "Financing"
    case contractNegotiation = "Contract Negotiation"
    
    var countsForREPS: Bool {
        switch self {
        case .investing, .financing, .contractNegotiation:
            return false
        default:
            return true
        }
    }
    
    var description: String {
        switch self {
        case .repairs: return "Fixing leaks, HVAC, plumbing, electrical"
        case .management: return "Collecting rent, communications, scheduling"
        case .leasing: return "Showing units, screening tenants, signing leases"
        case .bookkeeping: return "Accounting, tax prep, financial records"
        case .legal: return "Evictions, compliance, permits"
        case .insurance: return "Claims, policy reviews"
        case .travel: return "Driving to property for activities"
        case .renovations: return "Major improvements, remodeling"
        case .investing: return "NOT countable - Investment decisions"
        case .financing: return "NOT countable - Loan decisions"
        case .contractNegotiation: return "NOT countable - Purchase/sale negotiations"
        }
    }
    
    var icon: String {
        switch self {
        case .repairs: return "wrench.fill"
        case .management: return "folder.fill"
        case .leasing: return "key.fill"
        case .bookkeeping: return "doc.text.fill"
        case .legal: return "building.columns.fill"
        case .insurance: return "shield.fill"
        case .travel: return "car.fill"
        case .renovations: return "hammer.fill"
        case .investing: return "chart.line.uptrend.xyaxis"
        case .financing: return "dollarsign.circle.fill"
        case .contractNegotiation: return "signature"
        }
    }
    
    static var repsQualified: [ActivityCategory] {
        allCases.filter { $0.countsForREPS }
    }
    
    static var nonREPS: [ActivityCategory] {
        allCases.filter { !$0.countsForREPS }
    }
}

// MARK: - Participant
enum Participant: String, Codable, CaseIterable {
    case selfParticipant = "Self"
    case spouse = "Spouse"
    
    var icon: String {
        switch self {
        case .selfParticipant: return "person.fill"
        case .spouse: return "person.2.fill"
        }
    }
}

// MARK: - Attachment Model
struct TimeAttachment: Identifiable, Codable {
    let id: UUID
    var filename: String
    var data: Data
    var mimeType: String
    var createdAt: Date
    
    init(id: UUID = UUID(), filename: String, data: Data, mimeType: String) {
        self.id = id
        self.filename = filename
        self.data = data
        self.mimeType = mimeType
        self.createdAt = Date()
    }
}

// MARK: - Time Entry
struct TimeEntry: Identifiable, Codable {
    let id: UUID
    var propertyId: UUID
    var participant: Participant
    var category: ActivityCategory
    var hours: Double
    var date: Date
    var notes: String
    var attachments: [TimeAttachment]
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        propertyId: UUID,
        participant: Participant,
        category: ActivityCategory,
        hours: Double,
        date: Date = Date(),
        notes: String = "",
        attachments: [TimeAttachment] = []
    ) {
        self.id = id
        self.propertyId = propertyId
        self.participant = participant
        self.category = category
        self.hours = hours
        self.date = date
        self.notes = notes
        self.attachments = attachments
        self.createdAt = Date()
    }
    
    // Helper to get property name - call this when needed
    func getPropertyName(from properties: [RentalProperty]) -> String {
        properties.first { $0.id == propertyId }?.name ?? "Unknown"
    }
    
    var countsForREPS: Bool {
        category.countsForREPS
    }
    
    var formattedDuration: String {
        String(format: "%.1fh", hours)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - REPS Requirements
struct REPSRequirements {
    static let annualHourThreshold: Double = 750.0
    static let workingTimePercentage: Double = 0.50
    
    static var weeklyGoal: Double {
        annualHourThreshold / 52.0
    }
    
    static var monthlyGoal: Double {
        annualHourThreshold / 12.0
    }
}

// MARK: - Date Extensions
extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    var startOfWeek: Date? {
        Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self))
    }
    
    var startOfMonth: Date? {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self))
    }
    
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    var isThisWeek: Bool {
        guard let weekStart = startOfWeek else { return false }
        return self >= weekStart
    }
    
    var isThisMonth: Bool {
        guard let monthStart = startOfMonth else { return false }
        return self >= monthStart
    }
    
    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: self)
    }
}
