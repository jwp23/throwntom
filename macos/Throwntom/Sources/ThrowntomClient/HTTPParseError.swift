public enum HTTPParseError: Error, Equatable {
  case headTooLarge
  case malformedStatusLine(String)
  case malformedChunkSize(String)
  case malformedChunkTerminator
}
