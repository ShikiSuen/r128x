import Testing
import Foundation
@testable import EBUR128

// Additional regression tests for specific functionality
@Suite("Regression Tests for EBUR128 Functionality")
struct RegressionTests {
    
    @Test("Verify EBUR128 standard compliance")
    func testEBUR128StandardCompliance() async throws {
        let state = try EBUR128State(channels: 1, sampleRate: 48000, mode: [.I])
        
        // Generate a 1kHz sine wave at -20 dBFS (standard test signal)
        let amplitude = pow(10.0, -20.0 / 20.0) // -20 dBFS
        let frequency = 1000.0
        let sampleRate = 48000.0
        let duration = 5.0 // 5 seconds
        let frameCount = Int(sampleRate * duration)
        
        var sineWave = [Double]()
        for i in 0..<frameCount {
            let sample = amplitude * sin(2.0 * Double.pi * frequency * Double(i) / sampleRate)
            sineWave.append(sample)
        }
        
        // Process the audio
        try await state.addFrames([sineWave])
        
        // Get integrated loudness
        let loudness = try await state.loudnessGlobal()
        
        // For a 1kHz sine wave at -20 dBFS, integrated loudness should be approximately -20 LUFS
        #expect(loudness.isFinite)
        #expect(abs(loudness - (-20.0)) < 2.0, "Loudness should be approximately -20 LUFS, got \(loudness)")
    }
    
    @Test("Verify overflow protection in large buffer scenarios")
    func testLargeBufferOverflowProtection() async throws {
        // Test with parameters that could potentially cause overflow
        let state = try EBUR128State(channels: 8, sampleRate: 192000, mode: [.I, .LRA, .truePeak])
        
        #expect(state.channels == 8)
        #expect(state.sampleRate == 192000)
        
        // Process a large amount of data in chunks
        let chunkSize = 19200 // 0.1 seconds at 192kHz
        let audioData = [[Double]](
            repeating: Array(repeating: 0.01, count: chunkSize),
            count: 8
        )
        
        // Process multiple chunks to test overflow protection
        for _ in 0..<100 {
            try await state.addFrames(audioData)
        }
        
        let loudness = try await state.loudnessGlobal()
        #expect(loudness.isFinite || loudness == -Double.infinity)
    }
    
    @Test("Verify actor isolation and thread safety")
    func testActorIsolationThreadSafety() async throws {
        let state = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I, .samplePeak])
        
        // Test concurrent access
        await withTaskGroup(of: Void.self) { group in
            // Multiple tasks trying to add frames simultaneously
            for i in 0..<20 {
                group.addTask {
                    let amplitude = 0.01 * Double(i + 1)
                    let data = [[Double]](
                        repeating: Array(repeating: amplitude, count: 480),
                        count: 2
                    )
                    try? await state.addFrames(data)
                }
            }
            
            // Tasks trying to read measurements simultaneously
            for _ in 0..<10 {
                group.addTask {
                    _ = try? await state.loudnessGlobal()
                    _ = try? await state.samplePeak(channel: 0)
                }
            }
        }
        
        // Should not crash and should give reasonable results
        let finalLoudness = try await state.loudnessGlobal()
        let peak = try await state.samplePeak(channel: 0)
        
        #expect(finalLoudness.isFinite || finalLoudness == -Double.infinity)
        #expect(peak >= 0.0)
    }
    
    @Test("Verify filter coefficient stability")
    func testFilterCoefficientStability() async throws {
        // Test with various sample rates to ensure filter coefficients are stable
        let sampleRates: [UInt] = [44100, 48000, 88200, 96000, 176400, 192000]
        
        for sampleRate in sampleRates {
            let state = try EBUR128State(channels: 1, sampleRate: sampleRate, mode: [.I])
            
            let coeffA = await state.filterCoefA
            let coeffB = await state.filterCoefB
            
            // Verify coefficients are finite and reasonable
            for coef in coeffA {
                #expect(coef.isFinite, "Filter coefficient A should be finite at \(sampleRate)Hz")
                #expect(abs(coef) < 100.0, "Filter coefficient A should be reasonable at \(sampleRate)Hz")
            }
            
            for coef in coeffB {
                #expect(coef.isFinite, "Filter coefficient B should be finite at \(sampleRate)Hz")
                #expect(abs(coef) < 100.0, "Filter coefficient B should be reasonable at \(sampleRate)Hz")
            }
        }
    }
    
    @Test("Verify error handling defensive patterns")
    func testErrorHandlingDefensivePatterns() async throws {
        // Test all the defensive error cases
        
        // Invalid initialization parameters
        #expect(throws: EBUR128Error.noMem) {
            try EBUR128State(channels: 0, sampleRate: 48000, mode: [.I])
        }
        
        #expect(throws: EBUR128Error.noMem) {
            try EBUR128State(channels: 1000, sampleRate: 48000, mode: [.I])
        }
        
        #expect(throws: EBUR128Error.noMem) {
            try EBUR128State(channels: 2, sampleRate: 5, mode: [.I])
        }
        
        // Invalid channel operations
        let state = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I])
        
        #expect(throws: EBUR128Error.invalidChannelIndex) {
            try await state.setChannel(10, value: .left)
        }
        
        #expect(throws: EBUR128Error.duplicatedTypesAcrossChannels) {
            try await state.setChannels(since: 0, .left, .left)
        }
        
        // Invalid frame data
        #expect(throws: EBUR128Error.invalidChannelIndex) {
            try await state.addFrames([[], [], []]) // Wrong number of channels
        }
        
        // Invalid measurement requests
        #expect(throws: EBUR128Error.invalidChannelIndex) {
            try await state.samplePeak(channel: 10)
        }
    }
}