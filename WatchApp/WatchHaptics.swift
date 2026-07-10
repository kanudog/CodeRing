// WatchHaptics.swift — haptic routing + the CPR metronome.
// Metronome: haptic .click every beat (110 bpm default) with an OPTIONAL soft
// synthesized tick (C5 + one octave harmonic, eased attack so there's no
// click, quick decay — woodblock-ish rather than the old raw 880 Hz beep).
// Sound is OFF by default — haptic-only per spec. `envelope` (and its eased
// shadow `smoothed`) are read on the render thread while written/decayed
// across threads; that benign race is intentional and fine for a demo.

import WatchKit
import AVFoundation
import CodeCore

enum WatchHaptics {
    static var enabled = true

    static func play(_ type: WKHapticType) {
        guard enabled else { return }
        WKInterfaceDevice.current().play(type)
    }
}

final class ToneMetronome {

    private var timer: Timer?
    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    private var envelope: Float = 0
    private var smoothed: Float = 0    // render-thread eased copy — kills the attack click
    private var time: Double = 0
    private var sampleRate: Double = 44_100
    private(set) var isRunning = false
    private var soundOn = false

    func start(bpm: Int, soundOn: Bool) {
        stop()
        self.soundOn = soundOn
        if soundOn { startAudio() }
        let interval = 60.0 / Double(max(60, min(160, bpm)))
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        isRunning = true
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        engine?.stop()
        engine = nil
        source = nil
        isRunning = false
    }

    private func tick() {
        WatchHaptics.play(.click)
        if soundOn { envelope = 1.0 }
    }

    private func startAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)

        let audioEngine = AVAudioEngine()
        let output = audioEngine.outputNode
        let format = output.inputFormat(forBus: 0)
        sampleRate = format.sampleRate
        let freq = 523.25   // C5 — warmer than the old 880 Hz beep

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                // Eased attack + a quiet octave overtone + squared tail:
                // reads as a soft wooden tick instead of a phone-alarm sine.
                self.smoothed += (self.envelope - self.smoothed) * 0.02
                let phase = 2.0 * .pi * freq * self.time
                let tone = Float(sin(phase)) * 0.72 + Float(sin(2.0 * phase)) * 0.28
                let sample = tone * self.smoothed * self.smoothed * 0.32
                self.time += 1.0 / self.sampleRate
                self.envelope *= 0.9982   // quicker, cleaner decay
                for buffer in ablPointer {
                    let buf = UnsafeMutableBufferPointer<Float>(buffer)
                    if frame < buf.count { buf[frame] = sample }
                }
            }
            return noErr
        }

        audioEngine.attach(node)
        audioEngine.connect(node, to: output, format: format)
        try? audioEngine.start()
        engine = audioEngine
        source = node
    }
}
