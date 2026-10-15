import XCTest
import AVFoundation
import CoreMedia
@testable import PikKit

final class AudioPipelineTests: XCTestCase {
    static func sineBuffer(rate: Double, channels: Int = 1, start: Int, frames: Int, freq: Float = 440, amp: Float = 0.5, pts: CMTime? = nil) -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: UInt32(4 * channels), mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channels), mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var fd: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &fd)
        var samples = [Float](repeating: 0, count: frames * channels)
        for i in 0..<frames { for c in 0..<channels { samples[i * channels + c] = amp * sinf(2 * .pi * freq * Float(start + i) / Float(rate)) } }
        var bb: CMBlockBuffer?
        let bytes = frames * 4 * channels
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &bb)
        CMBlockBufferReplaceDataBytes(with: &samples, blockBuffer: bb!, offsetIntoDestination: 0, dataLength: bytes)
        var sb: CMSampleBuffer?
        let pts = pts ?? CMTime(value: CMTimeValue(start), timescale: CMTimeScale(rate))
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: bb!, formatDescription: fd!, sampleCount: frames, presentationTimeStamp: pts, packetDescriptions: nil, sampleBufferOut: &sb)
        return sb!
    }

    /// Pasa un seno por el mezclador y devuelve (muestras L, pts de cada bloque, frames de cada bloque).
    func run(rate: Double, block: Int, seconds: Double, suppress: Bool, system: Bool = false) -> (left: [Float], blocks: [(pts: CMTime, frames: Int)]) {
        var left: [Float] = []
        var blocks: [(CMTime, Int)] = []
        let mixer = AudioMixer(hasMic: true, hasSystem: system) { s, f, pts in
            for i in 0..<f { left.append(s[i * 2]) }
            blocks.append((pts, f))
        }
        mixer.noiseSuppression = suppress
        var pos = 0
        let total = Int(rate * seconds)
        while pos + block <= total {
            mixer.pushMic(Self.sineBuffer(rate: rate, start: pos, frames: block))
            pos += block
        }
        return (left, blocks)
    }

    /// Mayor salto entre muestras vecinas (un seno puro de 440 Hz a 0.5 nunca pasa de ~0.03).
    func maxJump(_ x: [Float], skip: Int = 4000) -> Float {
        var m: Float = 0
        for i in (skip + 1)..<x.count { m = max(m, abs(x[i] - x[i - 1])) }
        return m
    }

    func testResampledMicIsContinuous44k() {
        let r = run(rate: 44_100, block: 1024, seconds: 2, suppress: false)
        print("44k jump:", maxJump(r.left), "frames:", r.left.count, "expected:", Int(2 * 48_000))
        XCTAssertLessThan(maxJump(r.left), 0.08)
    }

    func testNativeMicIsContinuous48k() {
        let r = run(rate: 48_000, block: 1024, seconds: 2, suppress: false)
        print("48k jump:", maxJump(r.left))
        XCTAssertLessThan(maxJump(r.left), 0.08)
    }

    func testTimestampsAreContiguous() {
        let r = run(rate: 44_100, block: 1024, seconds: 2, suppress: false)
        var worst = 0.0
        for i in 1..<r.blocks.count {
            let expected = CMTimeAdd(r.blocks[i - 1].pts, CMTime(value: CMTimeValue(r.blocks[i - 1].frames), timescale: 48_000))
            worst = max(worst, abs(CMTimeGetSeconds(CMTimeSubtract(r.blocks[i].pts, expected))))
        }
        print("peor desfase de pts:", worst)
        XCTAssertLessThan(worst, 0.0001)
    }

    func testSuppressorKeepsSineClean() {
        let r = run(rate: 48_000, block: 1024, seconds: 3, suppress: true)
        print("suppress jump:", maxJump(r.left, skip: 48_000))
        XCTAssertLessThan(maxJump(r.left, skip: 48_000), 0.08)
    }
}
