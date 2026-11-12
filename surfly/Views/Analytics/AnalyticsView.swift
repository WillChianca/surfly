import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Query(sort: \SurfLesson.start, order: .reverse) private var allLessons: [SurfLesson]

    private var completed: [SurfLesson] {
        allLessons.filter { $0.ownerID == auth.userID && $0.isCompleted }
            .sorted { ($0.actualStart ?? .distantPast) > ($1.actualStart ?? .distantPast) }
    }
    private var summary: ProgressSummary { ProgressSummary(lessons: allLessons, ownerID: auth.userID ?? "") }
    private var weeks: [WaterWeek] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let current = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return (-7...0).compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: offset, to: current),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let minutes = completed.filter {
                guard let date = $0.actualStart else { return false }
                return date >= start && date < end
            }.reduce(0) { $0 + ($1.waterMinutes ?? 0) }
            return WaterWeek(start: start, hours: Double(minutes) / 60)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SurflyPageHeader(eyebrow: "Your progress", title: "My Surf Journey")
                    Text("Quick Stats").font(.title3.weight(.bold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        stat("Total Classes", value: "\(summary.totalClasses)", unit: "completed", icon: "graduationcap", color: SurflyTheme.softMint)
                        stat("Time in Water", value: String(format: "%.1f", Double(summary.waterMinutes) / 60), unit: "hours logged", icon: "stopwatch", color: SurflyTheme.softMint)
                        stat("Current Streak", value: "\(summary.currentStreak)", unit: "weeks", icon: "flame", color: SurflyTheme.warmSand)
                    }
                    Text("All-time totals from sessions you confirmed. A streak counts consecutive Monday–Sunday weeks; it stays active until the end of the following week.")
                        .font(.caption2).foregroundStyle(SurflyTheme.mutedText)
                    SurflyCard {
                        Text("Time in Water").font(.headline)
                        Text("Your last eight weeks · hours logged").font(.caption).foregroundStyle(SurflyTheme.mutedText)
                        if completed.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "chart.xyaxis.line").font(.largeTitle).foregroundStyle(SurflyTheme.forecastTeal)
                                Text("Your journey starts with your first session").font(.subheadline.weight(.semibold))
                                Text("Open a lesson in My Schedule and log your actual time in the water.").font(.caption).foregroundStyle(SurflyTheme.mutedText)
                            }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 28)
                        } else {
                            Chart(weeks) { week in
                                BarMark(x: .value("Week starting", week.start, unit: .weekOfYear), y: .value("Hours", week.hours))
                                    .foregroundStyle(SurflyTheme.forecastTeal.gradient).cornerRadius(5)
                            }
                            .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                            .chartYAxisLabel("Hours")
                            .chartYScale(domain: 0...max(1, (weeks.map(\.hours).max() ?? 0) * 1.15))
                            .frame(height: 190)
                            .accessibilityLabel("Weekly time in water from completed sessions")
                        }
                    }
                    SurflyCard(color: SurflyTheme.softMint) {
                        Label("Pose & Pop-up Evolution", systemImage: "figure.surfing").font(.headline)
                        Text("Posture analysis will appear here when AI Coach is available. No posture scores have been recorded.")
                            .font(.subheadline).foregroundStyle(SurflyTheme.mutedText)
                    }
                    HStack {
                        Text("Session History").font(.title3.weight(.bold))
                        Spacer()
                        Text("Completed sessions").font(.caption).foregroundStyle(SurflyTheme.mutedText)
                    }
                    if completed.isEmpty {
                        Text("No completed sessions yet.").font(.subheadline).foregroundStyle(SurflyTheme.mutedText)
                    }
                    ForEach(completed) { lesson in
                        NavigationLink { LessonDetailView(lesson: lesson) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "map").font(.title2).foregroundStyle(SurflyTheme.forecastTeal)
                                    .frame(width: 54, height: 54).background(SurflyTheme.softMint, in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(lesson.beachName).font(.subheadline.weight(.semibold))
                                    Text("\(lesson.waterMinutes ?? 0) min in the water").font(.caption).foregroundStyle(SurflyTheme.mutedText)
                                }
                                Spacer()
                                if let date = lesson.actualStart {
                                    Text(ForecastClock.text(date, format: "d MMM yyyy", timeZone: lesson.beach.timeZone))
                                        .font(.caption2).foregroundStyle(SurflyTheme.mutedText)
                                }
                                Image(systemName: "chevron.right").font(.caption)
                            }.padding(.vertical, 5)
                        }.buttonStyle(.plain)
                        Divider()
                    }
                    if let name = summary.mostVisited {
                        SurflyCard(color: SurflyTheme.warmSand) {
                            HStack(spacing: 14) {
                                Image(systemName: "water.waves").font(.largeTitle).foregroundStyle(SurflyTheme.forecastTeal)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("MOST SURFED SPOT").font(.caption2.weight(.bold)).foregroundStyle(SurflyTheme.mutedText)
                                    Text(name).font(.headline)
                                    Text("\(summary.mostVisitedCount) completed sessions").font(.caption).foregroundStyle(SurflyTheme.mutedText)
                                }
                            }
                        }
                    }
                }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(SurflyTheme.background).foregroundStyle(SurflyTheme.darkSlate)
            .toolbar(.hidden, for: .navigationBar)
        }.tint(SurflyTheme.forecastTeal)
    }

    private func stat(_ title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(SurflyTheme.forecastTeal)
            Text(title).font(.caption2).foregroundStyle(SurflyTheme.mutedText)
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(unit).font(.caption2).foregroundStyle(SurflyTheme.mutedText)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(color, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct WaterWeek: Identifiable {
    var id: Date { start }
    let start: Date
    let hours: Double
}
