#include "ebur128.h"
#include "gtest/gtest.h"
#include <cmath>
#include <vector>
#include <chrono>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

class EBUR128Test : public ::testing::Test {
protected:
    void SetUp() override {
        // Common setup for each test
    }
    
    void TearDown() override {
        // Common cleanup for each test
    }
    
    // Helper function to generate sine wave
    std::vector<float> generateSineWave(double frequency, double amplitude, 
                                       int sampleRate, int channels, double duration) {
        int totalFrames = static_cast<int>(sampleRate * duration);
        std::vector<float> samples(totalFrames * channels);
        
        for (int frame = 0; frame < totalFrames; ++frame) {
            double t = static_cast<double>(frame) / sampleRate;
            float value = static_cast<float>(amplitude * sin(2.0 * M_PI * frequency * t));
            
            for (int ch = 0; ch < channels; ++ch) {
                samples[frame * channels + ch] = value;
            }
        }
        
        return samples;
    }
    
    // Helper function to generate silence
    std::vector<float> generateSilence(int sampleRate, int channels, double duration) {
        int totalFrames = static_cast<int>(sampleRate * duration);
        std::vector<float> samples(totalFrames * channels, 0.0f);
        return samples;
    }
};

// Test basic library initialization and destruction
TEST_F(EBUR128Test, BasicInitializationAndDestruction) {
    ebur128_state* st = ebur128_init(2, 48000, EBUR128_MODE_I | EBUR128_MODE_LRA | EBUR128_MODE_TRUE_PEAK);
    ASSERT_NE(st, nullptr);
    
    EXPECT_EQ(st->channels, 2u);
    EXPECT_EQ(st->samplerate, 48000ul);
    EXPECT_EQ(st->mode, EBUR128_MODE_I | EBUR128_MODE_LRA | EBUR128_MODE_TRUE_PEAK);
    
    ebur128_destroy(&st);
    EXPECT_EQ(st, nullptr);
}

// Test library version information
TEST_F(EBUR128Test, VersionInformation) {
    int major, minor, patch;
    ebur128_get_version(&major, &minor, &patch);
    
    EXPECT_GT(major, 0);
    EXPECT_GE(minor, 0);
    EXPECT_GE(patch, 0);
}

// Test channel mapping
TEST_F(EBUR128Test, ChannelMapping) {
    ebur128_state* st = ebur128_init(2, 48000, EBUR128_MODE_I);
    ASSERT_NE(st, nullptr);
    
    EXPECT_EQ(ebur128_set_channel(st, 0, EBUR128_LEFT), EBUR128_SUCCESS);
    EXPECT_EQ(ebur128_set_channel(st, 1, EBUR128_RIGHT), EBUR128_SUCCESS);
    
    // Test invalid channel index
    EXPECT_EQ(ebur128_set_channel(st, 2, EBUR128_CENTER), EBUR128_ERROR_INVALID_CHANNEL_INDEX);
    
    ebur128_destroy(&st);
}

// Test silence processing - should produce negative infinity loudness
TEST_F(EBUR128Test, SilenceProcessing) {
    ebur128_state* st = ebur128_init(1, 48000, EBUR128_MODE_I);
    ASSERT_NE(st, nullptr);
    
    // Generate 5 seconds of silence
    auto silence = generateSilence(48000, 1, 5.0);
    
    int result = ebur128_add_frames_float(st, silence.data(), silence.size());
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    double loudness;
    result = ebur128_loudness_global(st, &loudness);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    EXPECT_TRUE(loudness == -HUGE_VAL); // Should be negative infinity for silence
    
    ebur128_destroy(&st);
}

// Test known sine wave loudness - this is the most important test for validation
TEST_F(EBUR128Test, SineWaveLoudness) {
    ebur128_state* st = ebur128_init(1, 48000, EBUR128_MODE_I | EBUR128_MODE_M);
    ASSERT_NE(st, nullptr);
    
    // Generate 1 kHz sine wave at -20 dBFS for 5 seconds
    double amplitude = pow(10.0, -20.0 / 20.0); // -20 dBFS
    auto sineWave = generateSineWave(1000.0, amplitude, 48000, 1, 5.0);
    
    int result = ebur128_add_frames_float(st, sineWave.data(), sineWave.size());
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    double integratedLoudness;
    result = ebur128_loudness_global(st, &integratedLoudness);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    // For a 1kHz sine wave at -20 dBFS, the expected loudness should be around -20 LUFS
    // (accounting for the BS.1770 weighting filter response)
    EXPECT_TRUE(std::isfinite(integratedLoudness));
    EXPECT_GT(integratedLoudness, -30.0);
    EXPECT_LT(integratedLoudness, -10.0);
    
    // Test momentary loudness
    double momentaryLoudness;
    result = ebur128_loudness_momentary(st, &momentaryLoudness);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    EXPECT_TRUE(std::isfinite(momentaryLoudness));
    
    ebur128_destroy(&st);
}

// Test short-term loudness measurement
TEST_F(EBUR128Test, ShortTermLoudness) {
    ebur128_state* st = ebur128_init(2, 48000, EBUR128_MODE_S);
    ASSERT_NE(st, nullptr);
    
    // Generate stereo sine wave
    double amplitude = pow(10.0, -15.0 / 20.0); // -15 dBFS
    auto sineWave = generateSineWave(1000.0, amplitude, 48000, 2, 5.0);
    
    int result = ebur128_add_frames_float(st, sineWave.data(), sineWave.size() / 2);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    double shortTermLoudness;
    result = ebur128_loudness_shortterm(st, &shortTermLoudness);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    EXPECT_TRUE(std::isfinite(shortTermLoudness));
    EXPECT_GT(shortTermLoudness, -25.0);
    EXPECT_LT(shortTermLoudness, -5.0);
    
    ebur128_destroy(&st);
}

// Test loudness range (LRA) calculation
TEST_F(EBUR128Test, LoudnessRange) {
    ebur128_state* st = ebur128_init(1, 48000, EBUR128_MODE_LRA);
    ASSERT_NE(st, nullptr);
    
    // Generate varying loudness signal
    std::vector<float> varyingSignal;
    
    // Quiet part: -30 dBFS
    auto quietPart = generateSineWave(1000.0, pow(10.0, -30.0 / 20.0), 48000, 1, 3.0);
    varyingSignal.insert(varyingSignal.end(), quietPart.begin(), quietPart.end());
    
    // Loud part: -10 dBFS  
    auto loudPart = generateSineWave(1000.0, pow(10.0, -10.0 / 20.0), 48000, 1, 3.0);
    varyingSignal.insert(varyingSignal.end(), loudPart.begin(), loudPart.end());
    
    int result = ebur128_add_frames_float(st, varyingSignal.data(), varyingSignal.size());
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    double lra;
    result = ebur128_loudness_range(st, &lra);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    EXPECT_TRUE(std::isfinite(lra));
    EXPECT_GT(lra, 0.0);
    EXPECT_LT(lra, 40.0); // Should be reasonable range
    
    ebur128_destroy(&st);
}

// Test sample peak measurement
TEST_F(EBUR128Test, SamplePeak) {
    ebur128_state* st = ebur128_init(2, 48000, EBUR128_MODE_SAMPLE_PEAK);
    ASSERT_NE(st, nullptr);
    
    // Generate signal with known peak
    double amplitude = 0.5; // -6 dBFS approximately
    auto sineWave = generateSineWave(1000.0, amplitude, 48000, 2, 2.0);
    
    int result = ebur128_add_frames_float(st, sineWave.data(), sineWave.size() / 2);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    double peak;
    result = ebur128_sample_peak(st, 0, &peak);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    EXPECT_GT(peak, 0.45);
    EXPECT_LT(peak, 0.55);
    
    // Test second channel
    result = ebur128_sample_peak(st, 1, &peak);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    EXPECT_GT(peak, 0.45);
    EXPECT_LT(peak, 0.55);
    
    ebur128_destroy(&st);
}

// Test true peak measurement
TEST_F(EBUR128Test, TruePeak) {
    ebur128_state* st = ebur128_init(1, 48000, EBUR128_MODE_TRUE_PEAK);
    ASSERT_NE(st, nullptr);
    
    // Generate signal that could have inter-sample peaks
    double amplitude = 0.8;
    auto sineWave = generateSineWave(8000.0, amplitude, 48000, 1, 2.0); // High frequency
    
    int result = ebur128_add_frames_float(st, sineWave.data(), sineWave.size());
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    double truePeak;
    result = ebur128_true_peak(st, 0, &truePeak);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    EXPECT_GT(truePeak, 0.7);
    EXPECT_LT(truePeak, 1.0);
    
    ebur128_destroy(&st);
}

// Test different sample rates
TEST_F(EBUR128Test, DifferentSampleRates) {
    std::vector<unsigned long> sampleRates = {44100, 48000, 88200, 96000, 192000};
    
    for (auto sampleRate : sampleRates) {
        ebur128_state* st = ebur128_init(1, sampleRate, EBUR128_MODE_I);
        ASSERT_NE(st, nullptr);
        
        double amplitude = pow(10.0, -20.0 / 20.0);
        auto sineWave = generateSineWave(1000.0, amplitude, static_cast<int>(sampleRate), 1, 3.0);
        
        int result = ebur128_add_frames_float(st, sineWave.data(), sineWave.size());
        EXPECT_EQ(result, EBUR128_SUCCESS);
        
        double loudness;
        result = ebur128_loudness_global(st, &loudness);
        EXPECT_EQ(result, EBUR128_SUCCESS);
        EXPECT_TRUE(std::isfinite(loudness));
        
        ebur128_destroy(&st);
    }
}

// Test error conditions
TEST_F(EBUR128Test, ErrorConditions) {
    // Test invalid mode for loudness calculation
    ebur128_state* st = ebur128_init(1, 48000, EBUR128_MODE_M); // No EBUR128_MODE_I
    ASSERT_NE(st, nullptr);
    
    auto sineWave = generateSineWave(1000.0, 0.1, 48000, 1, 1.0);
    ebur128_add_frames_float(st, sineWave.data(), sineWave.size());
    
    double loudness;
    int result = ebur128_loudness_global(st, &loudness);
    EXPECT_EQ(result, EBUR128_ERROR_INVALID_MODE);
    
    ebur128_destroy(&st);
    
    // Test invalid channel index for peak
    st = ebur128_init(1, 48000, EBUR128_MODE_SAMPLE_PEAK);
    ASSERT_NE(st, nullptr);
    
    double peak;
    result = ebur128_sample_peak(st, 1, &peak); // Channel 1 doesn't exist (only channel 0)
    EXPECT_EQ(result, EBUR128_ERROR_INVALID_CHANNEL_INDEX);
    
    ebur128_destroy(&st);
}

// Performance benchmark test
TEST_F(EBUR128Test, PerformanceBenchmark) {
    ebur128_state* st = ebur128_init(2, 48000, EBUR128_MODE_I | EBUR128_MODE_LRA | EBUR128_MODE_TRUE_PEAK);
    ASSERT_NE(st, nullptr);
    
    // Generate 10 seconds of stereo audio
    auto testSignal = generateSineWave(1000.0, 0.1, 48000, 2, 10.0);
    
    auto start = std::chrono::high_resolution_clock::now();
    
    int result = ebur128_add_frames_float(st, testSignal.data(), testSignal.size() / 2);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    double integratedLoudness, lra, truePeak;
    ebur128_loudness_global(st, &integratedLoudness);
    ebur128_loudness_range(st, &lra);
    ebur128_true_peak(st, 0, &truePeak);
    
    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
    
    // Should process 10 seconds of audio much faster than real-time
    EXPECT_LT(duration.count(), 1000); // Should take less than 1 second to process 10 seconds of audio
    
    std::cout << "Performance: Processed 10 seconds of stereo audio in " 
              << duration.count() << " ms" << std::endl;
    std::cout << "Results - Loudness: " << integratedLoudness 
              << " LUFS, LRA: " << lra 
              << " LU, True Peak: " << (20.0 * log10(truePeak)) << " dBFS" << std::endl;
    
    ebur128_destroy(&st);
}

// Test multiple instances
TEST_F(EBUR128Test, MultipleInstances) {
    const int numInstances = 3;
    ebur128_state* states[numInstances];
    
    // Initialize multiple instances
    for (int i = 0; i < numInstances; ++i) {
        states[i] = ebur128_init(1, 48000, EBUR128_MODE_I | EBUR128_MODE_LRA);
        ASSERT_NE(states[i], nullptr);
    }
    
    // Process different signals in each
    for (int i = 0; i < numInstances; ++i) {
        double amplitude = pow(10.0, (-20.0 - i * 5) / 20.0); // Different levels
        auto signal = generateSineWave(1000.0, amplitude, 48000, 1, 3.0);
        
        int result = ebur128_add_frames_float(states[i], signal.data(), signal.size());
        EXPECT_EQ(result, EBUR128_SUCCESS);
    }
    
    // Test global loudness across multiple instances
    double globalLoudness;
    int result = ebur128_loudness_global_multiple(states, numInstances, &globalLoudness);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    EXPECT_TRUE(std::isfinite(globalLoudness));
    
    // Test LRA across multiple instances
    double globalLRA;
    result = ebur128_loudness_range_multiple(states, numInstances, &globalLRA);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    EXPECT_TRUE(std::isfinite(globalLRA));
    EXPECT_GT(globalLRA, 0.0);
    
    // Clean up
    for (int i = 0; i < numInstances; ++i) {
        ebur128_destroy(&states[i]);
    }
}

// Test window-based loudness measurement
TEST_F(EBUR128Test, WindowLoudness) {
    ebur128_state* st = ebur128_init(1, 48000, EBUR128_MODE_M);
    ASSERT_NE(st, nullptr);
    
    // Set maximum window to 1000ms
    int result = ebur128_set_max_window(st, 1000);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    // Generate 2 seconds of test signal
    double amplitude = pow(10.0, -15.0 / 20.0);
    auto sineWave = generateSineWave(1000.0, amplitude, 48000, 1, 2.0);
    
    result = ebur128_add_frames_float(st, sineWave.data(), sineWave.size());
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    // Test window loudness measurement
    double windowLoudness;
    result = ebur128_loudness_window(st, 800, &windowLoudness); // 800ms window
    EXPECT_EQ(result, EBUR128_SUCCESS);
    EXPECT_TRUE(std::isfinite(windowLoudness));
    
    ebur128_destroy(&st);
}

// Test parameter changes during processing  
TEST_F(EBUR128Test, ParameterChanges) {
    ebur128_state* st = ebur128_init(1, 48000, EBUR128_MODE_I);
    ASSERT_NE(st, nullptr);
    
    // Process some initial data
    auto signal1 = generateSineWave(1000.0, 0.1, 48000, 1, 1.0);
    int result = ebur128_add_frames_float(st, signal1.data(), signal1.size());
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    // Change parameters (this will reset internal buffers)
    result = ebur128_change_parameters(st, 2, 44100); // Change to stereo, 44.1kHz
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    EXPECT_EQ(st->channels, 2u);
    EXPECT_EQ(st->samplerate, 44100ul);
    
    // Process new data with new parameters
    auto signal2 = generateSineWave(1000.0, 0.1, 44100, 2, 1.0);
    result = ebur128_add_frames_float(st, signal2.data(), signal2.size() / 2);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    double loudness;
    result = ebur128_loudness_global(st, &loudness);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    EXPECT_TRUE(std::isfinite(loudness));
    
    ebur128_destroy(&st);
}

// Test edge case: very short audio processing
TEST_F(EBUR128Test, ShortAudioProcessing) {
    ebur128_state* st = ebur128_init(1, 48000, EBUR128_MODE_I | EBUR128_MODE_M);
    ASSERT_NE(st, nullptr);
    
    // Process very short audio (0.1 seconds)
    auto shortSignal = generateSineWave(1000.0, 0.5, 48000, 1, 0.1);
    int result = ebur128_add_frames_float(st, shortSignal.data(), shortSignal.size());
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    // Momentary should work with short signals
    double momentary;
    result = ebur128_loudness_momentary(st, &momentary);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    // May be -infinity for too short signals, but should not crash
    
    // Integrated loudness may be -infinity for very short signals
    double integrated;
    result = ebur128_loudness_global(st, &integrated);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    ebur128_destroy(&st);
}

// Test comprehensive mode combinations
TEST_F(EBUR128Test, ModeValidation) {
    // Test all major mode combinations
    std::vector<int> testModes = {
        EBUR128_MODE_M,
        EBUR128_MODE_S, 
        EBUR128_MODE_I,
        EBUR128_MODE_LRA,
        EBUR128_MODE_SAMPLE_PEAK,
        EBUR128_MODE_TRUE_PEAK,
        EBUR128_MODE_I | EBUR128_MODE_LRA,
        EBUR128_MODE_I | EBUR128_MODE_LRA | EBUR128_MODE_TRUE_PEAK,
        EBUR128_MODE_HISTOGRAM | EBUR128_MODE_I
    };
    
    for (int mode : testModes) {
        ebur128_state* st = ebur128_init(2, 48000, mode);
        ASSERT_NE(st, nullptr) << "Failed to initialize with mode: " << mode;
        
        EXPECT_EQ(st->mode, mode);
        
        // Process test signal
        auto signal = generateSineWave(1000.0, 0.1, 48000, 2, 1.0);
        int result = ebur128_add_frames_float(st, signal.data(), signal.size() / 2);
        EXPECT_EQ(result, EBUR128_SUCCESS);
        
        ebur128_destroy(&st);
    }
}

// Test real-world audio file processing performance
TEST_F(EBUR128Test, RealWorldAudioFilePerformance) {
#ifdef TEST_AUDIO_FILE_PATH
    // Check if the downloaded audio file exists
    const char* audioFilePath = TEST_AUDIO_FILE_PATH;
    
    // Note: This test currently uses synthetic audio that simulates real-world characteristics
    // To process the actual OGG file, we would need audio decoding libraries (libvorbis, etc.)
    std::cout << "Real-world audio file available at: " << audioFilePath << std::endl;
    std::cout << "Note: Currently using synthetic audio simulation for C performance benchmarking" << std::endl;
#endif

    ebur128_state* st = ebur128_init(2, 48000, EBUR128_MODE_I | EBUR128_MODE_LRA | EBUR128_MODE_TRUE_PEAK);
    ASSERT_NE(st, nullptr);
    
    // Generate complex synthetic audio that simulates real-world music characteristics
    // This includes: varying frequencies, amplitude modulation, stereo imaging
    std::vector<float> complexAudio;
    const int sampleRate = 48000;
    const int channels = 2;
    const double duration = 30.0; // 30 seconds of audio - typical for real-world testing
    const int totalFrames = static_cast<int>(sampleRate * duration);
    
    std::cout << "Generating complex synthetic audio (simulating real-world music)..." << std::endl;
    std::cout << "Duration: " << duration << " seconds, Sample Rate: " << sampleRate << " Hz, Channels: " << channels << std::endl;
    
    auto start_generation = std::chrono::high_resolution_clock::now();
    
    // Create complex multi-layered audio similar to real music
    complexAudio.resize(totalFrames * channels);
    for (int frame = 0; frame < totalFrames; ++frame) {
        double t = static_cast<double>(frame) / sampleRate;
        
        // Base fundamental (simulating bass/rhythm)
        double fundamental = 0.3 * sin(2.0 * M_PI * 80.0 * t) * (1.0 + 0.1 * sin(2.0 * M_PI * 2.0 * t));
        
        // Harmonic content (simulating melody/instruments)
        double harmonics = 0.2 * sin(2.0 * M_PI * 440.0 * t) * (1.0 + 0.3 * sin(2.0 * M_PI * 0.5 * t))  // A4
                         + 0.15 * sin(2.0 * M_PI * 523.25 * t) * (1.0 + 0.2 * sin(2.0 * M_PI * 0.7 * t)) // C5
                         + 0.1 * sin(2.0 * M_PI * 659.25 * t) * (1.0 + 0.4 * sin(2.0 * M_PI * 1.3 * t));  // E5
        
        // High frequency content (simulating cymbals/percussion)
        double highFreq = 0.05 * sin(2.0 * M_PI * 8000.0 * t) * fabs(sin(2.0 * M_PI * 4.0 * t));
        
        // Amplitude envelope (simulating dynamic range)
        double envelope = 0.8 + 0.2 * sin(2.0 * M_PI * 0.1 * t);
        
        float leftSample = static_cast<float>((fundamental + harmonics + highFreq) * envelope);
        float rightSample = static_cast<float>((fundamental * 0.9 + harmonics * 1.1 + highFreq * 0.8) * envelope);
        
        // Apply some stereo imaging
        complexAudio[frame * channels] = leftSample * 0.7f;      // Left channel
        complexAudio[frame * channels + 1] = rightSample * 0.7f;  // Right channel
    }
    
    auto end_generation = std::chrono::high_resolution_clock::now();
    auto generation_duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_generation - start_generation);
    
    std::cout << "Audio generation completed in " << generation_duration.count() << " ms" << std::endl;
    std::cout << "Starting EBUR128 processing..." << std::endl;
    
    // Benchmark the C implementation processing time
    auto start_processing = std::chrono::high_resolution_clock::now();
    
    int result = ebur128_add_frames_float(st, complexAudio.data(), complexAudio.size() / 2);
    EXPECT_EQ(result, EBUR128_SUCCESS);
    
    double integratedLoudness, lra, truePeakLeft, truePeakRight;
    ebur128_loudness_global(st, &integratedLoudness);
    ebur128_loudness_range(st, &lra);
    ebur128_true_peak(st, 0, &truePeakLeft);
    ebur128_true_peak(st, 1, &truePeakRight);
    
    auto end_processing = std::chrono::high_resolution_clock::now();
    auto processing_duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_processing - start_processing);
    
    // Calculate performance metrics
    double realTimeRatio = (duration * 1000.0) / processing_duration.count();
    
    // Results validation
    EXPECT_TRUE(std::isfinite(integratedLoudness));
    EXPECT_TRUE(std::isfinite(lra));
    EXPECT_TRUE(std::isfinite(truePeakLeft));
    EXPECT_TRUE(std::isfinite(truePeakRight));
    
    // Performance should be significantly faster than real-time
    EXPECT_GT(realTimeRatio, 10.0); // Should be at least 10x real-time
    
    // Comprehensive performance report
    std::cout << "\n=== C IMPLEMENTATION PERFORMANCE BENCHMARK ===" << std::endl;
    std::cout << "Audio Duration: " << duration << " seconds" << std::endl;
    std::cout << "Processing Time: " << processing_duration.count() << " ms" << std::endl;
    std::cout << "Real-time Ratio: " << realTimeRatio << "x (higher is better)" << std::endl;
    std::cout << "Performance: " << (realTimeRatio >= 30.0 ? "EXCELLENT" : 
                                   realTimeRatio >= 20.0 ? "VERY GOOD" :
                                   realTimeRatio >= 10.0 ? "GOOD" : "NEEDS OPTIMIZATION") << std::endl;
    std::cout << "\n=== MEASUREMENT RESULTS ===" << std::endl;
    std::cout << "Integrated Loudness: " << integratedLoudness << " LUFS" << std::endl;
    std::cout << "Loudness Range: " << lra << " LU" << std::endl;
    std::cout << "True Peak L: " << (20.0 * log10(truePeakLeft)) << " dBFS" << std::endl;
    std::cout << "True Peak R: " << (20.0 * log10(truePeakRight)) << " dBFS" << std::endl;
    std::cout << "===============================================\n" << std::endl;
    
    // Important note about Swift implementation comparison
    std::cout << "⚠️  PERFORMANCE COMPARISON NOTE:" << std::endl;
    std::cout << "The Swift implementation is currently ~10x slower than this C version." << std::endl;
    std::cout << "Expected Swift performance: ~" << (realTimeRatio / 10.0) << "x real-time" << std::endl;
    std::cout << "This benchmark provides a baseline for Swift optimization targets." << std::endl;
    
    ebur128_destroy(&st);
}
