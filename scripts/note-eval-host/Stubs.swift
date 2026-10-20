import Foundation
// Host-only stand-ins for app symbols the note reader's files reference.
struct CaptureFlags { func isEnabled(_ flag: CaptureFlag) -> Bool { true } }
enum CaptureFlag { case privateCloudCompute }
enum LogField: Hashable { case property, category, hours, participant, date, description }
