// WatchHaptics.swift — haptic routing + the CPR metronome.
// Metronome: haptic .click every beat (110 bpm default) with an OPTIONAL soft
// synthesized tick (C5 + one octave harmonic, eased attack so there's no
// click, quick decay — woodblock-ish rather than the old raw 880 Hz beep).
// Sound is OFF by default — haptic-only per spec. `envelope` (and its eased
// shadow `smoothed`) are read on the render thread while written/decayed
// across threads; that benign race is intentional and fine for a demo.

import WatchKit
import AVFoundation
import OSLog
import CodeCore

enum WatchHaptics {
    static var enabled = true

    static func play(_ type: WKHapticType) {
        guard enabled else { return }
        WKInterfaceDevice.current().play(type)
    }

    /// User-mapped cue rhythms (Settings → Haptics). watchOS exposes no raw
    /// intensity, so distinct SEQUENCES are what makes cues tellable-apart
    /// without looking: pulse check vs med due vs swap-compressors moment.
    @MainActor
    static func play(_ pattern: HapticPattern) {
        guard enabled else { return }
        switch pattern {
        case .single:
            play(.notification)
        case .double:
            sequence([.directionUp, .directionUp], gap: 0.20)
        case .triple:
            sequence([.click, .click, .click], gap: 0.16)
        case .long:
            sequence([.start, .stop], gap: 0.45)
        }
    }

    @MainActor
    private static func sequence(_ types: [WKHapticType], gap: TimeInterval) {
        Task { @MainActor in
            for (i, t) in types.enumerated() {
                if i > 0 { try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000)) }
                play(t)
            }
        }
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
    private var frequency: Double = MetronomePitch.medium.frequency

    func start(bpm: Int, soundOn: Bool, pitch: MetronomePitch = .medium) {
        stop()
        self.soundOn = soundOn
        self.frequency = pitch.frequency
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
        // Every failure here used to be `try?`-swallowed — a silent metronome
        // with no trace. Log loudly instead; the sound is a safety feature.
        let log = Logger(subsystem: "com.sebastianheredia.CodeRing", category: "metronome")
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            log.error("audio session setup failed: \(error.localizedDescription)")
        }

        let audioEngine = AVAudioEngine()
        let output = audioEngine.outputNode
        let format = output.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            log.error("output format unusable (rate \(format.sampleRate), ch \(format.channelCount)) — no tick")
            return
        }
        sampleRate = format.sampleRate
        let freq = frequency   // user-selectable pitch (Settings → Metronome)

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
        do {
            try audioEngine.start()
            log.info("metronome audio running at \(freq, format: .fixed(precision: 1)) Hz")
        } catch {
            log.error("audio engine start failed: \(error.localizedDescription)")
        }
        engine = audioEngine
        source = node
    }
}
