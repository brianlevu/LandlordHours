import Foundation

class WeeklySummaryService {
    static let shared = WeeklySummaryService()
    
    private init() {}
    
    func generateWeeklySummary(entries: [TimeEntry]) -> String {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
            return "Unable to generate summary"
        }
        
        let weekEntries = entries.filter { $0.date >= weekStart && $0.category.countsForREPS }
        
        guard !weekEntries.isEmpty else {
            return "No time logged this week yet. Start tracking!"
        }
        
        let totalHours = weekEntries.reduce(0) { $0 + $1.hours }
        
        // Group by category
        var categoryHours: [String: Double] = [:]
        for entry in weekEntries {
            let categoryName = entry.category.rawValue
            categoryHours[categoryName, default: 0] += entry.hours
        }
        
        // Sort by hours
        let sortedCategories = categoryHours.sorted { $0.value > $1.value }
        
        var summary = "📊 Weekly Summary\n\n"
        summary += "Total: \(String(format: "%.1f", totalHours)) hours this week\n\n"
        
        summary += "Breakdown:\n"
        for (category, hours) in sortedCategories.prefix(5) {
            summary += "• \(category): \(String(format: "%.1f", hours))h\n"
        }
        
        // Goal progress
        let weeklyGoal = 750.0 / 52 // ~14.4 hours per week
        let progress = (totalHours / weeklyGoal) * 100
        summary += "\nGoal progress: \(Int(progress))% of weekly target"
        
        return summary
    }
    
    func generateMonthlySummary(entries: [TimeEntry]) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let monthStart = calendar.date(from: components) else {
            return "Unable to generate summary"
        }
        
        let monthEntries = entries.filter { $0.date >= monthStart && $0.category.countsForREPS }
        
        guard !monthEntries.isEmpty else {
            return "No time logged this month yet."
        }
        
        let totalHours = monthEntries.reduce(0) { $0 + $1.hours }
        
        // Properties worked
        let properties = Set(monthEntries.map { $0.propertyId })
        
        var summary = "📈 This Month\n"
        summary += "Total: \(String(format: "%.1f", totalHours)) hours\n"
        summary += "Properties: \(properties.count)\n"
        
        // REPS goal progress
        let yearProgress = (totalHours / 750.0) * 100
        summary += "REPS goal: \(Int(yearProgress))% complete"
        
        return summary
    }
}

class SmartReminderService {
    static let shared = SmartReminderService()
    
    private let lastLogKey = "lastLogDate"
    private let reminderEnabledKey = "smartRemindersEnabled"
    
    private init() {}
    
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: reminderEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: reminderEnabledKey) }
    }
    
    var lastLogDate: Date? {
        get { UserDefaults.standard.object(forKey: lastLogKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastLogKey) }
    }
    
    func recordLog() {
        lastLogDate = Date()
    }
    
    func daysSinceLastLog() -> Int? {
        guard let lastLog = lastLogDate else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: lastLog, to: Date())
        return components.day
    }
    
    func shouldRemind() -> Bool {
        guard isEnabled else { return false }
        guard let days = daysSinceLastLog() else { return true }
        return days >= 3 // Remind after 3 days of no logging
    }
    
    func getReminderMessage() -> String? {
        guard shouldRemind() else { return nil }
        let days = daysSinceLastLog() ?? 0
        
        let messages = [
            "Hey! You haven't logged time in \(days) days. How did you spend time on your rentals today?",
            "It's been \(days) days since your last entry. Take a moment to track your progress!",
            "Don't forget to log your REPS hours! It's been \(days) days.",
            "Quick reminder: Your rental activities need to be logged. Been \(days) days!"
        ]
        
        return messages.randomElement()
    }
    
    // Predict when user will hit REPS goal
    func predictGoalCompletion(entries: [TimeEntry]) -> String? {
        let calendar = Calendar.current
        let now = Date()
        
        // Get this year's entries
        let yearEntries = entries.filter {
            calendar.component(.year, from: $0.date) == calendar.component(.year, from: now) &&
            $0.category.countsForREPS
        }
        
        let totalHours = yearEntries.reduce(0) { $0 + $1.hours }
        guard totalHours > 0 else { return nil }
        
        let remaining = 750 - totalHours
        guard remaining > 0 else { return "🎉 You've hit your 750-hour REPS goal!" }
        
        // Calculate average hours per day
        if let firstEntry = yearEntries.sorted(by: { $0.date < $1.date }).first {
            let daysActive = calendar.dateComponents([.day], from: firstEntry.date, to: now).day ?? 1
            let avgPerDay = totalHours / Double(max(daysActive, 1))
            
            guard avgPerDay > 0 else { return nil }
            
            let daysToGoal = Int(remaining / avgPerDay)
            guard let completionDate = calendar.date(byAdding: .day, value: daysToGoal, to: now) else { return nil }
            
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            
            return "At your current pace, you'll hit 750 hours by \(formatter.string(from: completionDate))"
        }
        
        return nil
    }
}
