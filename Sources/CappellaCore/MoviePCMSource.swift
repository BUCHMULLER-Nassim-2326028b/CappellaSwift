import Foundation

/// Reads only the selected VO/VI channels and pads silence in bounded blocks.
/// Offline export does not need complete interleaved copies of the soundtrack.
public final class MoviePCMSource {
    private let inputs: [PCMChannelPreparation.Stream]
    private let channels: [(input: Int, channel: Int)]
    public let sampleRate: Int
    public let bitsPerSample: Int
    public var channelCount: Int { channels.count }
    public init(sources: [URL], international: Bool) throws {
        inputs = try sources.map { try PCMChannelPreparation.Stream($0) }
        guard let first = inputs.first else { throw ProjectError.invalid("Aucune piste audio à exporter.") }
        sampleRate = first.sampleRate; bitsPerSample = first.bitsPerSample
        guard inputs.allSatisfy({ $0.sampleRate == first.sampleRate && $0.bitsPerSample == first.bitsPerSample }) else {
            throw ProjectError.invalid("Les flux audio doivent avoir le même format PCM.")
        }
        let all = inputs.enumerated().flatMap { index, input in
            (0..<input.channels).map { (input: index, channel: $0) }
        }
        let selection = AudioRouting.selectedChannels(total: all.count, international: international)
        guard !selection.isEmpty else { throw ProjectError.invalid("Le média ne contient pas de piste VI.") }
        channels = selection.map { all[$0] }
        guard channels.count <= 2 else { throw ProjectError.invalid("L'export audio attend une piste VO/VI mono ou stéréo.") }
    }
    public func read(frame: Int, count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        let bytes = bitsPerSample / 8, stride = channels.count * bytes
        var result = Data(repeating: bitsPerSample == 8 ? 128 : 0, count: count * stride)
        let silence = min(count, max(0, -frame)), start = max(0, frame)
        if channels.allSatisfy({ $0.input == channels[0].input }) {
            let input = inputs[channels[0].input]
            let amount = min(count - silence, max(0, input.frameCount - start))
            if amount > 0 {
                let data = try input.read(frame: start, count: amount, channels: channels.map(\.channel))
                result.replaceSubrange(silence * stride..<(silence * stride + data.count), with: data)
            }
            return result
        }
        for (index, channel) in channels.enumerated() {
            let input = inputs[channel.input], amount = min(count - silence, max(0, inputs[channel.input].frameCount - start))
            guard amount > 0 else { continue }
            let data = try input.read(frame: start, count: amount, channels: [channel.channel])
            result.withUnsafeMutableBytes { target in
                data.withUnsafeBytes { source in
                    for sample in 0..<amount {
                        target.baseAddress!.advanced(by: (sample + silence) * stride + index * bytes)
                            .copyMemory(from: source.baseAddress!.advanced(by: sample * bytes), byteCount: bytes)
                    }
                }
            }
        }
        return result
    }
}
