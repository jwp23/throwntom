import Foundation

// MARK: - StatsSummary

/// The `/v1/stats` dashboard. Keys are Go field names because the daemon encodes the analytics
/// struct without tags; decoded with `DaemonJSON.decoder`.
public struct StatsSummary: Equatable, Sendable {

  // MARK: Lifecycle

  public init(today: Period, thisWeek: Period, thisMonth: Period, allTime: Period, streaks: Streaks, patterns: Patterns) {
    self.today = today
    self.thisWeek = thisWeek
    self.thisMonth = thisMonth
    self.allTime = allTime
    self.streaks = streaks
    self.patterns = patterns
  }

  // MARK: Public

  public struct Period: Decodable, Equatable, Sendable {
    public init(pomodoros: Int, focusMinutes: Int, pauses: Int, snoozes: Int) {
      self.pomodoros = pomodoros
      self.focusMinutes = focusMinutes
      self.pauses = pauses
      self.snoozes = snoozes
    }

    public let pomodoros: Int
    public let focusMinutes: Int
    public let pauses: Int
    public let snoozes: Int

    enum CodingKeys: String, CodingKey {
      case pomodoros = "Pomodoros"
      case focusMinutes = "FocusMinutes"
      case pauses = "Pauses"
      case snoozes = "Snoozes"
    }
  }

  public struct Streaks: Decodable, Equatable, Sendable {
    public init(current: Int, longest: Int) {
      self.current = current
      self.longest = longest
    }

    public let current: Int
    public let longest: Int

    enum CodingKeys: String, CodingKey {
      case current = "Current"
      case longest = "Longest"
    }
  }

  public struct Patterns: Decodable, Equatable, Sendable {
    public init(bestDay: Int, bestHour: Int, snoozeRate: Double, pauseRate: Double) {
      self.bestDay = bestDay
      self.bestHour = bestHour
      self.snoozeRate = snoozeRate
      self.pauseRate = pauseRate
    }

    public let bestDay: Int
    public let bestHour: Int
    public let snoozeRate: Double
    public let pauseRate: Double

    enum CodingKeys: String, CodingKey {
      case bestDay = "BestDay"
      case bestHour = "BestHour"
      case snoozeRate = "SnoozeRate"
      case pauseRate = "PauseRate"
    }
  }

  public let today: Period
  public let thisWeek: Period
  public let thisMonth: Period
  public let allTime: Period
  public let streaks: Streaks
  public let patterns: Patterns

}

// MARK: Decodable

extension StatsSummary: Decodable {

  // MARK: Lifecycle

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    today = try container.decode(Period.self, forKey: .today)
    thisWeek = try container.decode(Period.self, forKey: .thisWeek)
    thisMonth = try container.decode(Period.self, forKey: .thisMonth)
    allTime = try container.decode(Period.self, forKey: .allTime)
    streaks = try container.decode(Streaks.self, forKey: .streaks)
    patterns = try container.decode(Patterns.self, forKey: .patterns)
  }

  // MARK: Internal

  enum CodingKeys: String, CodingKey {
    case today = "Today"
    case thisWeek = "ThisWeek"
    case thisMonth = "ThisMonth"
    case allTime = "AllTime"
    case streaks = "Streaks"
    case patterns = "Patterns"
  }

}

// MARK: - StatsRows

/// The stats panel's rows, formatted the way the TUI's `stats` command prints them.
public enum StatsRows {

  // MARK: Public

  public struct Row: Equatable, Sendable {
    public init(label: String, value: String) {
      self.label = label
      self.value = value
    }

    public let label: String
    public let value: String
  }

  public static func rows(_ s: StatsSummary) -> [Row] {
    let streak = s.streaks.current
    return [
      Row(label: "Today", value: period(s.today)),
      Row(label: "This week", value: period(s.thisWeek)),
      Row(label: "This month", value: period(s.thisMonth)),
      Row(label: "All time", value: period(s.allTime)),
      Row(label: "Streak", value: "\(streak) \(streak == 1 ? "day" : "days") (best \(s.streaks.longest))"),
      Row(label: "Best hour", value: "\(s.patterns.bestHour):00–\(s.patterns.bestHour + 1):00"),
    ]
  }

  public static func formatDuration(minutes: Int) -> String {
    guard minutes >= 60 else { return "\(minutes)m" }
    let (h, m) = minutes.quotientAndRemainder(dividingBy: 60)
    return m == 0 ? "\(h)h" : "\(h)h \(m)m"
  }

  // MARK: Private

  private static func period(_ p: StatsSummary.Period) -> String {
    "\(p.pomodoros) · \(formatDuration(minutes: p.focusMinutes))"
  }

}
