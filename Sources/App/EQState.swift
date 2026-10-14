enum EQState: Equatable {
  case active, paused, off, starting, unavailable, disconnected
  var label: String {
    switch self {
    case .active: return "On"
    case .paused: return "Paused"
    case .off: return "Off"
    case .starting: return "Starting"
    case .unavailable: return "Unavailable"
    case .disconnected: return "Disconnected"
    }
  }
}
