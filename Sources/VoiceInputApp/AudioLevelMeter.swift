import Foundation

struct AudioLevelMeter {
    private let weights: [Double] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private let attack: Double = 0.40
    private let release: Double = 0.15
    private let minimumLevel: Double = 0.10
    private let jitterRange: ClosedRange<Double> = -0.04 ... 0.04

    private(set) var envelope: Double = 0
    private var randomSource: () -> Double

    init(randomSource: @escaping () -> Double = { Double.random(in: 0 ... 1) }) {
        self.randomSource = randomSource
    }

    mutating func levels(forRMS rms: Double) -> [Double] {
        let normalized = min(max(sqrt(max(rms, 0)) * 4.2, 0), 1)
        let smoothing = normalized > envelope ? attack : release
        envelope += (normalized - envelope) * smoothing

        let base = max(envelope, minimumLevel)

        return weights.map { weight in
            let jitter = jitterRange.lowerBound + (jitterRange.upperBound - jitterRange.lowerBound) * randomSource()
            return min(max(base * weight + jitter, minimumLevel * 0.75), 1)
        }
    }
}
