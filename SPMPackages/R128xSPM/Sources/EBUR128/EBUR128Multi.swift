import Foundation

/// Helper class for multi-instance EBUR128 loudness analysis
public class EBUR128Multi {
  // MARK: Public

  /// Get global integrated loudness across multiple instances
  /// - Parameter states: Array of EBUR128State instances
  /// - Returns: Integrated loudness in LUFS
  public static func loudnessGlobalMultiple(_ states: [EBUR128State]) throws -> Double {
    // Validate all states have proper mode
    for state in states {
      let threshold = (try? state.relativeThreshold()) ?? 0
      if threshold == 0 {
        throw EBUR128.Error.invalidMode
      }
    }

    // Calculate relative threshold across all states
    var relativeThreshold = 0.0
    var aboveThreshCounter = 0

    // Calculate gating threshold
    for state in states {
      if let threshold = try? state.relativeThreshold() {
        if threshold > -70.0 { // Not negative infinity
          let energy = pow(10.0, (threshold + 0.691) / 10.0) / Constants.relativeGateFactor
          let count = 1 // We only get one count per state, as we're using the pre-calculated threshold

          relativeThreshold += energy * Double(count)
          aboveThreshCounter += count
        }
      }
    }

    if aboveThreshCounter == 0 {
      return -.infinity
    }

    // Calculate relative threshold
    relativeThreshold /= Double(aboveThreshCounter)
    relativeThreshold *= Constants.relativeGateFactor

    // Get loudness with this threshold
    var gatedLoudness = 0.0
    aboveThreshCounter = 0

    // Re-analyze each state using the common threshold
    for state in states {
      if let energyThreshold = try? state.relativeThreshold() {
        let energy = pow(10.0, (energyThreshold + 0.691) / 10.0) / Constants.relativeGateFactor

        // Only include if energy is above our computed threshold
        if energy >= relativeThreshold {
          gatedLoudness += energy
          aboveThreshCounter += 1
        }
      }
    }

    if aboveThreshCounter == 0 {
      return -.infinity
    }

    gatedLoudness /= Double(aboveThreshCounter)
    return 10 * log10(gatedLoudness) - 0.691
  }

  /// Get loudness range across multiple instances
  /// - Parameter states: Array of EBUR128State instances
  /// - Returns: Loudness range in LU
  public static func loudnessRangeMultiple(_ states: [EBUR128State]) throws -> Double {
    // Validate all states have proper mode
    for state in states {
      let threshold = (try? state.relativeThreshold()) ?? 0
      if threshold == 0 {
        throw EBUR128.Error.invalidMode
      }
    }

    // Combine the loudness ranges
    var combinedLoudnessRange = 0.0
    var weightSum = 0.0

    for state in states {
      if let loudnessRange = try? state.loudnessRange() {
        // Weight by the duration of audio processed
        let weight = 1.0 // In a real implementation, this would be based on duration
        combinedLoudnessRange += loudnessRange * weight
        weightSum += weight
      }
    }

    if weightSum == 0 {
      return 0.0
    }

    return combinedLoudnessRange / weightSum
  }

  // MARK: Private

  /// Constants needed for multi-instance processing
  private enum Constants {
    static let relativeGateFactor: Double = pow(10.0, -10.0 / 10.0)
  }
}
