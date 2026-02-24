import SwiftUI
import PDFKit

struct ExportPDFView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    let year: Int
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        generateAndSharePDF()
                    } label: {
                        Label("Export as PDF", systemImage: "doc.fill")
                    }
                } footer: {
                    Text("Generates a detailed PDF report of all time entries for tax auditing purposes.")
                }
                
                Section("Report Includes") {
                    LabeledContent("Property Details", value: "\(viewModel.properties.count) properties")
                    LabeledContent("Time Entries", value: "\(yearEntries.count) entries")
                    LabeledContent("Total Hours", value: String(format: "%.1f hours", totalHours))
                    LabeledContent("REPS Qualified", value: String(format: "%.1f hours", repsQualifiedHours))
                }
            }
            .navigationTitle("Export Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    var yearEntries: [TimeEntry] {
        viewModel.timeEntries.filter { Calendar.current.component(.year, from: $0.date) == year }
    }
    
    var totalHours: Double {
        yearEntries.reduce(0) { $0 + $1.hours }
    }
    
    var repsQualifiedHours: Double {
        yearEntries.filter { $0.countsForREPS }.reduce(0) { $0 + $1.hours }
    }
    
    func generateAndSharePDF() {
        let pdfData = generatePDF()
        
        // Save to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("LandlordHours_\(year).pdf")
        try? pdfData.write(to: tempURL)
        
        // Present share sheet
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        
        dismiss()
    }
    
    func generatePDF() -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        
        let pdfMetaData = [
            kCGPDFContextCreator: "LandlordHours",
            kCGPDFContextAuthor: "LandlordHours App",
            kCGPDFContextTitle: "REPS Time Report \(year)"
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { context in
            context.beginPage()
            
            // Title
            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let title = "LandlordHours REPS Report"
            title.draw(at: CGPoint(x: margin, y: margin), withAttributes: [.font: titleFont])
            
            // Year
            let yearFont = UIFont.systemFont(ofSize: 18)
            "Year \(year)".draw(at: CGPoint(x: margin, y: margin + 35), withAttributes: [.font: yearFont])
            
            // Summary
            let headerFont = UIFont.boldSystemFont(ofSize: 14)
            let bodyFont = UIFont.systemFont(ofSize: 12)
            
            var yPosition: CGFloat = margin + 80
            
            "Summary".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: headerFont])
            yPosition += 25
            
            "Total Hours Logged: \(String(format: "%.1f", totalHours)) hours".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: bodyFont])
            yPosition += 20
            
            "REPS Qualified Hours: \(String(format: "%.1f", repsQualifiedHours)) hours".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: bodyFont])
            yPosition += 20
            
            "Total Entries: \(yearEntries.count)".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: bodyFont])
            yPosition += 35
            
            // Properties
            "Properties".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: headerFont])
            yPosition += 25
            
            for property in viewModel.properties {
                property.name.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: bodyFont])
                yPosition += 18
                property.address.draw(at: CGPoint(x: margin + 20, y: yPosition), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.gray])
                yPosition += 25
                
                if yPosition > pageHeight - 100 {
                    context.beginPage()
                    yPosition = margin
                }
            }
            
            yPosition += 15
            
            // Time Entries
            "Time Entries".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: headerFont])
            yPosition += 25
            
            // Table header
            let entries = yearEntries.sorted { $0.date > $1.date }
            
            for entry in entries {
                let property = viewModel.properties.first { $0.id == entry.propertyId }
                let propertyName = property?.name ?? "Unknown"
                
                let entryText = "\(entry.formattedDate) | \(propertyName) | \(entry.category.rawValue) | \(String(format: "%.1f", entry.hours))h | \(entry.participant.rawValue)"
                entryText.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: bodyFont])
                yPosition += 16
                
                if !entry.notes.isEmpty {
                    "  Notes: \(entry.notes)".draw(at: CGPoint(x: margin + 20, y: yPosition), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.gray])
                    yPosition += 16
                }
                
                if yPosition > pageHeight - 50 {
                    context.beginPage()
                    yPosition = margin
                }
            }
            
            // Footer
            let footerFont = UIFont.systemFont(ofSize: 10)
            let footer = "Generated by LandlordHours on \(Date().formatted(date: .long, time: .omitted))"
            let footerRect = CGRect(x: margin, y: pageHeight - 30, width: pageWidth - 2 * margin, height: 20)
            footer.draw(in: footerRect, withAttributes: [.font: footerFont, .foregroundColor: UIColor.gray])
        }
        
        return data
    }
}
