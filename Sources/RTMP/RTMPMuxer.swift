import AVFoundation

// MARK: -
final class RTMPMuxer {
    static let aac: UInt8 = FLVAudioCodec.aac.rawValue << 4 | FLVSoundRate.kHz44.rawValue << 2 | FLVSoundSize.snd16bit.rawValue << 1 | FLVSoundType.stereo.rawValue

    // so the muxer keeps the 1st buffer so on add it can play these
    var firstAudioBuffer : Data? = nil
    var firstVideoBuffer : Data? = nil
    
    var audioFormat: AVAudioFormat? {
        didSet {
            if stream == nil {
                print("LIVESTREAMER AUDIO FOR CHILD.DISCARD")
                return
            }
            print("LIVESTREAMER \(stream) AUDIO FORMAT SET")
            switch stream?.readyState {
            case .publishing:
                print("LIVESTREAMER \(stream) AUDIO FORMAT SET AND PUBLISHING")
                guard let audioFormat else {
                    print("LIVESTREAMER \(stream) AUDIO FORMAT IS NIL")
                    return
                }
                print("LIVESTREAMER \(stream) AUDIO FORMAT SET AND PUBLISHING AAC")

                var buffer = Data([RTMPMuxer.aac, FLVAACPacketType.seq.rawValue])
                buffer.append(contentsOf: AudioSpecificConfig(formatDescription: audioFormat.formatDescription).bytes)
                stream?.outputAudio(buffer, withTimestamp: 0)
                slock.lock()
                firstAudioBuffer = buffer
                let others = additionalStreams
                slock.unlock()
                print("LIVESTREAMER others aac \(others.count)")
                for ast in others {
                    ast.outputAudio(buffer, withTimestamp: 0)
                }
            case .playing:
                if let audioFormat {
                    audioBuffer = AVAudioCompressedBuffer(format: audioFormat, packetCapacity: 1, maximumPacketSize: 1024 * Int(audioFormat.channelCount))
                } else {
                    audioBuffer = nil
                }
            default:
                print("LIVESTREAMER \(stream) AUDIO FORMAT SET AND NOT PUBLISHING")
                break
            }
        }
    }

    var videoFormat: CMFormatDescription? {
        didSet {
            if stream == nil {
                print("LIVESTREAMER AUDIO FOR CHILD.DISCARD")
                return
            }

            print("LIVESTREAMER \(stream) VIDEO FORMAT SET")
            switch stream?.readyState {
            case .publishing:
                print("LIVESTREAMER \(stream) VIDEO FORMAT SET AND PUBLISHING")
                guard let videoFormat else {
                    print("LIVESTREAMER \(stream) VIDEO FORMAT IS NIL")
                    return
                }
                switch CMFormatDescriptionGetMediaSubType(videoFormat) {
                case kCMVideoCodecType_H264:
                    guard let avcC = AVCDecoderConfigurationRecord.getData(videoFormat) else {
                        return
                    }
                    print("LIVESTREAMER \(stream) VIDEO FORMAT SET AND PUBLISHING H264")

                    var buffer = Data([FLVFrameType.key.rawValue << 4 | FLVVideoCodec.avc.rawValue, FLVAVCPacketType.seq.rawValue, 0, 0, 0])
                    buffer.append(avcC)
                    stream?.outputVideo(buffer, withTimestamp: 0)
                    slock.lock()
                    firstVideoBuffer = buffer
                    let others = additionalStreams
                    slock.unlock()
                    print("LIVESTREAMER others h264 \(others.count)")
                    for ast in others {
                        ast.outputVideo(buffer, withTimestamp: 0)
                    }


                case kCMVideoCodecType_HEVC:
                    guard let hvcC = HEVCDecoderConfigurationRecord.getData(videoFormat) else {
                        return
                    }
                    print("LIVESTREAMER \(stream) VIDEO FORMAT SET AND PUBLISHING HEVC")

                    var buffer = Data([0b10000000 | FLVFrameType.key.rawValue << 4 | FLVVideoPacketType.sequenceStart.rawValue, 0x68, 0x76, 0x63, 0x31])
                    buffer.append(hvcC)
                    stream?.outputVideo(buffer, withTimestamp: 0)
                    slock.lock()
                    firstVideoBuffer = buffer
                    let others = additionalStreams
                    slock.unlock()
                    print("LIVESTREAMER others hevc \(others.count)")
                    for ast in others {
                        ast.outputVideo(buffer, withTimestamp: 0)
                    }

                default:
                    break
                }
            case .playing:
                stream?.dispatch(.rtmpStatus, bubbles: false, data: RTMPStream.Code.videoDimensionChange.data(""))
            default:
                print("LIVESTREAMER \(stream) VIDEO FORMAT SET AND NOT PUBLISHING")
                break
            }
        }
    }

    var isRunning: Atomic<Bool> = .init(false)
    private var videoTimeStamp: CMTime = .zero
    private var audioBuffer: AVAudioCompressedBuffer?
    private var audioTimeStamp: AVAudioTime = .init(hostTime: 0)
    private let compositiionTimeOffset: CMTime = .init(value: 3, timescale: 30)
    private weak var stream: RTMPStream?

    let slock = NSLock()
    private var additionalStreams: [RTMPStream] = []

    init(_ stream: RTMPStream?) {
        self.stream = stream
    }

    func addStream(stream: RTMPStream) {
        slock.lock()
        additionalStreams.append(stream)
        slock.unlock()
        // so WHEN should we add first audio/video buffers to the added stream?
        // when they are publishing.
        // should these be added ONCE they are publishing then?
        // makes sense!
        if let audio = firstAudioBuffer {
            print("LIVESTREAMER \(self.stream) CATCHUP AUDIO \(stream)")
            stream.outputAudio(audio, withTimestamp: 0)
        }
        if let video = firstVideoBuffer {
            print("LIVESTREAMER \(self.stream) CATCHUP VIDEO \(stream)")
            stream.outputVideo(video, withTimestamp: 0)
        } else {
            print("LIVESTREAMER \(self.stream) CAN'T CATCHUP VIDEO YET \(stream)")
        }
    }

    func append(_ message: RTMPAudioMessage, type: RTMPChunkType) {
        let payload = message.payload
        let codec = message.codec
        stream?.info.byteCount.mutate { $0 += Int64(payload.count) }

        guard let stream, message.codec.isSupported else {
            return
        }

        switch payload[1] {
        case FLVAACPacketType.seq.rawValue:
            let config = AudioSpecificConfig(bytes: [UInt8](payload[codec.headerSize..<payload.count]))
            audioFormat = config?.makeAudioFormat()
        case FLVAACPacketType.raw.rawValue:
            if audioFormat == nil {
                audioFormat = message.makeAudioFormat()
            }
            payload.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Void in
                guard let baseAddress = buffer.baseAddress, let audioBuffer else {
                    return
                }
                let byteCount = payload.count - codec.headerSize
                audioBuffer.packetDescriptions?.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(byteCount))
                audioBuffer.packetCount = 1
                audioBuffer.byteLength = UInt32(byteCount)
                audioBuffer.data.copyMemory(from: baseAddress.advanced(by: codec.headerSize), byteCount: byteCount)
                stream.mixer.audioIO.append(audioBuffer, when: audioTimeStamp)
            }
        default:
            break
        }

        switch type {
        case .zero:
            audioTimeStamp = .init(hostTime: AVAudioTime.hostTime(forSeconds: Double(message.timestamp) / 1000))
        default:
            audioTimeStamp = .init(hostTime: AVAudioTime.hostTime(forSeconds: AVAudioTime.seconds(forHostTime: audioTimeStamp.hostTime) + Double(message.timestamp) / 1000))
        }
    }

    func append(_ message: RTMPVideoMessage, type: RTMPChunkType) {
        stream?.info.byteCount.mutate { $0 += Int64( message.payload.count) }
        guard let stream, FLVTagType.video.headerSize <= message.payload.count && message.isSupported else {
            return
        }

        if message.isExHeader {
            // IsExHeader for Enhancing RTMP, FLV
            switch message.packetType {
            case FLVVideoPacketType.sequenceStart.rawValue:
                videoFormat = message.makeFormatDescription()
            case FLVVideoPacketType.codedFrames.rawValue:
                if let sampleBuffer = message.makeSampleBuffer(videoTimeStamp, formatDesciption: videoFormat) {
                    stream.mixer.videoIO.append(sampleBuffer)
                }
            default:
                break
            }
        } else {
            switch message.packetType {
            case FLVAVCPacketType.seq.rawValue:
                videoFormat = message.makeFormatDescription()
            case FLVAVCPacketType.nal.rawValue:
                if let sampleBuffer = message.makeSampleBuffer(videoTimeStamp, formatDesciption: videoFormat) {
                    stream.mixer.videoIO.append(sampleBuffer)
                }
            default:
                break
            }
        }

        switch type {
        case .zero:
            videoTimeStamp = .init(value: CMTimeValue(message.timestamp), timescale: 1000)
        default:
            videoTimeStamp = CMTimeAdd(videoTimeStamp, .init(value: CMTimeValue(message.timestamp), timescale: 1000))
        }
    }
}

extension RTMPMuxer: IOMuxer {
    // MARK: IOMuxer
    func append(_ audioBuffer: AVAudioBuffer, when: AVAudioTime) {
        guard let audioBuffer = audioBuffer as? AVAudioCompressedBuffer else {
            return
        }
        let delta = audioTimeStamp.hostTime == 0 ? 0 :
            (AVAudioTime.seconds(forHostTime: when.hostTime) - AVAudioTime.seconds(forHostTime: audioTimeStamp.hostTime)) * 1000
        guard 0 <= delta else {
            return
        }
        var buffer = Data([RTMPMuxer.aac, FLVAACPacketType.raw.rawValue])
        buffer.append(audioBuffer.data.assumingMemoryBound(to: UInt8.self), count: Int(audioBuffer.byteLength))
        stream?.outputAudio(buffer, withTimestamp: delta)
        slock.lock()
        let others = additionalStreams
        slock.unlock()
        for ast in others {
            ast.outputAudio(buffer, withTimestamp: delta)
        }
        audioTimeStamp = when
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        let keyframe = !sampleBuffer.isNotSync
        let decodeTimeStamp = sampleBuffer.decodeTimeStamp.isValid ? sampleBuffer.decodeTimeStamp : sampleBuffer.presentationTimeStamp
        let compositionTime = getCompositionTime(sampleBuffer)
        let delta = videoTimeStamp == .zero ? 0 : (decodeTimeStamp.seconds - videoTimeStamp.seconds) * 1000
        guard let formatDescription = sampleBuffer.formatDescription, let data = sampleBuffer.dataBuffer?.data, 0 <= delta else {
            return
        }
        switch CMFormatDescriptionGetMediaSubType(formatDescription) {
        case kCMVideoCodecType_H264:
            var buffer = Data([((keyframe ? FLVFrameType.key.rawValue : FLVFrameType.inter.rawValue) << 4) | FLVVideoCodec.avc.rawValue, FLVAVCPacketType.nal.rawValue])
            buffer.append(contentsOf: compositionTime.bigEndian.data[1..<4])
            buffer.append(data)
            stream?.outputVideo(buffer, withTimestamp: delta)
            slock.lock()
            let others = additionalStreams
            slock.unlock()
            for ast in others {
                ast.outputVideo(buffer, withTimestamp: delta)
            }
        case kCMVideoCodecType_HEVC:
            var buffer = Data([0b10000000 | ((keyframe ? FLVFrameType.key.rawValue : FLVFrameType.inter.rawValue) << 4) | FLVVideoPacketType.codedFrames.rawValue, 0x68, 0x76, 0x63, 0x31])
            buffer.append(contentsOf: compositionTime.bigEndian.data[1..<4])
            buffer.append(data)
            stream?.outputVideo(buffer, withTimestamp: delta)
            slock.lock()
            let others = additionalStreams
            slock.unlock()
            for ast in others {
                ast.outputVideo(buffer, withTimestamp: delta)
            }
        default:
            break
        }
        videoTimeStamp = decodeTimeStamp
    }

    private func getCompositionTime(_ sampleBuffer: CMSampleBuffer) -> Int32 {
        guard sampleBuffer.decodeTimeStamp.isValid, sampleBuffer.decodeTimeStamp != sampleBuffer.presentationTimeStamp else {
            return 0
        }
        return Int32((sampleBuffer.presentationTimeStamp - videoTimeStamp + compositiionTimeOffset).seconds * 1000)
    }
}

extension RTMPMuxer: Running {
    // MARK: Running
    func startRunning() {
        guard !isRunning.value else {
            return
        }
        audioTimeStamp = .init(hostTime: 0)
        videoTimeStamp = .zero
        audioFormat = nil
        videoFormat = nil
        isRunning.mutate { $0 = true }
    }

    func stopRunning() {
        guard isRunning.value else {
            return
        }
        isRunning.mutate { $0 = false }
    }
}
