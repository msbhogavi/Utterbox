//
//  VoiceActivityDetector.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 02/01/26.
//
import Foundation
import AVFoundation
import Combine
import AudioToolbox

final class VoiceActivityDetector: NSObject, ObservableObject {
    @Published var isSpeaking: Bool = false
    @Published var level: Float = 0
    @Published var threshold: Float = 0.01
    @Published var bufferCount: Int = 0

    private let holdTime: TimeInterval = 0.25
    private var lastAboveThreshold: Date = .distantPast

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "VoiceActivityDetector.AudioQueue")

    private var isRunning = false
    private var didPrintFormat = false

    func start() {
        if isRunning { return }

        Task { @MainActor in
            let ok = await requestPermissionIfNeeded()
            if !ok {
                print("VoiceActivityDetector: microphone permission NOT granted")
                return
            }
            configureSession()
            session.startRunning()
            isRunning = true
            print("VoiceActivityDetector: AVCaptureSession started")
        }
    }

    func stop() {
        guard isRunning else { return }
        session.stopRunning()
        isRunning = false
        didPrintFormat = false
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.level = 0
            self.bufferCount = 0
        }
        print("VoiceActivityDetector: AVCaptureSession stopped")
    }

    @MainActor
    private func requestPermissionIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    cont.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        for input in session.inputs { session.removeInput(input) }
        for out in session.outputs { session.removeOutput(out) }

        let devices = AVCaptureDevice.devices(for: .audio)
        let preferred = devices.first(where: { $0.localizedName == "MacBook Pro Microphone" }) ?? devices.first

        guard let device = preferred else {
            print("VoiceActivityDetector: No audio capture devices available")
            session.commitConfiguration()
            return
        }

        print("VoiceActivityDetector: Using device = \(device.localizedName)")

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            print("VoiceActivityDetector: Failed to create device input: \(error)")
            session.commitConfiguration()
            return
        }

        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }

        session.commitConfiguration()
    }

    private func process(level lvl: Float) {
        let now = Date()
        if lvl > threshold { lastAboveThreshold = now }
        let speakingNow = now.timeIntervalSince(lastAboveThreshold) < holdTime

        DispatchQueue.main.async {
            self.level = lvl
            self.isSpeaking = speakingNow
        }
    }

    /// Read audio samples as Float32 from the CMBlockBuffer and compute max-abs level.
    /// (Your ASBD indicates Float32, 1ch, bytesPerFrame=4.)
    private func levelFloat32(sampleBuffer: CMSampleBuffer) -> Float {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0 }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let st = CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard st == kCMBlockBufferNoErr, let dataPointer, length > 0 else { return 0 }

        let sampleCount = length / MemoryLayout<Float>.size
        guard sampleCount > 0 else { return 0 }

        let samples = dataPointer.withMemoryRebound(to: Float.self, capacity: sampleCount) { ptr in
            UnsafeBufferPointer(start: ptr, count: sampleCount)
        }

        var sum: Float = 0
        for s in samples {
            sum += s * s
        }
        return sqrt(sum / Float(sampleCount)) // RMS
    }
}

extension VoiceActivityDetector: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        let newCount = bufferCount + 1
        DispatchQueue.main.async { self.bufferCount = newCount }

        if !didPrintFormat, let fmt = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee {
            didPrintFormat = true
            print("VoiceActivityDetector: ASBD sampleRate=\(asbd.mSampleRate) channels=\(asbd.mChannelsPerFrame) bytesPerFrame=\(asbd.mBytesPerFrame) formatFlags=\(asbd.mFormatFlags) bits=\(asbd.mBitsPerChannel)")
        }

        let lvl = levelFloat32(sampleBuffer: sampleBuffer)

        if newCount % 200 == 0 {
            print("VoiceActivityDetector: RMS(Float32) ~ \(String(format: "%.4f", lvl))")
        }

        process(level: lvl)
    }
}
