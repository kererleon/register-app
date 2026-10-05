// Desktop widget that shows the lessons of the current school week.
// The Register app writes the week to the shared app group container
// (see MainFlutterWindow.swift); this widget only reads it.

import SwiftUI
import WidgetKit

// MARK: - Data

struct Lesson: Codable, Hashable {
  let from: Int
  let to: Int
  let subject: String
  let short: String
  let room: String?
  let test: Bool
  let color: Int
  let start: String?
  let end: String?

  /// Whether this lesson is running right now on [day].
  func isNow(on day: SchoolDay, at date: Date = .now) -> Bool {
    guard isToday(day), let start, let end else { return false }
    let now = Lesson.clock.string(from: date)
    return start <= now && now < end
  }

  static let clock: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
  }()

  /// Short name for the widget. A nickname set in the app wins; otherwise
  /// known subjects get a fixed abbreviation and others are shortened.
  var abbreviation: String {
    if short != subject { return short }
    return Lesson.abbreviate(subject)
  }

  static let knownAbbreviations: [String: String] = [
    "deutsch": "Deu",
    "englisch": "Eng",
    "italienisch": "Ita",
    "mathematik": "Mathe",
    "geschichte": "Gesch",
    "informatik": "Info",
    "religion": "Rel",
    "bewegung und sport": "BuS",
    "systeme und netze": "SN",
    "telekommunikation": "TK",
    "technologie und planung": "TP",
  ]

  static func abbreviate(_ subject: String) -> String {
    let key = subject.lowercased().trimmingCharacters(in: .whitespaces)
    if let known = knownAbbreviations[key] { return known }
    let words = subject.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "/" })
    if words.count > 1 {
      // "Systeme und Netze" -> "SN", "Bewegung und Sport" -> "BuS"
      return words.map { word in
        word.lowercased() == "und" ? "u" : String(word.prefix(1)).uppercased()
      }.joined()
    }
    return subject.count <= 5 ? subject : String(subject.prefix(4))
  }

  var swiftColor: Color { Color(hex: color) }
}

struct SchoolDay: Codable, Hashable {
  let date: String
  let weekday: String
  let loaded: Bool
  let lessons: [Lesson]

  var parsedDate: Date? { Self.formatter.date(from: date) }

  static let formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "de_DE")
    return f
  }()
}

struct TaskItem: Codable, Hashable {
  let date: String
  let label: String?
  let title: String
  let subtitle: String?
  let test: Bool
  let done: Bool
  let color: Int?

  var parsedDate: Date? { SchoolDay.formatter.date(from: date) }
  var swiftColor: Color { color.map(Color.init(hex:)) ?? Holo.violet }
  var subjectShort: String? { label.map(Lesson.abbreviate) }
}

struct GradeItem: Codable, Hashable {
  let subject: String
  let short: String
  let average: Double
  let color: Int

  var abbreviation: String { short != subject ? short : Lesson.abbreviate(subject) }
}

struct Week: Codable {
  let updated: String
  let monday: String
  let days: [SchoolDay]
  var tasks: [TaskItem]? = nil
  var grades: [GradeItem]? = nil
  var overall: Double? = nil
  var semester: String? = nil
}

extension Color {
  init(hex: Int) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }
}

enum WeekStore {
  static func load() -> Week? {
    guard
      let group = Bundle.main.object(forInfoDictionaryKey: "RegisterAppGroup") as? String,
      let url = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("week.json"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? JSONDecoder().decode(Week.self, from: data)
  }

  static let sample = Week(
    updated: "",
    monday: "",
    days: ["Mo", "Di", "Mi", "Do", "Fr"].enumerated().map { index, weekday in
      let subjects: [(String, Int)] = [
        ("Mathematik", 0x7C5CFF), ("Deutsch", 0x22D3EE), ("Englisch", 0x2DD4A3),
        ("Informatik", 0xF5B544), ("Italienisch", 0xFF5C7A), ("TP", 0x60A5FA),
      ]
      let lessons = (0..<5).map { hour -> Lesson in
        let (name, color) = subjects[(hour + index) % subjects.count]
        return Lesson(
          from: hour + 1, to: hour + 1, subject: name, short: name,
          room: "R\(100 + hour)", test: hour == 2 && index == 3, color: color,
          start: nil, end: nil)
      }
      return SchoolDay(date: "", weekday: weekday, loaded: true, lessons: lessons)
    },
    tasks: [
      TaskItem(date: "", label: "Mathematik", title: "Schularbeit", subtitle: "Kapitel 3–5",
        test: true, done: false, color: 0x7C5CFF),
      TaskItem(date: "", label: "Deutsch", title: "Erörterung fertig schreiben", subtitle: nil,
        test: false, done: false, color: 0x22D3EE),
      TaskItem(date: "", label: "Englisch", title: "Vokabeln Unit 4", subtitle: nil,
        test: false, done: true, color: 0x2DD4A3),
    ],
    grades: [
      GradeItem(subject: "Mathematik", short: "Mathematik", average: 5.75, color: 0x7C5CFF),
      GradeItem(subject: "Deutsch", short: "Deutsch", average: 7.25, color: 0x22D3EE),
      GradeItem(subject: "Englisch", short: "Englisch", average: 8.5, color: 0x2DD4A3),
      GradeItem(subject: "Informatik", short: "Informatik", average: 9.0, color: 0xF5B544),
    ],
    overall: 7.6,
    semester: "1. Semester")
}

// MARK: - Timeline

struct WeekEntry: TimelineEntry {
  let date: Date
  let week: Week?
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> WeekEntry {
    WeekEntry(date: .now, week: WeekStore.sample)
  }

  func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
    completion(WeekEntry(date: .now, week: WeekStore.load() ?? WeekStore.sample))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
    let week = WeekStore.load()
    // One entry now and one at every lesson start and end today, so that the
    // running lesson is marked; afterwards redraw after midnight.
    var dates: [Date] = [.now]
    if let today = week?.days.first(where: isToday) {
      let calendar = Calendar.current
      for lesson in today.lessons {
        for time in [lesson.start, lesson.end].compactMap({ $0 }) {
          let parts = time.split(separator: ":").compactMap { Int($0) }
          if parts.count == 2,
            let date = calendar.date(
              bySettingHour: parts[0], minute: parts[1], second: 0, of: .now),
            date > .now
          {
            dates.append(date)
          }
        }
      }
    }
    let entries = Set(dates).sorted().map { WeekEntry(date: $0, week: week) }
    let tomorrow = Calendar.current.startOfDay(
      for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
    completion(Timeline(entries: entries, policy: .after(tomorrow)))
  }
}

// MARK: - Style

enum Holo {
  static let night = Color(red: 0.039, green: 0.055, blue: 0.102)
  static let violet = Color(red: 0.486, green: 0.361, blue: 1.0)
  static let cyan = Color(red: 0.133, green: 0.827, blue: 0.933)
  static let danger = Color(red: 1.0, green: 0.361, blue: 0.478)
  static let muted = Color(red: 0.6, green: 0.64, blue: 0.77)
  static let accent = LinearGradient(
    colors: [violet, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)

  static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }
}

struct HoloBackground: View {
  var body: some View {
    ZStack {
      Holo.night
      RadialGradient(
        colors: [Holo.violet.opacity(0.45), .clear], center: .topLeading,
        startRadius: 0, endRadius: 260)
      RadialGradient(
        colors: [Holo.cyan.opacity(0.22), .clear], center: .bottomTrailing,
        startRadius: 0, endRadius: 220)
    }
  }
}

struct Header: View {
  let title: String
  let subtitle: String
  var size: CGFloat = 13

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(.system(size: size, weight: .bold))
        .foregroundStyle(Holo.accent)
      Spacer()
      Text(subtitle.uppercased())
        .font(Holo.mono(size * 0.72))
        .tracking(1.2)
        .foregroundStyle(Holo.muted)
    }
  }
}

struct LessonChip: View {
  let lesson: Lesson
  var showRoom = false
  var compact = false
  var fontSize: CGFloat? = nil
  var isNow = false

  var body: some View {
    HStack(spacing: 5) {
      RoundedRectangle(cornerRadius: 2)
        .fill(lesson.swiftColor)
        .frame(width: compact ? 3 : 4)
        .shadow(color: lesson.swiftColor.opacity(0.9), radius: 3)
        .widgetAccentable()
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 3) {
          Text(lesson.abbreviation)
            .font(.system(size: fontSize ?? (compact ? 12 : 14), weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          if lesson.test {
            Image(systemName: "bolt.fill")
              .font(.system(size: (fontSize ?? 12) * 0.7))
              .foregroundStyle(Holo.danger)
          }
        }
        if showRoom, let room = lesson.room {
          Text(room)
            .font(Holo.mono((fontSize ?? 12) * 0.55, .medium))
            .foregroundStyle(Holo.muted)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, compact ? 2 : 4)
    .padding(.leading, 1)
    .padding(.trailing, 4)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(
      (isNow ? Holo.cyan.opacity(0.28) : lesson.swiftColor.opacity(0.16)),
      in: RoundedRectangle(cornerRadius: 6)
    )
    .overlay {
      if isNow {
        RoundedRectangle(cornerRadius: 6)
          .stroke(Holo.cyan, lineWidth: 1.5)
          .shadow(color: Holo.cyan.opacity(0.9), radius: 4)
          .widgetAccentable()
      }
    }
  }
}

/// The weekday label; today is marked so that it stays readable when macOS
/// shows desktop widgets desaturated.
struct WeekdayLabel: View {
  @Environment(\.widgetRenderingMode) private var renderingMode
  let day: SchoolDay
  var size: CGFloat = 9

  var body: some View {
    let today = isToday(day)
    let full = renderingMode == .fullColor
    Text(day.weekday.uppercased())
      .font(Holo.mono(size, .bold))
      .tracking(1)
      .foregroundStyle(today ? (full ? Color.white : Color.primary) : Holo.muted)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 3)
      .background {
        if today {
          if full {
            Capsule().fill(Holo.accent).shadow(color: Holo.violet.opacity(0.7), radius: 5)
          } else {
            Capsule().stroke(Color.primary, lineWidth: 1.2).widgetAccentable()
          }
        }
      }
  }
}

struct EmptyHint: View {
  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "calendar.badge.clock")
        .font(.system(size: 22))
        .foregroundStyle(Holo.accent)
      Text("Öffne Register, um deinen Stundenplan zu laden.")
        .font(.system(size: 11, weight: .medium))
        .multilineTextAlignment(.center)
        .foregroundStyle(Holo.muted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

func isToday(_ day: SchoolDay) -> Bool {
  guard let date = day.parsedDate else { return false }
  return Calendar.current.isDateInToday(date)
}

/// Today, or the next school day of the week when today is over or free.
private func focusDay(in week: Week) -> SchoolDay? {
  let today = Calendar.current.startOfDay(for: .now)
  return week.days.first { day in
    guard let date = day.parsedDate else { return false }
    return date >= today && !day.lessons.isEmpty
  } ?? week.days.first { !$0.lessons.isEmpty }
}

private func weekRange(_ week: Week) -> String {
  let dates = week.days.compactMap(\.parsedDate)
  guard let first = dates.first, let last = dates.last else { return "Diese Woche" }
  let f = DateFormatter()
  f.dateFormat = "dd.MM."
  return "\(f.string(from: first)) – \(f.string(from: last))"
}

// MARK: - Views

struct SmallView: View {
  let week: Week
  var date: Date = .now

  var body: some View {
    if let day = focusDay(in: week) {
      VStack(alignment: .leading, spacing: 6) {
        Header(
          title: isToday(day) ? "Heute" : day.weekday, subtitle: "\(day.lessons.count) Std",
          size: 15)
        VStack(spacing: 3) {
          ForEach(day.lessons.prefix(7), id: \.self) { lesson in
            HStack(spacing: 5) {
              Text("\(lesson.from)")
                .font(Holo.mono(11, .bold))
                .foregroundStyle(Holo.muted)
                .frame(width: 14, alignment: .trailing)
              LessonChip(
                lesson: lesson, compact: true, fontSize: 13, isNow: lesson.isNow(on: day, at: date))
            }
          }
        }
        Spacer(minLength: 0)
      }
    } else {
      EmptyHint()
    }
  }
}

struct MediumView: View {
  let week: Week
  var date: Date = .now

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Header(title: "Register · Woche", subtitle: "Mo – Fr", size: 14)
      HStack(alignment: .top, spacing: 5) {
        ForEach(week.days, id: \.self) { day in
          DayColumn(day: day, compact: true, date: date)
        }
      }
      Spacer(minLength: 0)
    }
  }
}

struct DayColumn: View {
  let day: SchoolDay
  var compact = false
  var showRoom = false
  var date: Date = .now

  var body: some View {
    let today = isToday(day)
    VStack(spacing: 3) {
      WeekdayLabel(day: day, size: 10.5)
      if day.lessons.isEmpty {
        Text(day.loaded ? "frei" : "–")
          .font(Holo.mono(9))
          .foregroundStyle(Holo.muted)
          .padding(.top, 4)
      }
      ForEach(day.lessons, id: \.self) { lesson in
        LessonChip(
          lesson: lesson, showRoom: showRoom, compact: compact, fontSize: 13,
          isNow: lesson.isNow(on: day, at: date))
      }
    }
    .padding(3)
    .frame(maxWidth: .infinity, alignment: .top)
    .background {
      if today {
        RoundedRectangle(cornerRadius: 8)
          .stroke(Holo.cyan.opacity(0.5), lineWidth: 1)
      }
    }
  }
}

struct LargeView: View {
  let week: Week
  var extraLarge = false
  var date: Date = .now

  var body: some View {
    let maxHour = week.days.flatMap(\.lessons).map(\.to).max() ?? 6
    VStack(alignment: .leading, spacing: 8) {
      Header(
        title: "Register · Stundenplan", subtitle: weekRange(week),
        size: extraLarge ? 18 : 16)
      Grid(horizontalSpacing: extraLarge ? 6 : 4, verticalSpacing: extraLarge ? 5 : 4) {
        GridRow {
          Text("").frame(width: extraLarge ? 22 : 18)
          ForEach(week.days, id: \.self) { day in
            WeekdayLabel(day: day, size: extraLarge ? 14 : 12)
          }
        }
        ForEach(1...max(maxHour, 1), id: \.self) { hour in
          GridRow {
            Text("\(hour)")
              .font(Holo.mono(extraLarge ? 15 : 13, .bold))
              .foregroundStyle(Holo.muted)
              .frame(width: extraLarge ? 22 : 18)
            ForEach(week.days, id: \.self) { day in
              if let lesson = day.lessons.first(where: { $0.from <= hour && hour <= $0.to }) {
                LessonChip(
                  lesson: lesson, showRoom: extraLarge, compact: false,
                  fontSize: extraLarge ? 22 : 17, isNow: lesson.isNow(on: day, at: date))
              } else {
                RoundedRectangle(cornerRadius: 5)
                  .stroke(Color.white.opacity(0.06), lineWidth: 1)
                  .frame(maxWidth: .infinity, maxHeight: .infinity)
              }
            }
          }
        }
      }
      Spacer(minLength: 0)
    }
  }
}

struct RegisterWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: WeekEntry

  var body: some View {
    Group {
      if let week = entry.week {
        switch family {
        case .systemSmall: SmallView(week: week, date: entry.date)
        case .systemLarge: LargeView(week: week, date: entry.date)
        case .systemExtraLarge: LargeView(week: week, extraLarge: true, date: entry.date)
        default: MediumView(week: week, date: entry.date)
        }
      } else {
        EmptyHint()
      }
    }
    .environment(\.colorScheme, .dark)
    .containerBackground(for: .widget) { HoloBackground() }
  }
}

@main
struct RegisterWidgets: WidgetBundle {
  var body: some Widget {
    RegisterWidget()
    TasksWidget()
    GradesWidget()
  }
}

struct RegisterWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "RegisterWeek", provider: Provider()) { entry in
      RegisterWidgetView(entry: entry)
    }
    .configurationDisplayName("Stundenplan")
    .description("Deine Fächer dieser Woche aus Register.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
  }
}

#Preview(as: .systemMedium) {
  RegisterWidget()
} timeline: {
  WeekEntry(date: .now, week: WeekStore.sample)
}

// MARK: - Tests & Aufgaben

private func countdown(to date: Date?, from now: Date = .now) -> (Int, String) {
  guard let date else { return (0, "") }
  let calendar = Calendar.current
  let days = calendar.dateComponents(
    [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
  ).day ?? 0
  switch days {
  case ..<1: return (0, "Heute")
  case 1: return (1, "Morgen")
  default: return (days, "in \(days) Tagen")
  }
}

private func dayLabel(_ date: Date?) -> String {
  guard let date else { return "" }
  let f = DateFormatter()
  f.locale = Locale(identifier: "de_DE")
  f.dateFormat = "EE dd.MM."
  return f.string(from: date).uppercased()
}

struct TaskRow: View {
  let task: TaskItem
  var size: CGFloat = 12

  var body: some View {
    let (days, text) = countdown(to: task.parsedDate)
    HStack(spacing: 6) {
      RoundedRectangle(cornerRadius: 2)
        .fill(task.test ? Holo.danger : task.swiftColor)
        .frame(width: 3)
        .widgetAccentable()
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 4) {
          if task.test {
            Image(systemName: "bolt.fill").font(.system(size: size * 0.75))
              .foregroundStyle(Holo.danger)
          }
          if let short = task.subjectShort {
            Text(short).font(.system(size: size, weight: .bold)).foregroundStyle(.white)
          }
          Text(task.title)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.white.opacity(task.done ? 0.45 : 0.9))
            .strikethrough(task.done)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      Text(days <= 1 ? text.uppercased() : dayLabel(task.parsedDate))
        .font(Holo.mono(size * 0.72, .bold))
        .foregroundStyle(days <= 1 ? (task.test ? Holo.danger : Holo.cyan) : Holo.muted)
    }
    .padding(.vertical, 3)
    .padding(.trailing, 4)
    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
  }
}

struct TasksView: View {
  @Environment(\.widgetFamily) private var family
  let week: Week

  var body: some View {
    let open = (week.tasks ?? []).filter { !$0.done || $0.test }
    let nextTest = open.first(where: \.test)
    switch family {
    case .systemSmall:
      VStack(alignment: .leading, spacing: 4) {
        Header(title: "Nächster Test", subtitle: "", size: 13)
        if let test = nextTest {
          let (days, text) = countdown(to: test.parsedDate)
          Spacer(minLength: 0)
          Text(days <= 1 ? "!" : "\(days)")
            .font(Holo.mono(46, .heavy))
            .foregroundStyle(Holo.accent)
          Text(days <= 1 ? text : "Tage")
            .font(Holo.mono(11, .bold))
            .foregroundStyle(Holo.muted)
          Text(test.subjectShort ?? test.title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
          Text(test.title)
            .font(.system(size: 11))
            .foregroundStyle(Holo.muted)
            .lineLimit(1)
        } else {
          Spacer()
          Text("Keine Tests in Sicht")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Holo.muted)
          Spacer()
        }
      }
    default:
      let limit = family == .systemMedium ? 4 : 11
      VStack(alignment: .leading, spacing: 5) {
        Header(
          title: "Register · Tests & Aufgaben",
          subtitle: "\(open.count) offen", size: 14)
        if open.isEmpty {
          EmptyHint()
        }
        ForEach(open.prefix(limit), id: \.self) { task in
          TaskRow(task: task, size: family == .systemMedium ? 12 : 13.5)
        }
        Spacer(minLength: 0)
      }
    }
  }
}

struct TasksWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "RegisterTasks", provider: Provider()) { entry in
      Group {
        if let week = entry.week { TasksView(week: week) } else { EmptyHint() }
      }
      .environment(\.colorScheme, .dark)
      .containerBackground(for: .widget) { HoloBackground() }
    }
    .configurationDisplayName("Tests & Aufgaben")
    .description("Countdown zum nächsten Test und deine offenen Aufgaben.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

// MARK: - Notendurchschnitt

private func gradeColor(_ grade: Double) -> Color {
  if grade < 6 { return Holo.danger }
  if grade < 7 { return Color(red: 0.96, green: 0.71, blue: 0.27) }
  if grade < 8.5 { return Holo.violet }
  return Holo.cyan
}

private func gradeText(_ grade: Double) -> String {
  String(format: "%.2f", grade).replacingOccurrences(of: ".", with: ",")
}

struct GradeRing: View {
  let value: Double
  let label: String
  var size: CGFloat = 56
  var stroke: CGFloat = 5

  var body: some View {
    let color = gradeColor(value)
    ZStack {
      Circle().stroke(Color.white.opacity(0.1), lineWidth: stroke)
      Circle()
        .trim(from: 0, to: min(max(value / 10, 0), 1))
        .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .shadow(color: color.opacity(0.8), radius: 4)
        .widgetAccentable()
      Text(label)
        .font(Holo.mono(size * 0.24, .bold))
        .foregroundStyle(.white)
        .minimumScaleFactor(0.6)
        .padding(stroke + 2)
    }
    .frame(width: size, height: size)
  }
}

struct GradesView: View {
  @Environment(\.widgetFamily) private var family
  let week: Week

  var body: some View {
    let grades = week.grades ?? []
    if grades.isEmpty {
      EmptyHint()
    } else {
      switch family {
      case .systemSmall:
        VStack(spacing: 6) {
          Header(title: "Ø Noten", subtitle: "", size: 13)
          Spacer(minLength: 0)
          GradeRing(value: week.overall ?? 0, label: gradeText(week.overall ?? 0), size: 86, stroke: 8)
          Spacer(minLength: 0)
          if let worst = grades.first, worst.average < 6 {
            Text("\(worst.abbreviation) unter 6")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(Holo.danger)
          }
        }
      case .systemMedium:
        HStack(spacing: 14) {
          VStack(spacing: 4) {
            GradeRing(value: week.overall ?? 0, label: gradeText(week.overall ?? 0), size: 84, stroke: 8)
            Text("GESAMT").font(Holo.mono(9, .bold)).foregroundStyle(Holo.muted)
          }
          VStack(alignment: .leading, spacing: 5) {
            Header(title: "Schwächste Fächer", subtitle: week.semester ?? "", size: 12)
            ForEach(grades.prefix(4), id: \.self) { grade in
              GradeBar(grade: grade)
            }
            Spacer(minLength: 0)
          }
        }
      default:
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Header(title: "Register · Noten", subtitle: week.semester ?? "", size: 15)
          }
          HStack(spacing: 12) {
            GradeRing(value: week.overall ?? 0, label: gradeText(week.overall ?? 0), size: 70, stroke: 7)
            Text("Gesamtdurchschnitt")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.white)
          }
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
            ForEach(grades.sorted { $0.subject < $1.subject }.prefix(16), id: \.self) { grade in
              VStack(spacing: 3) {
                GradeRing(value: grade.average, label: gradeText(grade.average), size: 46, stroke: 4)
                Text(grade.abbreviation)
                  .font(.system(size: 11, weight: .bold))
                  .foregroundStyle(.white)
                  .lineLimit(1)
              }
            }
          }
          Spacer(minLength: 0)
        }
      }
    }
  }
}

struct GradeBar: View {
  let grade: GradeItem

  var body: some View {
    let color = gradeColor(grade.average)
    HStack(spacing: 6) {
      Text(grade.abbreviation)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 44, alignment: .leading)
        .lineLimit(1)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.white.opacity(0.08))
          Capsule().fill(color)
            .frame(width: geo.size.width * min(max(grade.average / 10, 0), 1))
            .shadow(color: color.opacity(0.8), radius: 3)
            .widgetAccentable()
        }
      }
      .frame(height: 6)
      Text(gradeText(grade.average))
        .font(Holo.mono(10.5, .bold))
        .foregroundStyle(color)
        .frame(width: 34, alignment: .trailing)
    }
  }
}

struct GradesWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "RegisterGrades", provider: Provider()) { entry in
      Group {
        if let week = entry.week { GradesView(week: week) } else { EmptyHint() }
      }
      .environment(\.colorScheme, .dark)
      .containerBackground(for: .widget) { HoloBackground() }
    }
    .configurationDisplayName("Notendurchschnitt")
    .description("Dein Gesamtdurchschnitt und die Fächer, bei denen es knapp wird.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
