//
//  PrompterViewModel.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 05/01/26.
//
import Foundation
import AppKit
import Combine

final class PrompterViewModel: ObservableObject {
    @Published var script: String {
        didSet {
            if isTrackingScriptHistory, script != oldValue {
                undoStack.append(oldValue)
                redoStack.removeAll()
            }
            UserDefaults.standard.set(script, forKey: DefaultsKey.currentScript)
        }
    }
    @Published var speed: Double {
        didSet { UserDefaults.standard.set(speed, forKey: DefaultsKey.prompterSpeed) }
    }
    @Published var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: DefaultsKey.prompterFontSize) }
    }
    @Published var voiceFollowEnabled: Bool {
        didSet { UserDefaults.standard.set(voiceFollowEnabled, forKey: DefaultsKey.voiceFollowEnabled) }
    }

    @Published var isEditing: Bool = true
    @Published var isPaused: Bool = true

    @Published var offsetY: CGFloat = 0
    @Published var viewportHeight: CGFloat = 1
    @Published var prompterWidth: CGFloat = 300
    @Published private(set) var contentHeight: CGFloat = 1

    @Published var importErrorMessage: String? = nil
    @Published var showControlsInNotch: Bool = true

    var isPlaying: Bool {
        !isPaused
    }

    var voiceContextualStrings: [String] {
        var seen = Set<String>()
        var values: [String] = []
        for word in wordTargets.map(\.normalizedText) where Self.isStrongSpeechWord(word) {
            guard seen.insert(word).inserted else { continue }
            values.append(word)
            if values.count >= 80 { break }
        }
        return values
    }

    private var lastTick: CFTimeInterval = CACurrentMediaTime()
    private var timer: Timer?

    private let measureQueue = DispatchQueue(label: "Prompter.MeasureQueue", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()
    private var sentenceTargets: [SentenceTarget] = []
    private var wordTargets: [WordTarget] = []
    private var nextSentenceIndex = 0
    private var nextWordIndex = 0
    private var lastMatchedTranscript = ""
    private var pendingVoiceMatchIndex: Int?
    private var pendingVoiceMatchCount = 0
    private var voiceTargetOffsetY: CGFloat?
    private var undoStack: [String] = []
    private var redoStack: [String] = []
    private var isApplyingHistory = false

    private var isTrackingScriptHistory: Bool {
        !isApplyingHistory
    }

    var canUndoScriptEdit: Bool { !undoStack.isEmpty }
    var canRedoScriptEdit: Bool { !redoStack.isEmpty }

    init() {
        script = UserDefaults.standard.string(forKey: DefaultsKey.currentScript) ?? "Paste your script here."
        speed = (UserDefaults.standard.object(forKey: DefaultsKey.prompterSpeed) as? Double) ?? 35
        fontSize = (UserDefaults.standard.object(forKey: DefaultsKey.prompterFontSize) as? Double) ?? 16
        voiceFollowEnabled = (UserDefaults.standard.object(forKey: DefaultsKey.voiceFollowEnabled) as? Bool) ?? false
        sentenceTargets = Self.buildSentenceTargets(for: script)
        wordTargets = Self.buildWordTargets(for: script)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleShowControlsInNotch(_:)),
                                               name: .overlayShowControlsInNotch,
                                               object: nil)

        // IMPORTANT: pick up changes made by Settings window (UserDefaults writes)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }

                let newSpeed = (UserDefaults.standard.object(forKey: DefaultsKey.prompterSpeed) as? Double) ?? self.speed
                if newSpeed != self.speed { self.speed = newSpeed }

                let newFont = (UserDefaults.standard.object(forKey: DefaultsKey.prompterFontSize) as? Double) ?? self.fontSize
                if newFont != self.fontSize {
                    self.fontSize = newFont
                    // Recompute height if font changes while prompting
                    if !self.isEditing { self.recomputeContentHeight(restoreRatio: nil) }
                }

                let newVoiceFollow = (UserDefaults.standard.object(forKey: DefaultsKey.voiceFollowEnabled) as? Bool) ?? self.voiceFollowEnabled
                if newVoiceFollow != self.voiceFollowEnabled {
                    self.voiceFollowEnabled = newVoiceFollow
                }

                // Script changes via settings import/export also reflect
                let newScript = UserDefaults.standard.string(forKey: DefaultsKey.currentScript) ?? self.script
                if newScript != self.script {
                    self.replaceScript(newScript, resetHistory: true)
                    self.rebuildVoiceTargets()
                    self.offsetY = 0
                    self.recomputeContentHeight(restoreRatio: 0)
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopTicker()
    }

    func startTicker() {
        stopTicker()
        lastTick = CACurrentMediaTime()

        let interval = 1.0 / Layout.tickHz
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    func stopTicker() {
        timer?.invalidate()
        timer = nil
    }

    func tick() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.tick() }
            return
        }

        let now = CACurrentMediaTime()
        let dt = min(max(now - lastTick, 0), Layout.maxDt)
        lastTick = now

        guard !isEditing, !isPaused else { return }

        if voiceFollowEnabled {
            guard let voiceTargetOffsetY else { return }
            let distance = voiceTargetOffsetY - offsetY
            if abs(distance) < 0.5 {
                offsetY = clampOffset(voiceTargetOffsetY)
                return
            }

            let smoothing = min(1, max(0.08, CGFloat(dt * 9.0)))
            offsetY = clampOffset(offsetY + distance * smoothing)
            return
        }

        // HARD STOP when speed <= 0
        if speed <= 0 { return }

        let delta = CGFloat(speed) * CGFloat(dt)
        if delta <= 0 { return }
        offsetY = clampOffset(offsetY + delta)
    }

    func importFile(url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                self.replaceScript(text, resetHistory: true)
                self.offsetY = 0
                self.recomputeContentHeight(restoreRatio: 0)
            }
        } catch {
            DispatchQueue.main.async {
                self.importErrorMessage = "Could not import file.\n\(error.localizedDescription)"
            }
        }
    }

    func play() {
        isPaused = false
        recomputeContentHeight(restoreRatio: nil)
    }

    func pause() {
        isPaused = true
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func resetToTop() {
        offsetY = 0
        lastTick = CACurrentMediaTime()
        nextSentenceIndex = 0
        nextWordIndex = 0
        lastMatchedTranscript = ""
        pendingVoiceMatchIndex = nil
        pendingVoiceMatchCount = 0
        voiceTargetOffsetY = nil
    }

    func adjustSpeed(by delta: Double) {
        speed = min(300, max(0, speed + delta))
    }

    func scrollManually(by deltaY: CGFloat) {
        guard !isEditing else { return }

        let nextOffset = clampOffset(offsetY + deltaY)
        offsetY = nextOffset
        voiceTargetOffsetY = voiceFollowEnabled ? nextOffset : nil
        lastTick = CACurrentMediaTime()
        syncVoiceProgressToVisibleOffset()
    }

    func undoScriptEdit() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(script)
        applyScriptFromHistory(previous)
    }

    func redoScriptEdit() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(script)
        applyScriptFromHistory(next)
    }

    func handleRecognizedSpeech(_ text: String) {
        guard voiceFollowEnabled, !isEditing, !isPaused else { return }

        let normalizedTranscript = Self.normalizedText(text)
        guard normalizedTranscript.count >= 3, normalizedTranscript != lastMatchedTranscript else { return }

        let transcriptWords = Array(Self.words(in: normalizedTranscript).suffix(90))
        let recentWords = transcriptWords.joined(separator: " ")
        guard !transcriptWords.isEmpty, !recentWords.isEmpty else { return }

        if let phraseMatch = bestPhraseMatch(for: transcriptWords) {
            guard confirmVoiceMatch(at: phraseMatch.index) else { return }
            commitVoiceMatch(index: phraseMatch.index)
            return
        }

        let searchEnd = min(sentenceTargets.count, nextSentenceIndex + 5)
        guard nextSentenceIndex < searchEnd else { return }

        for index in nextSentenceIndex..<searchEnd {
            let target = sentenceTargets[index]
            let matchCount = Self.orderedMatchCount(targetWords: target.words,
                                                    transcriptWords: transcriptWords)
            if Self.transcript(recentWords, matches: target.words, phrase: target.normalizedText) {
                nextSentenceIndex = min(index + 1, sentenceTargets.count)
                lastMatchedTranscript = normalizedTranscript
                let targetIndex = voiceTargetIndex(in: target, matchedWords: matchCount)
                if confirmVoiceMatch(at: targetIndex) {
                    commitVoiceMatch(index: targetIndex)
                }
                return
            }
        }
    }

    func recomputeContentHeight(restoreRatio: CGFloat?) {
        let text = script
        let width = prompterWidth
        let fs = fontSize
        guard width > 10 else { return }

        measureQueue.async { [weak self] in
            guard let self else { return }
            let measured = Self.measureHeight(text: text, width: width, fontSize: fs)
            DispatchQueue.main.async {
                self.contentHeight = max(1, measured)
                if let r = restoreRatio {
                    self.offsetY = self.clampOffset(self.maxOffset() * r)
                } else {
                    self.offsetY = self.clampOffset(self.offsetY)
                }
            }
        }
    }

    private func rebuildVoiceTargets() {
        sentenceTargets = Self.buildSentenceTargets(for: script)
        wordTargets = Self.buildWordTargets(for: script)
        nextSentenceIndex = 0
        nextWordIndex = 0
        lastMatchedTranscript = ""
        pendingVoiceMatchIndex = nil
        pendingVoiceMatchCount = 0
        voiceTargetOffsetY = nil
    }

    private func applyScriptFromHistory(_ text: String) {
        isApplyingHistory = true
        script = text
        isApplyingHistory = false
        rebuildVoiceTargets()
        recomputeContentHeight(restoreRatio: nil)
    }

    private func replaceScript(_ text: String, resetHistory: Bool) {
        isApplyingHistory = resetHistory
        script = text
        isApplyingHistory = false
        if resetHistory {
            undoStack.removeAll()
            redoStack.removeAll()
        }
        rebuildVoiceTargets()
    }

    private func scrollToCharacterIndex(_ characterIndex: Int) {
        let targetY = Self.measureHeight(
            text: String(script.prefix(max(0, min(characterIndex, script.count)))),
            width: prompterWidth,
            fontSize: fontSize
        )
        let targetOffset = clampOffset(max(0, targetY - viewportHeight * 0.35))
        if voiceFollowEnabled {
            voiceTargetOffsetY = targetOffset
        } else {
            offsetY = targetOffset
        }
        lastTick = CACurrentMediaTime()
    }

    private func syncVoiceProgressToVisibleOffset() {
        guard !wordTargets.isEmpty else { return }

        let approximateReadY = offsetY + viewportHeight * 0.35
        var low = 0
        var high = wordTargets.count - 1
        var best = 0

        while low <= high {
            let mid = (low + high) / 2
            let y = Self.measureHeight(
                text: String(script.prefix(max(0, min(wordTargets[mid].range.upperBound, script.count)))),
                width: prompterWidth,
                fontSize: fontSize
            )
            if y <= approximateReadY {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        nextWordIndex = min(best, wordTargets.count - 1)
        advanceSentenceProgress(upTo: wordTargets[nextWordIndex].range.lowerBound)
        lastMatchedTranscript = ""
        pendingVoiceMatchIndex = nil
        pendingVoiceMatchCount = 0
    }

    private func confirmVoiceMatch(at index: Int) -> Bool {
        if pendingVoiceMatchIndex == index || pendingVoiceMatchIndex.map({ abs($0 - index) <= 1 }) == true {
            pendingVoiceMatchIndex = index
            pendingVoiceMatchCount += 1
        } else {
            pendingVoiceMatchIndex = index
            pendingVoiceMatchCount = 1
        }
        return pendingVoiceMatchCount >= 2
    }

    private func commitVoiceMatch(index: Int) {
        guard wordTargets.indices.contains(index) else { return }
        nextWordIndex = min(index + 1, wordTargets.count)
        advanceSentenceProgress(upTo: wordTargets[index].range.upperBound)
        scrollToCharacterIndex(wordTargets[index].range.upperBound)
    }

    static func measureHeight(text: String, width: CGFloat, fontSize: Double) -> CGFloat {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        para.lineSpacing = Layout.lineSpacing

        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        let attr = NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: para
        ])

        let rect = attr.boundingRect(
            with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        return ceil(rect.height) + 8
    }

    func toggleEditMode() {
        if isEditing {
            isEditing = false
            isPaused = true
            recomputeContentHeight(restoreRatio: nil)
        } else {
            isPaused = true
            isEditing = true
        }
    }

    private func maxOffset() -> CGFloat { max(0, contentHeight - viewportHeight) }
    private func clampOffset(_ proposed: CGFloat) -> CGFloat { min(max(proposed, 0), maxOffset()) }

    @objc private func handleShowControlsInNotch(_ note: Notification) {
        if let v = note.object as? Bool {
            DispatchQueue.main.async { self.showControlsInNotch = v }
        }
    }
}

private struct SentenceTarget {
    let range: Range<Int>
    let normalizedText: String
    let words: [String]
}

private struct WordTarget {
    let range: Range<Int>
    let normalizedText: String
}

private struct PhraseMatch {
    let index: Int
    let score: Int
}

private extension PrompterViewModel {
    static func buildSentenceTargets(for script: String) -> [SentenceTarget] {
        let characters = Array(script)
        var targets: [SentenceTarget] = []
        var start = 0

        func appendTarget(end: Int) {
            let trimmedStart = trimForward(characters, from: start, to: end)
            let trimmedEnd = trimBackward(characters, from: trimmedStart, to: end)
            guard trimmedEnd > trimmedStart else {
                start = end
                return
            }

            let sentence = String(characters[trimmedStart..<trimmedEnd])
            let normalized = normalizedText(sentence)
            let words = words(in: normalized)
            if !words.isEmpty {
                targets.append(SentenceTarget(range: trimmedStart..<trimmedEnd,
                                              normalizedText: normalized,
                                              words: words))
            }
            start = end
        }

        for index in characters.indices {
            let c = characters[index]
            if ".!?\n".contains(c) {
                appendTarget(end: index + 1)
            }
        }
        appendTarget(end: characters.count)

        return targets
    }

    static func buildWordTargets(for script: String) -> [WordTarget] {
        let characters = Array(script)
        var targets: [WordTarget] = []
        var start: Int?

        func appendWord(end: Int) {
            guard let wordStart = start else { return }
            let word = String(characters[wordStart..<end])
            let normalized = normalizedText(word)
            if !normalized.isEmpty {
                targets.append(WordTarget(range: wordStart..<end, normalizedText: normalized))
            }
            start = nil
        }

        for index in characters.indices {
            let scalar = String(characters[index]).unicodeScalars.first
            let isWordCharacter = scalar.map { CharacterSet.alphanumerics.contains($0) } ?? false
            if isWordCharacter {
                if start == nil { start = index }
            } else {
                appendWord(end: index)
            }
        }
        appendWord(end: characters.count)

        return targets
    }

    func voiceTargetIndex(in sentence: SentenceTarget, matchedWords: Int) -> Int {
        guard matchedWords > 0 else { return nextWordIndex }

        let sentenceWordIndices = wordTargets.indices.filter { sentence.range.overlaps(wordTargets[$0].range) }
        guard !sentenceWordIndices.isEmpty else { return nextWordIndex }

        let index = min(max(matchedWords - 1, 0), sentenceWordIndices.count - 1)
        return sentenceWordIndices[index]
    }

    func bestPhraseMatch(for transcriptWords: [String]) -> PhraseMatch? {
        guard !wordTargets.isEmpty, transcriptWords.count >= 2 else { return nil }

        let targetStart = max(0, min(nextWordIndex, wordTargets.count - 1))
        let targetEnd = min(wordTargets.count, targetStart + 36)
        let recentTranscript = Array(transcriptWords.suffix(8))
        var best: PhraseMatch?

        for start in targetStart..<targetEnd {
            guard let candidate = alignPhrase(from: start, transcriptWords: recentTranscript) else { continue }
            if best == nil || candidate.score > best!.score {
                best = candidate
            }
        }

        return best
    }

    func alignPhrase(from start: Int, transcriptWords: [String]) -> PhraseMatch? {
        guard start < wordTargets.count else { return nil }

        var targetIndex = start
        var matchedIndices: [Int] = []
        var strongMatches = 0
        let maxSkipPerWord = 4

        for spoken in transcriptWords {
            guard spoken.count >= 2 else { continue }
            let searchEnd = min(wordTargets.count, targetIndex + maxSkipPerWord + 1)
            guard targetIndex < searchEnd else { break }

            var foundIndex: Int?
            for index in targetIndex..<searchEnd {
                let target = wordTargets[index].normalizedText
                if Self.wordsAreCompatible(spoken, target) {
                    foundIndex = index
                    break
                }
            }

            if let foundIndex {
                matchedIndices.append(foundIndex)
                if Self.isStrongSpeechWord(spoken) {
                    strongMatches += 1
                }
                targetIndex = foundIndex + 1
            }
        }

        guard matchedIndices.count >= 2, strongMatches >= 1, let lastIndex = matchedIndices.last else {
            return nil
        }

        let distancePenalty = max(0, start - nextWordIndex)
        let score = matchedIndices.count * 12 + strongMatches * 5 - distancePenalty
        return PhraseMatch(index: lastIndex, score: score)
    }

    func advanceSentenceProgress(upTo characterIndex: Int) {
        while nextSentenceIndex < sentenceTargets.count,
              sentenceTargets[nextSentenceIndex].range.upperBound <= characterIndex {
            nextSentenceIndex += 1
        }
    }

    static func normalizedText(_ text: String) -> String {
        let lowered = text.lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars)
            .split(separator: " ")
            .joined(separator: " ")
    }

    static func words(in normalizedText: String) -> [String] {
        normalizedText.split(separator: " ").map(String.init)
    }

    static func wordsAreCompatible(_ spoken: String, _ target: String) -> Bool {
        guard spoken.count >= 2, target.count >= 2 else { return false }
        if spoken == target { return true }

        let minLength = min(spoken.count, target.count)
        guard minLength >= 4 else { return false }
        return spoken.hasPrefix(target) || target.hasPrefix(spoken)
    }

    static func isStrongSpeechWord(_ word: String) -> Bool {
        guard word.count >= 4 else { return false }
        return !weakSpeechWords.contains(word)
    }

    static let weakSpeechWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by",
        "for", "from", "has", "have", "he", "her", "his", "i",
        "in", "is", "it", "its", "me", "my", "of", "on", "or",
        "our", "she", "so", "that", "the", "their", "them", "then",
        "there", "they", "this", "to", "was", "we", "were", "with",
        "you", "your"
    ]

    static func transcript(_ transcript: String, matches targetWords: [String], phrase: String) -> Bool {
        guard !targetWords.isEmpty else { return false }
        if phrase.count >= 12, transcript.contains(phrase) { return true }

        let transcriptWords = words(in: transcript)
        guard !transcriptWords.isEmpty else { return false }

        let matched = orderedMatchCount(targetWords: targetWords,
                                        transcriptWords: transcriptWords,
                                        maxTargetSkips: 5)
        let required: Int
        if targetWords.count <= 3 {
            required = targetWords.count
        } else {
            required = max(3, Int(ceil(Double(targetWords.count) * 0.72)))
        }

        return matched >= required
    }

    static func orderedMatchCount(targetWords: [String],
                                  transcriptWords: [String],
                                  maxTargetSkips: Int = 2) -> Int {
        var targetIndex = 0
        var matched = 0

        for spoken in transcriptWords {
            guard targetIndex < targetWords.count else { break }

            let searchEnd = min(targetWords.count, targetIndex + maxTargetSkips + 1)
            var matchedIndex: Int?
            for index in targetIndex..<searchEnd {
                let target = targetWords[index]
                if wordsAreCompatible(spoken, target) {
                    matchedIndex = index
                    break
                }
            }

            if let matchedIndex {
                matched += 1
                targetIndex = matchedIndex + 1
            }
        }

        return matched
    }

    static func trimForward(_ characters: [Character], from start: Int, to end: Int) -> Int {
        var index = start
        while index < end, characters[index].isWhitespace {
            index += 1
        }
        return index
    }

    static func trimBackward(_ characters: [Character], from start: Int, to end: Int) -> Int {
        var index = end
        while index > start, characters[index - 1].isWhitespace {
            index -= 1
        }
        return index
    }
}
