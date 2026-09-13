/// Negative-control fixture for macos/mutation-control.sh, planted into a scratch copy of the
/// package and never compiled in place. Its test checks 5 and -5 but not the boundary, so
/// `>` → `>=` must survive and `>` → `<` must be killed.
enum MutationControl {
  static func isPositive(_ value: Int) -> Bool {
    value > 0
  }
}
