/// Path segment of POST /v1/timer/{verb}.
public enum TimerVerb: String, Sendable {
  case start
  case confirm
  case pause
  case resume
  case skip
  case skipToday = "skip-today"
  case newCycle = "new-cycle"
  case lunch
  case unsnooze
}
