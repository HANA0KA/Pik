import AVFoundation
import CoreMedia
import XCTest
@testable import PikKit

final class MovieWriterTests: XCTestCase {
    private func makePixelBuffer(w: Int, h: Int, shade: UInt8) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        let base = CVPixelBufferGetBaseAddress(pb!)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pb!)
        for y in 0..<h { for x in 0..<w {
            let o = y * stride + x * 4
            base[o] = shade; base[o + 1] = UInt8((x * 255) / w); base[o + 2] = UInt8((y * 255) / h); base[o + 3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(pb!, [])
        return pb!
    }

    /// Genera un buffer de audio "de micrófono" (Float32 mono 44,1 kHz) como lo entregaría AVCapture.
    private func makeMicBuffer(frames: Int, startFrame: Int, pts: CMTime) -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 4, mFramesPerPacket: 1,
            mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var fd: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &fd)
        var samples = (0..<frames).map { Float(sin(2 * Double.pi * 440 * Double($0 + startFrame) / 44_100)) * 0.4 }
        var bb: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: frames * 4, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: frames * 4, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &bb)
        CMBlockBufferReplaceDataBytes(with: &samples, blockBuffer: bb!, offsetIntoDestination: 0, dataLength: frames * 4)
        var sb: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: bb!, formatDescription: fd!, sampleCount: frames, presentationTimeStamp: pts, packetDescriptions: nil, sampleBufferOut: &sb)
        return sb!
    }

    func testWritesPlayableMP4WithAudioAndVideo() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pik-test-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let w = try MovieWriter(config: .init(url: url, width: 640, height: 360, fps: 30))
        try w.start()
        let mixer = AudioMixer(hasMic: true, hasSystem: false) { s, f, pts in w.appendAudio(samples: s, frames: f, pts: pts) }

        let t0 = MovieWriter.hostNow()
        let frameCount = 90
        var audioFrame = 0
        for i in 0..<frameCount {
            let pts = CMTimeAdd(t0, CMTime(value: CMTimeValue(i), timescale: 30))
            w.appendVideo(makePixelBuffer(w: 640, h: 360, shade: UInt8(i * 2)), pts: pts)
            // 1/30 s de audio a 44,1 kHz = 1470 muestras
            mixer.pushMic(makeMicBuffer(frames: 1470, startFrame: audioFrame, pts: pts))
            audioFrame += 1470
            try await Task.sleep(nanoseconds: 8_000_000)
        }
        // Dejar que la cola termine y que el "reloj de pared" no domine la duración.
        let result = try await w.finish()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertGreaterThan(result.duration, 2.5)

        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(video.count, 1)
        XCTAssertEqual(audio.count, 1)
        let dur = try await asset.load(.duration).seconds
        XCTAssertGreaterThan(dur, 2.4)
        let size = try await video[0].load(.naturalSize)
        XCTAssertEqual(Int(size.width), 640)
    }

    func testPauseRemovesPausedTimeFromTimeline() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pik-test-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let w = try MovieWriter(config: .init(url: url, width: 320, height: 180, fps: 30, withAudio: false))
        try w.start()
        func push(_ n: Int, shade: UInt8) async throws {
            for _ in 0..<n {
                w.appendVideo(makePixelBuffer(w: 320, h: 180, shade: shade), pts: MovieWriter.hostNow())
                try await Task.sleep(nanoseconds: 33_000_000)
            }
        }
        let begin = Date()
        var active: TimeInterval = 0
        var mark = Date()
        try await push(30, shade: 10)
        active += Date().timeIntervalSince(mark)
        w.pause()
        try await Task.sleep(nanoseconds: 1_500_000_000)   // 1,5 s en pausa (no debe contar)
        w.resume()
        mark = Date()
        try await push(30, shade: 200)
        active += Date().timeIntervalSince(mark)
        let wall = Date().timeIntervalSince(begin)
        let result = try await w.finish()
        XCTAssertEqual(result.duration, active, accuracy: 0.45, "la duración debe ser el tiempo activo, no el de pared")
        XCTAssertLessThan(result.duration, wall - 1.0, "la pausa no debe sumar tiempo al video")
    }

    func testAudioMixerSumsMicAndSystem() {
        var captured: [Float] = []
        let mixer = AudioMixer(hasMic: true, hasSystem: true) { s, f, _ in
            captured.append(contentsOf: UnsafeBufferPointer(start: s, count: f * 2))
        }
        mixer.noiseSuppression = false      // la señal de prueba es constante: el supresor la tomaría por ruido
        func buf(_ rate: Double, _ value: Float, frames: Int) -> CMSampleBuffer {
            var asbd = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 4, mFramesPerPacket: 1,
                mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
            var fd: CMAudioFormatDescription?
            CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &fd)
            var samples = [Float](repeating: value, count: frames)
            var bb: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: frames * 4, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: frames * 4, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &bb)
            CMBlockBufferReplaceDataBytes(with: &samples, blockBuffer: bb!, offsetIntoDestination: 0, dataLength: frames * 4)
            var sb: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: bb!, formatDescription: fd!, sampleCount: frames, presentationTimeStamp: .zero, packetDescriptions: nil, sampleBufferOut: &sb)
            return sb!
        }
        for _ in 0..<4 { mixer.pushSystem(buf(48_000, 0.2, frames: 4800)) }
        for _ in 0..<2 { mixer.pushMic(buf(48_000, 0.3, frames: 4800)) }
        XCTAssertFalse(captured.isEmpty)
        // Mitad del camino: mic (0.3) + sistema (0.2 * 0.9) ≈ 0.48
        let mid = captured[captured.count / 2]
        XCTAssertEqual(mid, 0.3 + 0.2 * 0.9, accuracy: 0.03)
    }

    /// Regresión: con micrófono de 48 kHz los bloques salen perfectamente encadenados (PTS == fin del bloque anterior).
    /// Antes se descartaba uno de cada dos bloques y el audio quedaba con la mitad de duración (voz cortada/distorsionada).
    func testContiguousMicBlocksAreAllWritten() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pik-test-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let w = try MovieWriter(config: .init(url: url, width: 320, height: 180, fps: 30))
        try w.start()
        let mixer = AudioMixer(hasMic: true, hasSystem: false) { s, f, pts in w.appendAudio(samples: s, frames: f, pts: pts) }
        mixer.noiseSuppression = false
        let t0 = MovieWriter.hostNow()
        let seconds = 3.0
        var pos = 0
        let block = 1024
        for i in 0..<Int(seconds * 30) {
            w.appendVideo(makePixelBuffer(w: 320, h: 180, shade: UInt8(i)), pts: CMTimeAdd(t0, CMTime(value: CMTimeValue(i), timescale: 30)))
            // el audio que "ha pasado" hasta este fotograma, en bloques de 1024 a 48 kHz
            while Double(pos + block) / 48_000 <= Double(i + 1) / 30 {
                let pts = CMTimeAdd(t0, CMTime(value: CMTimeValue(pos), timescale: 48_000))
                mixer.pushMic(AudioPipelineTests.sineBuffer(rate: 48_000, start: pos, frames: block, pts: pts))
                pos += block
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        _ = try await w.finish()
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let audioDur = try await audio[0].load(.timeRange).duration.seconds
        let fed = Double(pos) / 48_000
        XCTAssertGreaterThan(audioDur, fed * 0.9, "el audio debe cubrir lo que se alimentó (\(fed) s), no la mitad")
    }
}
