import ActivityKit
import Foundation

struct LandlordHoursTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var propertyName: String
        var categoryName: String
        var startDate: Date
        var isReviewNeeded: Bool
    }

    var timerId: String
}
