//
//  SpeechVoiceActivityDetector.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 02/01/26.
//
import Foundation
import Speech
import AVFoundation
import Combine

struct MicrophoneDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

enum MicrophoneCatalog {
    static func availableMicrophones() -> [MicrophoneDevice] {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone],
                                                       mediaType: .audio,
                                                       position: .unspecified)
        return session.devices.map { MicrophoneDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func device(for id: String?) -> AVCaptureDevice? {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone],
                                                       mediaType: .audio,
                                                       position: .unspecified).devices
        if let id, let selected = devices.first(where: { $0.uniqueID == id }) {
            return selected
        }
        if let systemDefault = AVCaptureDevice.default(for: .audio) {
            return systemDefault
        }
        return devices.first
    }

    static func isLikelyVirtualSilentDefault(_ device: AVCaptureDevice?) -> Bool {
        guard let name = device?.localizedName.lowercased() else { return false }
        return name.contains("zoom")
            || name.contains("teams")
            || name.contains("blackhole")
            || name.contains("loopback")
            || name.contains("soundflower")
    }
}

final class SpeechVoiceActivityDetector: NSObject, ObservableObject {
    @Published var isSpeaking: Bool = false
    @Published var statusText: String = "Off"
    @Published var transcript: String = ""
    @Published var inputLevel: Float = 0
    @Published var activeInputName: String = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let captureQueue = DispatchQueue(label: "Utterbox.SpeechCapture")

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastResultTime: Date = .distantPast
    private var isRestarting = false
    private var contextualStrings: [String] = []
    private var selectedMicrophoneID: String?
    private var recognitionMode: SpeechRecognitionMode = .onDeviceOnly
    private var receivedAudioFrames = 0

    func start(contextualStrings: [String] = [],
               recognitionMode: SpeechRecognitionMode = SpeechRecognitionMode.fromDefaults(),
               selectedMicrophoneID: String? = UserDefaults.standard.string(forKey: DefaultsKey.selectedMicrophoneID)) {
        self.contextualStrings = contextualStrings
        self.recognitionMode = recognitionMode
        self.selectedMicrophoneID = selectedMicrophoneID

        Task { @MainActor in
            let speechOK = await requestSpeechPermission()
            let micOK = await requestMicPermission()
            print("SpeechVoiceActivityDetector: permissions speech=\(speechOK) mic=\(micOK)")
            guard speechOK, micOK else {
                statusText = "Permission denied"
                isSpeaking = false
                return
            }
            startRecognition()
        }
    }

    func stop() {
        stopAudioPipeline(cancelTask: true)
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.statusText = "Off"
            self.transcript = ""
            self.inputLevel = 0
            self.activeInputName = ""
        }
        print("SpeechVoiceActivityDetector: stopped")
    }

    @MainActor
    private func requestSpeechPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { newStatus in
                print("SpeechVoiceActivityDetector: speech auth status=\(newStatus.rawValue)")
                cont.resume(returning: newStatus == .authorized)
            }
        }
    }

    @MainActor
    private func requestMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    print("SpeechVoiceActivityDetector: mic granted=\(granted)")
                    cont.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    @MainActor
    private func startRecognition() {
        stopAudioPipeline(cancelTask: true)

        guard let recognizer else {
            statusText = "Recognizer nil"
            return
        }

        print("SpeechVoiceActivityDetector: recognizer locale=\(recognizer.locale.identifier) available=\(recognizer.isAvailable) supportsOnDevice=\(recognizer.supportsOnDeviceRecognition)")
        guard recognizer.isAvailable else {
            statusText = "Recognizer unavailable"
            return
        }
        guard recognitionMode == .allowServerFallback || recognizer.supportsOnDeviceRecognition else {
            statusText = "On-device speech unavailable"
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        req.contextualStrings = contextualStrings
        req.requiresOnDeviceRecognition = recognitionMode == .onDeviceOnly
        request = req
        lastResultTime = .distantPast
        receivedAudioFrames = 0
        statusText = "Listening..."

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.lastResultTime = Date()
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.isSpeaking = true
                    self.statusText = result.isFinal ? "Final" : "Recognizing..."
                    self.transcript = text
                }

                if result.isFinal {
                    self.scheduleRecognitionRestart()
                }
                return
            }

            if let error {
                print("SpeechVoiceActivityDetector: recognition error: \(error)")
                DispatchQueue.main.async {
                    self.statusText = "Recognition restarting..."
                    self.isSpeaking = false
                }
                self.scheduleRecognitionRestart()
            }
        }

        do {
            try startAudioPipeline(request: req)
            startSilenceTimer()
            print("SpeechVoiceActivityDetector: AVCaptureSession started")
        } catch {
            print("SpeechVoiceActivityDetector: capture error: \(error)")
            statusText = "Mic input error"
            stopAudioPipeline(cancelTask: true)
        }
    }

    private func startAudioPipeline(request: SFSpeechAudioBufferRecognitionRequest) throws {
        var device = MicrophoneCatalog.device(for: selectedMicrophoneID)
        if selectedMicrophoneID != nil,
           MicrophoneCatalog.isLikelyVirtualSilentDefault(device) {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.selectedMicrophoneID)
            selectedMicrophoneID = nil
            device = MicrophoneCatalog.device(for: nil)
        }

        guard let device else {
            throw SpeechDetectorError.noInputDevice
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw SpeechDetectorError.cannotAddInput
        }
        session.addInput(input)

        audioOutput.setSampleBufferDelegate(self, queue: captureQueue)
        audioOutput.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        guard session.canAddOutput(audioOutput) else {
            session.commitConfiguration()
            throw SpeechDetectorError.cannotAddOutput
        }
        session.addOutput(audioOutput)
        session.commitConfiguration()

        DispatchQueue.main.async {
            self.activeInputName = device.localizedName
            self.statusText = "Listening: \(device.localizedName)"
        }

        session.startRunning()
        scheduleCaptureWatchdog(for: device.localizedName)
    }

    private func stopAudioPipeline(cancelTask: Bool) {
        silenceTimer?.invalidate()
        silenceTimer = nil

        if cancelTask {
            task?.cancel()
            task = nil
        }

        request?.endAudio()
        request = nil

        audioOutput.setSampleBufferDelegate(nil, queue: nil)
        if session.isRunning {
            session.stopRunning()
        }
        receivedAudioFrames = 0
        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
    }

    private func scheduleRecognitionRestart() {
        guard !isRestarting else { return }
        isRestarting = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.isRestarting = false
            guard self.request != nil || self.session.isRunning else { return }
            self.startRecognition()
        }
    }

    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Date().timeIntervalSince(self.lastResultTime) > 0.8 {
                DispatchQueue.main.async { self.isSpeaking = false }
            }
        }
    }

    private func scheduleCaptureWatchdog(for inputName: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.session.isRunning else { return }
            if self.receivedAudioFrames == 0 {
                self.statusText = "No audio from \(inputName)"
            } else if self.inputLevel < 0.0005 {
                self.statusText = "Very low input: \(inputName)"
            }
        }
    }

    private func appendToSpeechRequest(_ sampleBuffer: CMSampleBuffer) {
        guard let request else { return }
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer,
                                                                  at: 0,
                                                                  frameCount: Int32(frameCount),
                                                                  into: pcmBuffer.mutableAudioBufferList)
        guard status == noErr else {
            print("SpeechVoiceActivityDetector: PCM copy failed status=\(status)")
            return
        }

        updateInputLevel(pcmBuffer)
        receivedAudioFrames += Int(frameCount)
        request.append(pcmBuffer)
    }

    private func updateInputLevel(_ buffer: AVAudioPCMBuffer) {
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        var sum: Float = 0
        var count = 0

        for audioBuffer in buffers {
            guard let data = audioBuffer.mData else { continue }
            let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
            guard sampleCount > 0 else { continue }
            let samples = data.bindMemory(to: Float.self, capacity: sampleCount)
            for index in 0..<sampleCount {
                let value = samples[index]
                sum += value * value
            }
            count += sampleCount
        }

        guard count > 0 else { return }
        let rms = sqrt(sum / Float(count))
        DispatchQueue.main.async {
            self.inputLevel = rms
        }
    }
}

extension SpeechVoiceActivityDetector: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        appendToSpeechRequest(sampleBuffer)
    }
}

private enum SpeechDetectorError: Error {
    case noInputDevice
    case cannotAddInput
    case cannotAddOutput
}
