# LandlordHours

A mobile-first time tracking app for landlords to track hours spent on rental properties for IRS Real Estate Professional Status (REPS) tax qualification.

## Tagline

*"Track your path to tax qualification"*

## Features

- ⏱️ **Timer** - Start/stop tracking with one tap
- 🏠 **Multi-Property** - Track hours across LTR and STR properties
- 📊 **Dashboard** - Real-time progress toward 750-hour requirement
- 👥 **Multi-User** - Track hours for Self and Spouse
- 📈 **Reports** - Detailed breakdowns by property and category
- ⚖️ **50% Rule Calculator** - Monitor working time participation

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Apple Developer Account (for device deployment)

## Getting Started

### Installation

1. Clone the repository
2. Open `LandlordHours.xcodeproj` in Xcode
3. Select your target device/simulator
4. Build and run (⌘R)

### Setup

1. Add your rental properties (LTR or STR)
2. Start tracking time using the timer or manual entry
3. Monitor progress on the Home and Reports screens

## Project Structure

```
LandlordHours/
├── Sources/
│   ├── App/
│   │   └── LandlordHoursApp.swift
│   ├── Models/
│   │   └── Models.swift
│   ├── ViewModels/
│   │   └── AppViewModel.swift
│   └── Views/
│       ├── ContentView.swift
│       ├── DashboardView.swift
│       ├── PropertiesView.swift
│       ├── TimeLogView.swift
│       ├── HistoryView.swift
│       ├── ReportsView.swift
│       └── SettingsView.swift
└── Documentation/
    ├── PRODUCT_REQUIREMENTS.md
    ├── USER_GUIDE.md
    └── BRAND_GUIDELINES.md
```

## Architecture

- **Pattern:** MVVM (Model-View-ViewModel)
- **UI Framework:** SwiftUI
- **Persistence:** UserDefaults (local storage)

## Branding

- **Colors:** Navy Blue (#1E3A5F) + Green Accent (#34C759)
- **Vibe:** Clean, minimal, professional

## IRS Reference

### REPS Requirements
- **750-Hour Rule:** >750 hours of material participation annually
- **50% Rule:** Not more than 500 hours in other trade/business activities
- **Property Ownership:** At least 50% ownership in rental activities

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

## License

MIT License. See [LICENSE](LICENSE).

---

*For tax advice, consult a qualified tax professional.*
