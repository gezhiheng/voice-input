import AVFoundation
import Foundation
import QuartzCore
import Speech

struct TranscriptAccumulator {
    private(set) var committedText = ""
    private(set) var activeText = ""

    var combinedText: String {
        Self.join(committedText, activeText)
    }

    mutating func updateActiveText(_ text: String) {
        guard !text.isEmpty else {
            activeText = text
            return
        }

        guard !activeText.isEmpty else {
            activeText = text
            return
        }

        if shouldReplaceActiveText(with: text) {
            activeText = text
            return
        }

        committedText = Self.join(committedText, activeText)
        activeText = text
    }

    mutating func commitActiveText() {
        committedText = Self.join(committedText, activeText)
        activeText = ""
    }

    mutating func reset() {
        committedText = ""
        activeText = ""
    }

    private static func join(_ left: String, _ right: String) -> String {
        guard !left.isEmpty else {
            return right
        }

        guard !right.isEmpty else {
            return left
        }

        let overlapLength = overlapCount(betweenSuffixOf: left, andPrefixOf: right)
        if overlapLength > 0 {
            let suffixStart = right.index(right.startIndex, offsetBy: overlapLength)
            return left + right[suffixStart...]
        }

        if shouldInsertSpace(between: left, and: right) {
            return left + " " + right
        }

        return left + right
    }

    private func shouldReplaceActiveText(with newText: String) -> Bool {
        if newText == activeText {
            return true
        }

        if newText.hasPrefix(activeText) || activeText.hasPrefix(newText) {
            return true
        }

        if newText.contains(activeText) || activeText.contains(newText) {
            return true
        }

        let prefixLength = Self.commonPrefixCount(between: activeText, and: newText)
        let shorterLength = min(activeText.count, newText.count)
        if shorterLength > 0 && prefixLength * 2 >= shorterLength {
            return true
        }

        return false
    }

    private static func shouldInsertSpace(between left: String, and right: String) -> Bool {
        guard let leftScalar = left.unicodeScalars.last,
              let rightScalar = right.unicodeScalars.first else {
            return false
        }

        let whitespace = CharacterSet.whitespacesAndNewlines
        if whitespace.contains(leftScalar) || whitespace.contains(rightScalar) {
            return false
        }

        if punctuationLike.contains(leftScalar) || punctuationLike.contains(rightScalar) {
            return false
        }

        if isCJK(leftScalar) || isCJK(rightScalar) {
            return false
        }

        return true
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x2E80 ... 0x2EFF,
             0x2F00 ... 0x2FDF,
             0x3040 ... 0x30FF,
             0x3100 ... 0x312F,
             0x3130 ... 0x318F,
             0x31A0 ... 0x31BF,
             0x3400 ... 0x4DBF,
             0x4E00 ... 0x9FFF,
             0xAC00 ... 0xD7AF,
             0xF900 ... 0xFAFF,
             0xFF66 ... 0xFF9D:
            return true
        default:
            return false
        }
    }

    private static func commonPrefixCount(between left: String, and right: String) -> Int {
        zip(left, right).prefix { lhs, rhs in
            lhs == rhs
        }.count
    }

    private static func overlapCount(betweenSuffixOf left: String, andPrefixOf right: String) -> Int {
        let maxLength = min(left.count, right.count)
        guard maxLength > 0 else {
            return 0
        }

        for length in stride(from: maxLength, through: 1, by: -1) {
            let leftStart = left.index(left.endIndex, offsetBy: -length)
            let rightEnd = right.index(right.startIndex, offsetBy: length)

            if left[leftStart...] == right[..<rightEnd] {
                return length
            }
        }

        return 0
    }

    private static let punctuationLike = CharacterSet.punctuationCharacters
        .union(.symbols)
}

final class SpeechRecognizerService: SpeechTranscribing {
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var finalContinuation: CheckedContinuation<String, Error>?
    private var transcriptAccumulator = TranscriptAccumulator()
    private var didStop = false
    private var levelHandler: (([Double]) -> Void)?
    private var partialHandler: ((String) -> Void)?
    private var levelMeter = AudioLevelMeter()
    private var lastLevelEmission = CACurrentMediaTime()
    private var currentTaskID = UUID()

    func start(
        locale: Locale,
        partialHandler: @escaping (String) -> Void,
        levelHandler: @escaping ([Double]) -> Void
    ) async throws {
        cancel()
        resetAudioEngine()

        guard let speechRecognizer = SFSpeechRecognizer(locale: locale), speechRecognizer.isAvailable else {
            throw VoiceInputError.speechRecognizerUnavailable
        }

        self.speechRecognizer = speechRecognizer
        self.partialHandler = partialHandler
        self.levelHandler = levelHandler
        self.transcriptAccumulator.reset()
        self.didStop = false
        self.levelMeter = AudioLevelMeter()
        self.lastLevelEmission = CACurrentMediaTime()
        self.currentTaskID = UUID()
        self.recognitionRequest = nil

        let inputNode = audioEngine.inputNode
        let format = preferredTapFormat(for: inputNode)
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let request = self.recognitionRequest else {
                return
            }

            request.append(buffer)
            self.process(buffer: buffer)
        }

        startRecognitionTask(with: speechRecognizer)

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() async throws -> String {
        didStop = true

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()

        return try await awaitFinalResult(fallback: transcriptAccumulator.combinedText)
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

    private func preferredTapFormat(for inputNode: AVAudioInputNode) -> AVAudioFormat {
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let outputFormat = inputNode.outputFormat(forBus: 0)

        // Some device / route changes leave the node's client format desynced from the
        // hardware input format. The tap must match the hardware format to avoid AVFAudio
        // aborting with "Input HW format and tap format not matching".
        if inputFormat.sampleRate != outputFormat.sampleRate ||
            inputFormat.channelCount != outputFormat.channelCount {
            return inputFormat
        }

        return outputFormat
    }

    private func startRecognitionTask(with recognizer: SFSpeechRecognizer) {
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        self.recognitionRequest = recognitionRequest

        let taskID = UUID()
        currentTaskID = taskID
        transcriptAccumulator.updateActiveText("")

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            self?.handleRecognitionEvent(taskID: taskID, result: result, error: error)
        }
    }

    private func handleRecognitionEvent(
        taskID: UUID,
        result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        guard taskID == currentTaskID else {
            return
        }

        if let result {
            transcriptAccumulator.updateActiveText(result.bestTranscription.formattedString)
            partialHandler?(transcriptAccumulator.combinedText)

            if result.isFinal {
                transcriptAccumulator.commitActiveText()
                partialHandler?(transcriptAccumulator.combinedText)

                if didStop {
                    resumeContinuation(with: .success(transcriptAccumulator.combinedText))
                } else if let speechRecognizer {
                    startRecognitionTask(with: speechRecognizer)
                }

                return
            }
        }

        if let error {
            let currentTranscript = transcriptAccumulator.combinedText

            if didStop, !currentTranscript.isEmpty {
                resumeContinuation(with: .success(currentTranscript))
            } else if didStop {
                resumeContinuation(with: .failure(error))
            }
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
        transcriptAccumulator.reset()
        currentTaskID = UUID()
    }

    private func resetAudioEngine() {
        audioEngine = AVAudioEngine()
    }
}
