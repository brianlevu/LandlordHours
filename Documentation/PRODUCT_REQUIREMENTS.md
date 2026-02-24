# LandlordHours - Product Requirements Document

## 1. Product Overview

**Product Name:** LandlordHours  
**Tagline:** Track Your Real Estate Professional Hours with Confidence  
**Version:** 1.0.0

### Summary
LandlordHours is a mobile-first time tracking app designed for real estate investors who need to meet IRS Material Participation requirements (REPS) and Short-Term Rental (STR) eligibility. The app helps users log hours toward the 750-hour annual requirement and track participation across multiple properties.

### Target Users
- Real estate investors with rental properties (LTR/STR)
- Taxpayers seeking REPS qualification for passive activity loss deductions
- Property managers tracking time across multiple rentals
- Married couples where both spouses participate in rental activities

---

## 2. Core Features

### 2.1 Time Tracking
- [x] Start/Stop Timer
- [x] Manual Time Entry
- [x] Assign to Property
- [x] Categorize Activities (REPS-qualified vs Non-REPS)
- [x] Track by Participant (Self/Spouse)
- [x] Add Notes to Entries

### 2.2 Property Management
- [x] Add/Edit/Delete Properties
- [x] Property Types: LTR (Long-Term Rental), STR (Short-Term Rental)
- [x] Property Address Storage
- [x] Hours per Property Tracking

### 2.3 REPS Compliance
- [x] 750-Hour Annual Goal Tracking
- [x] 50% Working Time Rule Calculator
- [x] REPS vs Non-REPS Activity Categories
- [x] Real-time Progress Dashboard

### 2.4 Reporting
- [x] Hours by Property
- [x] Hours by Category
- [x] Hours by Participant
- [x] Year-over-Year Comparison
- [ ] Export to PDF (Planned)

---

## 3. User Interface

### Navigation Structure
- **Tab Bar:** Home | Properties | Track | Reports | Settings

### Screen List
1. **Home** - Timer + Today's Stats + Quick Actions
2. **Properties** - List/Add/Manage Properties
3. **Track** - Manual Entry + Timer Controls
4. **Reports** - Detailed REPS Progress + Analytics
5. **Settings** - App Settings + Data Management

### Design System
- **Primary Color:** Blue (#007AFF)
- **Secondary Color:** Purple (#5856D6)
- **Success:** Green (#34C759)
- **Warning:** Orange (#FF9500)
- **Error:** Red (#FF3B30)
- **Background:** System Background (Adaptive)
- **Typography:** SF Pro (System Font)

---

## 4. Technical Specification

### Architecture
- **Pattern:** MVVM (Model-View-ViewModel)
- **UI Framework:** SwiftUI
- **Persistence:** UserDefaults (Local)
- **Minimum iOS:** 17.0
- **Bundle ID:** com.openclaw.repstracker

### Data Models
- `RentalProperty`: id, name, address, propertyType, createdAt
- `TimeEntry`: id, propertyId, participant, category, hours, date, notes, createdAt
- `ActivityCategory`: 11 categories (8 REPS-qualified, 3 non-REPS)

### Cloud Integration (Future)
- iCloud sync via CloudKit
- Export functionality

---

## 5. IRS Reference

### REPS Requirements (2024)
- **750-Hour Rule:** Must participate in rental activities for >750 hours annually
- **50% Rule:** Must not have more than 500 hours in other trade/business activities
- **Material Participation:** Real-time logging provides evidence for audit defense

### Qualifying Activities
- Repairs & Maintenance
- Property Management
- Leasing & Tenant Relations
- Bookkeeping & Financial
- Legal & Compliance
- Insurance & Claims
- Travel to Property
- Renovations & Improvements

### Non-Qualifying Activities
- Investing Decisions
- Financing
- Contract Negotiation

---

## 6. Roadmap

### v1.1 (Planned)
- [ ] iCloud Sync
- [ ] Export to PDF/CSV
- [ ] Voice Input for Quick Logging
- [ ] Photo Evidence Attachment

### v1.2 (Planned)
- [ ] Widget Support
- [ ] Apple Watch App
- [ ] Siri Shortcuts
- [ ] Calendar Integration

---

*Last Updated: February 20, 2026*
