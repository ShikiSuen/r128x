import Foundation

/// Filter state for BS.1770 filtering
private typealias FilterState = [Double]

// MARK: - Constants

/// Constants used in the EBUR128 calculations
private enum Constants {
  static let relativeGate: Double = -10.0
  static let relativeGateFactor: Double = pow(10.0, relativeGate / 10.0)
  static let minusTwentyDecibels: Double = pow(10.0, -20.0 / 10.0)
  static let filterStateSize: Int = 5
  static let almostZero: Double = 0.000001

  /// Histogram related constants
  static var histogramEnergies: [Double] = {
    var energies = [Double](repeating: 0, count: 1000)
    for i in 0 ..< 1000 {
      energies[i] = pow(10.0, (Double(i) / 10.0 - 69.95 + 0.691) / 10.0)
    }
    return energies
  }()

  static var histogramEnergyBoundaries: [Double] = {
    var boundaries = [Double](repeating: 0, count: 1001)
    boundaries[0] = pow(10.0, (-70.0 + 0.691) / 10.0)
    for i in 1 ..< 1001 {
      boundaries[i] = pow(10.0, (Double(i) / 10.0 - 70.0 + 0.691) / 10.0)
    }
    return boundaries
  }()

  /// Find the histogram index for a given energy value
  static func findHistogramIndex(energy: Double) -> Int {
    var indexMin = 0
    var indexMax = 1000

    while indexMax - indexMin > 1 {
      let indexMid = (indexMin + indexMax) / 2
      if energy >= histogramEnergyBoundaries[indexMid] {
        indexMin = indexMid
      } else {
        indexMax = indexMid
      }
    }

    return indexMin
  }

  /// Convert energy to loudness in LUFS
  static func energyToLoudness(_ energy: Double) -> Double {
    10.0 * log10(energy) - 0.691
  }
}

// MARK: - Interpolator

/// Audio resampler for true-peak detection
private class Interpolator {
  // MARK: Lifecycle

  init?(taps: UInt, factor: UInt, channels: UInt) {
    self.taps = taps
    self.factor = factor
    self.channels = channels
    self.delay = (taps + factor - 1) / factor

    // Initialize filter array
    self.filter = [InterpFilter](
      repeating:
      InterpFilter(count: 0, index: [], coeff: []),
      count: Int(factor)
    )

    for j in 0 ..< factor {
      filter[Int(j)].index = [UInt](repeating: 0, count: Int(delay))
      filter[Int(j)].coeff = [Double](repeating: 0, count: Int(delay))
    }

    // Initialize delay buffers
    self.z = [[Float]](repeating: [Float](repeating: 0, count: Int(delay)), count: Int(channels))
    self.zi = 0

    // Calculate filter coefficients
    for j in 0 ..< taps {
      // Calculate sinc
      let m = Double(j) - Double(taps - 1) / 2.0
      var c = 1.0
      if abs(m) > Constants.almostZero {
        c = sin(m * .pi / Double(factor)) / (m * .pi / Double(factor))
      }

      // Apply Hanning window
      c *= 0.5 * (1.0 - cos(2.0 * .pi * Double(j) / Double(taps - 1)))

      if abs(c) > Constants.almostZero {
        // Put coefficient into correct subfilter
        let f = j % factor
        let t = filter[Int(f)].count
        filter[Int(f)].coeff[Int(t)] = c
        filter[Int(f)].index[Int(t)] = j / factor
        filter[Int(f)].count += 1
      }
    }
  }

  // MARK: Internal

  struct InterpFilter {
    var count: UInt
    var index: [UInt]
    var coeff: [Double]
  }

  let factor: UInt
  let taps: UInt
  let channels: UInt
  let delay: UInt
  var filter: [InterpFilter]
  var z: [[Float]]
  var zi: UInt

  func process(frames: Int, input: [Float], output: inout [Float]) -> Int {
    for frame in 0 ..< frames {
      for chan in 0 ..< Int(channels) {
        // Add sample to delay buffer
        z[chan][Int(zi)] = input[frame * Int(channels) + chan]

        // Apply coefficients
        var outp = chan
        for f in 0 ..< Int(factor) {
          var acc = 0.0
          for t in 0 ..< Int(filter[f].count) {
            var i = Int(zi) - Int(filter[f].index[t])
            if i < 0 {
              i += Int(delay)
            }
            let c = filter[f].coeff[t]
            acc += Double(z[chan][i]) * c
          }
          output[outp] = Float(acc)
          outp += Int(channels)
        }
      }

      output = Array(output.dropFirst(Int(channels) * Int(factor)))
      zi += 1
      if zi == delay {
        zi = 0
      }
    }

    return frames * Int(factor)
  }
}

// MARK: - EBUR128State

/// Main state class for EBU R128 loudness measurements
public class EBUR128State {
  // MARK: Lifecycle

  /// Create a new EBUR128State for loudness analysis
  /// - Parameters:
  ///   - channels: Number of audio channels
  ///   - samplerate: Sample rate in Hz
  ///   - mode: Processing modes
  public init?(channels: UInt, samplerate: UInt, mode: EBUR128.Mode) throws {
    // Validate parameters
    guard channels > 0, channels <= 64 else {
      throw EBUR128.Error.invalidChannelIndex
    }

    guard samplerate >= 16, samplerate <= 2_822_400 else {
      throw EBUR128.Error.invalidMode
    }

    self.channels = channels
    self.samplerate = samplerate
    self.mode = mode

    // Initialize channel map with default values
    self.channelMap = Array(repeating: .unused, count: Int(channels))
    if channels == 4 {
      channelMap[0] = .left
      channelMap[1] = .right
      channelMap[2] = .leftSurround
      channelMap[3] = .rightSurround
    } else if channels == 5 {
      channelMap[0] = .left
      channelMap[1] = .right
      channelMap[2] = .center
      channelMap[3] = .leftSurround
      channelMap[4] = .rightSurround
    } else {
      for i in 0 ..< Int(channels) {
        switch i {
        case 0: channelMap[i] = .left
        case 1: channelMap[i] = .right
        case 2: channelMap[i] = .center
        case 3: channelMap[i] = .unused
        case 4: channelMap[i] = .leftSurround
        case 5: channelMap[i] = .rightSurround
        default: channelMap[i] = .unused
        }
      }
    }

    // Initialize peak arrays
    self.samplePeak = Array(repeating: 0.0, count: Int(channels))
    self.prevSamplePeak = Array(repeating: 0.0, count: Int(channels))
    self.truePeak = Array(repeating: 0.0, count: Int(channels))
    self.prevTruePeak = Array(repeating: 0.0, count: Int(channels))

    // Set up window and history parameters
    self.useHistogram = mode.contains(.histogram)
    self.history = .max

    // Initialize block lists
    self.blockList = BlockQueue(maxSize: Int(history / 100))
    self.shortTermBlockList = BlockQueue(maxSize: Int(history / 3000))
    self.shortTermFrameCounter = 0

    if mode.contains(.shortTerm) {
      self.window = 3000
    } else if mode.contains(.momentary) {
      self.window = 400
    } else {
      throw EBUR128.Error.invalidMode
    }

    // Initialize samples and frames
    self.samplesIn100ms = (samplerate + 5) / 10
    self.audioDataFrames = Int(samplerate * window / 1000)

    // First block needs 400ms of audio data
    self.neededFrames = samplesIn100ms * 4

    // Round up to multiple of samples_in_100ms
    if audioDataFrames % Int(samplesIn100ms) != 0 {
      self.audioDataFrames = audioDataFrames + Int(samplesIn100ms) - (audioDataFrames % Int(samplesIn100ms))
    }

    // Allocate audio data buffer
    self.audioData = Array(repeating: 0.0, count: Int(channels) * audioDataFrames)
    self.audioDataIndex = 0

    // Initialzie some other variables

    // Initialize filter coefficients
    self.b = Array(repeating: 0.0, count: Constants.filterStateSize)
    self.a = Array(repeating: 0.0, count: Constants.filterStateSize)
    try Self.initFilter(a: &a, b: &b, sampleRate: Double(samplerate))

    self.v = Array(
      repeating: Array(repeating: 0.0, count: Constants.filterStateSize),
      count: Int(channels)
    )

    // Initialize histograms if needed
    if useHistogram {
      self.blockEnergyHistogram = Array(repeating: 0, count: 1000)
      self.shortTermBlockEnergyHistogram = Array(repeating: 0, count: 1000)
    } else {
      self.blockEnergyHistogram = nil
      self.shortTermBlockEnergyHistogram = nil
    }

    // Initialize resampler for true-peak detection
    self.interp = nil
    self.resamplerBufferInput = nil
    self.resamplerBufferOutput = nil
    self.resamplerBufferInputFrames = 0
    self.resamplerBufferOutputFrames = 0
    if mode.contains(.truePeak) {
      try initResampler()
    }
  }

  // MARK: Public

  /// Set the channel type for a specific channel
  /// - Parameters:
  ///   - channelNumber: Channel index (zero-based)
  ///   - value: Channel type
  /// - Returns: Success or error
  public func setChannel(channelNumber: UInt, value: EBUR128.Channel) throws {
    guard channelNumber < channels else {
      throw EBUR128.Error.invalidChannelIndex
    }

    if value == .dualMono, channels != 1 || channelNumber != 0 {
      throw EBUR128.Error.invalidChannelIndex
    }

    channelMap[Int(channelNumber)] = value
  }

  /// Add audio frames to be processed
  /// - Parameters:
  ///   - frames: Number of frames (not samples) to process
  ///   - src: Audio data, interleaved by channel
  /// - Returns: Success or error
  public func addFrames<T: BinaryFloatingPoint>(frames: Int, src: [T]) throws {
    // Reset peak values for this chunk
    for c in 0 ..< Int(channels) {
      prevSamplePeak[c] = 0.0
      prevTruePeak[c] = 0.0
    }

    var frameIndex = 0
    var remainingFrames = frames

    while remainingFrames > 0 {
      if remainingFrames >= Int(neededFrames) {
        // Process a complete block
        try filterFrames(
          frames: Int(neededFrames),
          src: src[(frameIndex * Int(channels))...],
          scaling: 1.0
        )

        frameIndex += Int(neededFrames)
        remainingFrames -= Int(neededFrames)
        audioDataIndex += Int(neededFrames) * Int(channels)

        // Calculate gating block if needed
        if mode.contains(.integrated) {
          _ = try calcGatingBlock(framesPerBlock: Int(samplesIn100ms * 4))
        }

        // Handle short-term processing for LRA calculation
        if mode.contains(.loudnessRange) {
          shortTermFrameCounter += Int(neededFrames)
          if shortTermFrameCounter == Int(samplesIn100ms * 30) {
            if let stEnergy = try? energyShortTerm() {
              if stEnergy >= Constants.histogramEnergyBoundaries[0] {
                if useHistogram {
                  shortTermBlockEnergyHistogram?[
                    Constants.findHistogramIndex(energy: stEnergy)
                  ] += 1
                } else {
                  shortTermBlockList.append(stEnergy)
                }
              }
            }
            shortTermFrameCounter = Int(samplesIn100ms * 20)
          }
        }

        // For blocks after the first, we need 100ms
        neededFrames = samplesIn100ms

        // Reset index at buffer end
        if audioDataIndex == audioDataFrames * Int(channels) {
          audioDataIndex = 0
        }
      } else {
        // Process remaining frames (less than needed)
        try filterFrames(
          frames: remainingFrames,
          src: src[(frameIndex * Int(channels))...],
          scaling: 1.0
        )

        audioDataIndex += remainingFrames * Int(channels)

        if mode.contains(.loudnessRange) {
          shortTermFrameCounter += remainingFrames
        }

        neededFrames -= UInt(remainingFrames)
        remainingFrames = 0
      }
    }

    // Update overall peak values
    for c in 0 ..< Int(channels) {
      if prevSamplePeak[c] > samplePeak[c] {
        samplePeak[c] = prevSamplePeak[c]
      }
      if prevTruePeak[c] > truePeak[c] {
        truePeak[c] = prevTruePeak[c]
      }
    }
  }

  // MARK: - Public API methods

  /// Get global integrated loudness in LUFS
  /// - Returns: Integrated loudness value or -infinity
  public func loudnessGlobal() throws -> Double {
    guard mode.contains(.integrated) else {
      throw EBUR128.Error.invalidMode
    }

    var relativeThreshold = 0.0
    var aboveThresholdCounter = 0

    // Calculate relative threshold
    if useHistogram, let histogram = blockEnergyHistogram {
      for i in 0 ..< 1000 {
        relativeThreshold += Double(histogram[i]) * Constants.histogramEnergies[i]
        aboveThresholdCounter += Int(histogram[i])
      }
    } else {
      blockList.forEach { energy in
        aboveThresholdCounter += 1
        relativeThreshold += energy
      }
    }

    if aboveThresholdCounter == 0 {
      return -.infinity
    }

    // Calculate gated loudness
    relativeThreshold /= Double(aboveThresholdCounter)
    relativeThreshold *= Constants.relativeGateFactor

    var gatedLoudness = 0.0
    aboveThresholdCounter = 0

    // Find blocks above threshold
    var startIndex: Int
    if relativeThreshold < Constants.histogramEnergyBoundaries[0] {
      startIndex = 0
    } else {
      startIndex = Constants.findHistogramIndex(energy: relativeThreshold)
      if relativeThreshold > Constants.histogramEnergies[startIndex] {
        startIndex += 1
      }
    }

    // Sum energy of blocks above threshold
    if useHistogram, let histogram = blockEnergyHistogram {
      for j in startIndex ..< 1000 {
        gatedLoudness += Double(histogram[j]) * Constants.histogramEnergies[j]
        aboveThresholdCounter += Int(histogram[j])
      }
    } else {
      blockList.forEach { energy in
        if energy >= relativeThreshold {
          gatedLoudness += energy
          aboveThresholdCounter += 1
        }
      }
    }

    if aboveThresholdCounter == 0 {
      return -.infinity
    }

    gatedLoudness /= Double(aboveThresholdCounter)
    return Constants.energyToLoudness(gatedLoudness)
  }

  /// Get momentary loudness (last 400ms) in LUFS
  /// - Returns: Momentary loudness value
  public func loudnessMomentary() throws -> Double {
    let energy = try energyInInterval(intervalFrames: Int(samplesIn100ms * 4))

    if energy <= 0.0 {
      return -.infinity
    }

    return Constants.energyToLoudness(energy)
  }

  /// Get short-term loudness (last 3s) in LUFS
  /// - Returns: Short-term loudness value
  public func loudnessShortterm() throws -> Double {
    guard mode.contains(.shortTerm) else {
      throw EBUR128.Error.invalidMode
    }

    let energy = try energyShortTerm()

    if energy <= 0.0 {
      return -.infinity
    }

    return Constants.energyToLoudness(energy)
  }

  /// Get loudness range (LRA) in LU
  /// - Returns: Loudness range value
  public func loudnessRange() throws -> Double {
    guard mode.contains(.loudnessRange) else {
      throw EBUR128.Error.invalidMode
    }

    if useHistogram, let histogram = shortTermBlockEnergyHistogram {
      var stlSize = 0
      var stlPower = 0.0

      // Calculate total energy and count
      for j in 0 ..< 1000 {
        stlSize += Int(histogram[j])
        stlPower += Double(histogram[j]) * Constants.histogramEnergies[j]
      }

      if stlSize == 0 {
        return 0.0
      }

      stlPower /= Double(stlSize)
      let stlIntegrated = Constants.minusTwentyDecibels * stlPower

      // Find starting index based on integrated level
      var index: Int
      if stlIntegrated < Constants.histogramEnergyBoundaries[0] {
        index = 0
      } else {
        index = Constants.findHistogramIndex(energy: stlIntegrated)
        if stlIntegrated > Constants.histogramEnergies[index] {
          index += 1
        }
      }

      // Count blocks above threshold
      stlSize = 0
      for j in index ..< 1000 {
        stlSize += Int(histogram[j])
      }

      if stlSize == 0 {
        return 0.0
      }

      // Calculate percentile thresholds
      let percentileLow = Int(Double(stlSize - 1) * 0.1 + 0.5)
      let percentileHigh = Int(Double(stlSize - 1) * 0.95 + 0.5)

      // Find energy at each percentile
      var count = 0
      var j = index
      var lowEnergy = 0.0
      var highEnergy = 0.0

      while count <= percentileLow {
        count += Int(histogram[j])
        lowEnergy = Constants.histogramEnergies[j]
        j += 1
      }

      while count <= percentileHigh {
        count += Int(histogram[j])
        highEnergy = Constants.histogramEnergies[j]
        j += 1
      }

      return Constants.energyToLoudness(highEnergy) - Constants.energyToLoudness(lowEnergy)
    } else {
      // Extract all short-term blocks
      var stlVector: [Double] = []
      shortTermBlockList.forEach { energy in
        stlVector.append(energy)
      }

      if stlVector.isEmpty {
        return 0.0
      }

      // Sort by energy level
      stlVector.sort()

      // Calculate average power
      let stlPower = stlVector.reduce(0.0, +) / Double(stlVector.count)
      let stlIntegrated = Constants.minusTwentyDecibels * stlPower

      // Filter to blocks above relative threshold
      let filteredVector = stlVector.filter { $0 >= stlIntegrated }

      if filteredVector.isEmpty {
        return 0.0
      }

      // Find percentile values
      let lowIndex = Int(Double(filteredVector.count - 1) * 0.1 + 0.5)
      let highIndex = Int(Double(filteredVector.count - 1) * 0.95 + 0.5)

      let lowEnergy = filteredVector[lowIndex]
      let highEnergy = filteredVector[highIndex]

      return Constants.energyToLoudness(highEnergy) - Constants.energyToLoudness(lowEnergy)
    }
  }

  /// Get loudness of the specified window in LUFS
  /// - Parameter window: Window duration in milliseconds
  /// - Returns: Loudness value
  public func loudnessWindow(windowMs: UInt) throws -> Double {
    guard windowMs <= window else {
      throw EBUR128.Error.invalidMode
    }

    let intervalFrames = Int(samplerate * windowMs / 1000)
    let energy = try energyInInterval(intervalFrames: intervalFrames)

    if energy <= 0.0 {
      return -.infinity
    }

    return Constants.energyToLoudness(energy)
  }

  /// Get maximum sample peak from all processed frames
  /// - Parameter channelNumber: Channel to query
  /// - Returns: Sample peak value (1.0 is 0 dBFS)
  public func samplePeak(channelNumber: UInt) throws -> Double {
    guard mode.contains(.samplePeak) else {
      throw EBUR128.Error.invalidMode
    }

    guard channelNumber < channels else {
      throw EBUR128.Error.invalidChannelIndex
    }

    return samplePeak[Int(channelNumber)]
  }

  /// Get maximum sample peak from the last processed frames
  /// - Parameter channelNumber: Channel to query
  /// - Returns: Sample peak value (1.0 is 0 dBFS)
  public func prevSamplePeak(channelNumber: UInt) throws -> Double {
    guard mode.contains(.samplePeak) else {
      throw EBUR128.Error.invalidMode
    }

    guard channelNumber < channels else {
      throw EBUR128.Error.invalidChannelIndex
    }

    return prevSamplePeak[Int(channelNumber)]
  }

  /// Get maximum true peak from all processed frames
  /// - Parameter channelNumber: Channel to query
  /// - Returns: True peak value (1.0 is 0 dBTP)
  public func truePeak(channelNumber: UInt) throws -> Double {
    guard mode.contains(.truePeak) else {
      throw EBUR128.Error.invalidMode
    }

    guard channelNumber < channels else {
      throw EBUR128.Error.invalidChannelIndex
    }

    return max(truePeak[Int(channelNumber)], samplePeak[Int(channelNumber)])
  }

  /// Get maximum true peak from the last processed frames
  /// - Parameter channelNumber: Channel to query
  /// - Returns: True peak value (1.0 is 0 dBTP)
  public func prevTruePeak(channelNumber: UInt) throws -> Double {
    guard mode.contains(.truePeak) else {
      throw EBUR128.Error.invalidMode
    }

    guard channelNumber < channels else {
      throw EBUR128.Error.invalidChannelIndex
    }

    return max(prevTruePeak[Int(channelNumber)], prevSamplePeak[Int(channelNumber)])
  }

  /// Get the relative threshold in LUFS
  /// - Returns: Relative threshold value
  public func relativeThreshold() throws -> Double {
    guard mode.contains(.integrated) else {
      throw EBUR128.Error.invalidMode
    }

    var relativeThreshold = 0.0
    var aboveThreshCounter = 0

    if useHistogram, let histogram = blockEnergyHistogram {
      for i in 0 ..< 1000 {
        relativeThreshold += Double(histogram[i]) * Constants.histogramEnergies[i]
        aboveThreshCounter += Int(histogram[i])
      }
    } else {
      blockList.forEach { energy in
        aboveThreshCounter += 1
        relativeThreshold += energy
      }
    }

    if aboveThreshCounter == 0 {
      return -70.0
    }

    relativeThreshold /= Double(aboveThreshCounter)
    relativeThreshold *= Constants.relativeGateFactor

    return Constants.energyToLoudness(relativeThreshold)
  }

  // MARK: Private

  private let mode: EBUR128.Mode
  private let channels: UInt
  private let samplerate: UInt

  // Audio data and processing buffers
  private var audioData: [Double]
  private var audioDataFrames: Int
  private var audioDataIndex: Int
  private var neededFrames: UInt
  private var channelMap: [EBUR128.Channel]
  private var samplesIn100ms: UInt

  // Filter coefficients
  private var b: [Double] // Nominator coefficients
  private var a: [Double] // Denominator coefficients
  private var v: [FilterState] // Filter states for each channel

  // Block energy storage
  private var blockList: BlockQueue
  private var shortTermBlockList: BlockQueue
  private var shortTermFrameCounter: Int

  // Histogram storage (when using histogram mode)
  private var useHistogram: Bool
  private var blockEnergyHistogram: [UInt]?
  private var shortTermBlockEnergyHistogram: [UInt]?

  // Peak measurements
  private var samplePeak: [Double]
  private var prevSamplePeak: [Double]
  private var truePeak: [Double]
  private var prevTruePeak: [Double]

  // Resampler for true-peak detection
  private var interp: Interpolator?
  private var resamplerBufferInput: [Float]?
  private var resamplerBufferInputFrames: Int
  private var resamplerBufferOutput: [Float]?
  private var resamplerBufferOutputFrames: Int

  // Configuration
  private var window: UInt
  private var history: UInt

  /// Initialize the BS.1770 filters
  private static func initFilter(a: inout [Double], b: inout [Double], sampleRate: Double) throws {
    // Pre-computed filter coefficients for BS.1770
    let f0 = 1681.974450955533
    let G = 3.999843853973347
    let Q = 0.7071752369554196

    let K: Double = tan(.pi * f0 / sampleRate)
    let Vh: Double = pow(10.0, G / 20.0)
    let Vb: Double = pow(Vh, 0.4996667741545416)

    var pb: [Double] = [0.0, 0.0, 0.0]
    var pa: [Double] = [1.0, 0.0, 0.0]
    let rb: [Double] = [1.0, -2.0, 1.0]
    var ra: [Double] = [1.0, 0.0, 0.0]

    let a0 = 1.0 + K / Q + K * K
    pb[0] = (Vh + Vb * K / Q + K * K) / a0
    pb[1] = 2.0 * (K * K - Vh) / a0
    pb[2] = (Vh - Vb * K / Q + K * K) / a0
    pa[1] = 2.0 * (K * K - 1.0) / a0
    pa[2] = (1.0 - K / Q + K * K) / a0

    let f1 = 38.13547087602444
    let Q1 = 0.5003270373238773
    let K1: Double = tan(.pi * f1 / sampleRate)

    ra[1] = 2.0 * (K1 * K1 - 1.0) / (1.0 + K1 / Q1 + K1 * K1)
    ra[2] = (1.0 - K1 / Q1 + K1 * K1) / (1.0 + K1 / Q1 + K1 * K1)

    // Combine filter coefficients
    b[0] = pb[0] * rb[0]
    b[1] = pb[0] * rb[1] + pb[1] * rb[0]
    b[2] = pb[0] * rb[2] + pb[1] * rb[1] + pb[2] * rb[0]
    b[3] = pb[1] * rb[2] + pb[2] * rb[1]
    b[4] = pb[2] * rb[2]

    a[0] = pa[0] * ra[0]
    a[1] = pa[0] * ra[1] + pa[1] * ra[0]
    a[2] = pa[0] * ra[2] + pa[1] * ra[1] + pa[2] * ra[0]
    a[3] = pa[1] * ra[2] + pa[2] * ra[1]
    a[4] = pa[2] * ra[2]
  }

  /// Initialize resampler for true-peak detection
  private func initResampler() throws {
    guard mode.contains(.truePeak) else {
      return
    }

    if samplerate < 96000 {
      self.interp = Interpolator(taps: 49, factor: 4, channels: channels)
    } else if samplerate < 192000 {
      self.interp = Interpolator(taps: 49, factor: 2, channels: channels)
    } else {
      return
    }

    guard let interp = interp else {
      throw EBUR128.Error.nomem
    }

    // Allocate resampler buffers
    resamplerBufferInputFrames = Int(samplesIn100ms * 4)
    resamplerBufferInput = [Float](
      repeating: 0.0,
      count: resamplerBufferInputFrames * Int(channels)
    )

    resamplerBufferOutputFrames = resamplerBufferInputFrames * Int(interp.factor)
    resamplerBufferOutput = [Float](
      repeating: 0.0,
      count: resamplerBufferOutputFrames * Int(channels)
    )
  }

  /// Filter frames of audio according to BS.1770 specification
  private func filterFrames<T: BinaryFloatingPoint>(frames: Int, src: ArraySlice<T>, scaling: Double) throws {
    guard frames > 0, frames <= audioDataFrames else {
      throw EBUR128.Error.invalidMode
    }

    // Process sample peak if needed
    if mode.contains(.samplePeak) {
      for c in 0 ..< Int(channels) {
        var max = 0.0
        for i in 0 ..< frames {
          let val = Double(src[i * Int(channels) + c])
          if abs(val) > max {
            max = abs(val)
          }
        }
        max /= scaling
        if max > prevSamplePeak[c] {
          prevSamplePeak[c] = max
        }
      }
    }

    // Process true peak if needed
    if mode.contains(.truePeak), let interp = interp,
       let inputBuffer = resamplerBufferInput,
       let outputBuffer = resamplerBufferOutput {
      // Copy samples to resampler input buffer
      for i in 0 ..< frames {
        for c in 0 ..< Int(channels) {
          resamplerBufferInput?[i * Int(channels) + c] =
            Float(Double(src[i * Int(channels) + c]) / scaling)
        }
      }

      // Process through resampler
      var outBuf = outputBuffer
      let framesOut = interp.process(
        frames: frames,
        input: inputBuffer,
        output: &outBuf
      )

      // Check for new peak values
      for i in 0 ..< framesOut {
        for c in 0 ..< Int(channels) {
          let val = Double(outBuf[i * Int(channels) + c])
          let peak = abs(val)

          if peak > prevTruePeak[c] {
            prevTruePeak[c] = peak
          }
        }
      }
    }

    // Apply BS.1770 filter to each channel
    for c in 0 ..< Int(channels) {
      // Skip unused channels
      if channelMap[c] == .unused {
        continue
      }

      for i in 0 ..< frames {
        // Apply filter
        v[c][0] =
          Double(src[i * Int(channels) + c]) / scaling - a[1] * v[c][1] - a[2] * v[c][2] - a[3] * v[c][3] - a[4]
            * v[c][4]

        let filtered = b[0] * v[c][0] + b[1] * v[c][1] + b[2] * v[c][2] + b[3] * v[c][3] + b[4] * v[c][4]

        let idx = audioDataIndex + i * Int(channels) + c
        let wrappedIdx = idx % (audioDataFrames * Int(channels))
        audioData[wrappedIdx] = filtered

        // Shift filter state
        v[c][4] = v[c][3]
        v[c][3] = v[c][2]
        v[c][2] = v[c][1]
        v[c][1] = v[c][0]
      }

      // Fix potential denormals
      for j in 1 ... 4 {
        if abs(v[c][j]) < Double.leastNormalMagnitude {
          v[c][j] = 0.0
        }
      }
    }
  }

  /// Calculate gating block from audio data
  private func calcGatingBlock(framesPerBlock: Int) throws -> Double {
    guard framesPerBlock <= audioDataFrames else {
      throw EBUR128.Error.invalidMode
    }

    var sum = 0.0

    for c in 0 ..< Int(channels) {
      if channelMap[c] == .unused {
        continue
      }

      var channelSum = 0.0

      // Handle audio data buffer wrap-around
      if audioDataIndex < framesPerBlock * Int(channels) {
        // Buffer has wrapped - need to consider audio from end and beginning
        for i in 0 ..< audioDataIndex / Int(channels) {
          let idx = i * Int(channels) + c
          channelSum += audioData[idx] * audioData[idx]
        }

        let minAudioDataFrames: Int = audioDataFrames - (framesPerBlock - audioDataIndex / Int(channels))
        for i in minAudioDataFrames ..< audioDataFrames {
          let idx = i * Int(channels) + c
          channelSum += audioData[idx] * audioData[idx]
        }
      } else {
        // Data is contiguous in the buffer
        let minAudioDataIndex = audioDataIndex / Int(channels) - framesPerBlock
        let maxAudioDataIndex = audioDataIndex / Int(channels)
        (minAudioDataIndex ..< maxAudioDataIndex).forEach { i in
          let idx = i * Int(channels) + c
          channelSum += audioData[idx] * audioData[idx]
        }
      }

      // Apply channel weighting
      switch channelMap[c] {
      case .leftSurround, .mm060, .mm090, .mp060, .mp090, .rightSurround:
        channelSum *= 1.41
      case .dualMono:
        channelSum *= 2.0
      default:
        break
      }

      sum += channelSum
    }

    // Normalize by number of frames
    sum /= Double(framesPerBlock)

    // Add to appropriate storage
    if sum >= Constants.histogramEnergyBoundaries[0] {
      if useHistogram {
        blockEnergyHistogram?[Constants.findHistogramIndex(energy: sum)] += 1
      } else {
        blockList.append(sum)
      }
    }

    return sum
  }

  // MARK: - Private helper methods

  /// Get energy in specific interval
  private func energyInInterval(intervalFrames: Int) throws -> Double {
    guard intervalFrames <= audioDataFrames else {
      throw EBUR128.Error.invalidMode
    }
    return try calcGatingBlock(framesPerBlock: intervalFrames)
  }

  /// Get short-term energy (3s window)
  private func energyShortTerm() throws -> Double {
    try energyInInterval(intervalFrames: Int(samplesIn100ms * 30))
  }
}

// MARK: - Convenience Extensions

extension EBUR128State {
  /// Add frames of different numeric types

  /// Add frames of 32-bit float data
  public func addFrames(frames: Int, srcFloat src: [Float]) throws {
    try addFrames(frames: frames, src: src)
  }

  /// Add frames of 64-bit float data
  public func addFrames(frames: Int, srcDouble src: [Double]) throws {
    try addFrames(frames: frames, src: src)
  }

  /// Add frames of 16-bit integer data
  public func addFrames(frames: Int, srcInt16 src: [Int16]) throws {
    // Convert to floating point and scale appropriately
    var floatData = [Float]()
    floatData.reserveCapacity(src.count)

    for sample in src {
      floatData.append(Float(sample) / Float(Int16.max))
    }

    try addFrames(frames: frames, src: floatData)
  }

  /// Add frames of 32-bit integer data
  public func addFrames(frames: Int, srcInt32 src: [Int32]) throws {
    // Convert to floating point and scale appropriately
    var floatData = [Float]()
    floatData.reserveCapacity(src.count)

    for sample in src {
      floatData.append(Float(sample) / Float(Int32.max))
    }

    try addFrames(frames: frames, src: floatData)
  }
}
