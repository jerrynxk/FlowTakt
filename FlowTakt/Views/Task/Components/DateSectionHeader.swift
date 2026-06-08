import SwiftUI

// MARK: - DateSectionHeader

struct DateSectionHeader: View {
    let date: Date

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(headerText)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Computed

    private var headerText: String {
        if date.isToday {
            return "今天"
        } else if date.isYesterday {
            return "昨天"
        } else {
            let calendar = Calendar.current
            if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
                return date.shortDateString
            } else {
                return date.fullDateString
            }
        }
    }

    private var iconName: String {
        if date.isToday {
            return "sun.max.fill"
        } else if date.isYesterday {
            return "moon.stars.fill"
        } else {
            return "calendar"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        DateSectionHeader(date: Date())
        Divider()
        DateSectionHeader(date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        Divider()
        DateSectionHeader(date: Calendar.current.date(byAdding: .day, value: -3, to: Date())!)
    }
    .padding()
}
