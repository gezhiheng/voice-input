import AVFoundation
import Foundation
import QuartzCore
import Speech

final class SpeechRecognizerService: SpeechTranscribing {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var finalContinuation: CheckedContinuation<String, Error>?
    private var latestTranscript = ""
    private var didStop = false
    private var levelHandler: (([Double]) -> Void)?
    private var partialHandler: ((String) -> Void)?
    private var levelMeter = AudioLevelMeter()
    private var lastLevelEmission = CACurrentMediaTime()

    func start(
        locale: Locale,
        partialHandler: @escaping (String) -> Void,
        levelHandler: @escaping ([Double]) -> Void
    ) async throws {
        cancel()

        guard let speechRecognizer = SFSpeechRecognizer(locale: locale), speechRecognizer.isAvailable else {
            throw VoiceInputError.speechRecognizerUnavailable
        }

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        self.speechRecognizer = speechRecognizer
        self.recognitionRequest = recognitionRequest
        self.partialHandler = partialHandler
        self.levelHandler = levelHandler
        self.latestTranscript = ""
        self.didStop = false
        self.levelMeter = AudioLevelMeter()
        self.lastLevelEmission = CACurrentMediaTime()

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let request = self.recognitionRequest else {
                return
            }

            request.append(buffer)
            self.process(buffer: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else {
                return
            }

            if let result {
                let transcript = result.bestTranscription.formattedString
                self.latestTranscript = transcript
                self.partialHandler?(transcript)

                if result.isFinal {
                    self.resumeContinuation(with: .success(transcript))
                }
            }

            if let error {
                if self.didStop, !self.latestTranscript.isEmpty {
                    self.resumeContinuation(with: .success(self.latestTranscript))
                } else {
                    self.resumeContinuation(with: .failure(error))
                }
            }
        }
    }

    func stop() async throws -> String {
        didStop = true

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()

        let fallback = latestTranscript

        if !fallback.isEmpty {
            return try await awaitFinalResult(fallback: fallback)
        }

        return try await awaitFinalResult(fallback: "")
    }

    func cancel() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        cleanup()
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            return
        }

        let samples = Int(buffer.frameLength)
        guard samples > 0 else {
            return
        }

        let channel = channelData[0]
        var sumSquares: Double = 0
        for sampleIndex in 0 ..< samples {
            let sample = Double(channel[sampleIndex])
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Double(samples))
        let now = CACurrentMediaTime()

        guard now - lastLevelEmission >= (1.0 / 30.0) else {
            return
        }

        lastLevelEmission = now
        let levels = levelMeter.levels(forRMS: rms)
        DispatchQueue.main.async { [weak self] in
            self?.levelHandler?(levels)
        }
    }

    private func awaitFinalResult(fallback: String) async throws -> String {
        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { [weak self] in
                    guard let self else {
                        return fallback
                    }

                    return try await withCheckedThrowingContinuation { continuation in
                        self.finalContinuation = continuation
                    }
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                    return fallback
                }

                let result = try await group.next() ?? fallback
                group.cancelAll()
                cleanup()
                return result
            }
        } catch {
            cleanup()
            throw error
        }
    }

    private func resumeContinuation(with result: Result<String, Error>) {
        guard let continuation = finalContinuation else {
            return
        }

        finalContinuation = nil

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func cleanup() {
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
        finalContinuation = nil
        partialHandler = nil
        levelHandler = nil
        didStop = false
        latestTranscript = ""
    }
}
