import AVFoundation

/// An object that provides the interface to control a one-way channel over a RtmpConnection.
open class RTMPStream: IOStream {
    /// NetStatusEvent#info.code for NetStream
    /// - seealso: https://help.adobe.com/en_US/air/reference/html/flash/events/NetStatusEvent.html#NET_STATUS
    public enum Code: String {
        case bufferEmpty               = "NetStream.Buffer.Empty"
        case bufferFlush               = "NetStream.Buffer.Flush"
        case bufferFull                = "NetStream.Buffer.Full"
        case connectClosed             = "NetStream.Connect.Closed"
        case connectFailed             = "NetStream.Connect.Failed"
        case connectRejected           = "NetStream.Connect.Rejected"
        case connectSuccess            = "NetStream.Connect.Success"
        case drmUpdateNeeded           = "NetStream.DRM.UpdateNeeded"
        case failed                    = "NetStream.Failed"
        case multicastStreamReset      = "NetStream.MulticastStream.Reset"
        case pauseNotify               = "NetStream.Pause.Notify"
        case playFailed                = "NetStream.Play.Failed"
        case playFileStructureInvalid  = "NetStream.Play.FileStructureInvalid"
        case playInsufficientBW        = "NetStream.Play.InsufficientBW"
        case playNoSupportedTrackFound = "NetStream.Play.NoSupportedTrackFound"
        case playReset                 = "NetStream.Play.Reset"
        case playStart                 = "NetStream.Play.Start"
        case playStop                  = "NetStream.Play.Stop"
        case playStreamNotFound        = "NetStream.Play.StreamNotFound"
        case playTransition            = "NetStream.Play.Transition"
        case playUnpublishNotify       = "NetStream.Play.UnpublishNotify"
        case publishBadName            = "NetStream.Publish.BadName"
        case publishIdle               = "NetStream.Publish.Idle"
        case publishStart              = "NetStream.Publish.Start"
        case recordAlreadyExists       = "NetStream.Record.AlreadyExists"
        case recordFailed              = "NetStream.Record.Failed"
        case recordNoAccess            = "NetStream.Record.NoAccess"
        case recordStart               = "NetStream.Record.Start"
        case recordStop                = "NetStream.Record.Stop"
        case recordDiskQuotaExceeded   = "NetStream.Record.DiskQuotaExceeded"
        case secondScreenStart         = "NetStream.SecondScreen.Start"
        case secondScreenStop          = "NetStream.SecondScreen.Stop"
        case seekFailed                = "NetStream.Seek.Failed"
        case seekInvalidTime           = "NetStream.Seek.InvalidTime"
        case seekNotify                = "NetStream.Seek.Notify"
        case stepNotify                = "NetStream.Step.Notify"
        case unpauseNotify             = "NetStream.Unpause.Notify"
        case unpublishSuccess          = "NetStream.Unpublish.Success"
        case videoDimensionChange      = "NetStream.Video.DimensionChange"

        public var level: String {
            switch self {
            case .bufferEmpty:
                return "status"
            case .bufferFlush:
                return "status"
            case .bufferFull:
                return "status"
            case .connectClosed:
                return "status"
            case .connectFailed:
                return "error"
            case .connectRejected:
                return "error"
            case .connectSuccess:
                return "status"
            case .drmUpdateNeeded:
                return "status"
            case .failed:
                return "error"
            case .multicastStreamReset:
                return "status"
            case .pauseNotify:
                return "status"
            case .playFailed:
                return "error"
            case .playFileStructureInvalid:
                return "error"
            case .playInsufficientBW:
                return "warning"
            case .playNoSupportedTrackFound:
                return "status"
            case .playReset:
                return "status"
            case .playStart:
                return "status"
            case .playStop:
                return "status"
            case .playStreamNotFound:
                return "error"
            case .playTransition:
                return "status"
            case .playUnpublishNotify:
                return "status"
            case .publishBadName:
                return "error"
            case .publishIdle:
                return "status"
            case .publishStart:
                return "status"
            case .recordAlreadyExists:
                return "status"
            case .recordFailed:
                return "error"
            case .recordNoAccess:
                return "error"
            case .recordStart:
                return "status"
            case .recordStop:
                return "status"
            case .recordDiskQuotaExceeded:
                return "error"
            case .secondScreenStart:
                return "status"
            case .secondScreenStop:
                return "status"
            case .seekFailed:
                return "error"
            case .seekInvalidTime:
                return "error"
            case .seekNotify:
                return "status"
            case .stepNotify:
                return "status"
            case .unpauseNotify:
                return "status"
            case .unpublishSuccess:
                return "status"
            case .videoDimensionChange:
                return "status"
            }
        }

        func data(_ description: String) -> ASObject {
            [
                "code": rawValue,
                "level": level,
                "description": description
            ]
        }
    }

    /// The type of publish options.
    public enum HowToPublish: String {
        /// Publish with server-side recording.
        case record
        /// Publish with server-side recording which is to append file if exists.
        case append
        /// Publish with server-side recording which is to append and ajust time file if exists.
        case appendWithGap
        /// Publish.
        case live
    }

    private struct PausedStatus {
        let hasAudio: Bool
        let hasVideo: Bool
    }

    static let defaultID: UInt32 = 0
    /// The RTMPStream metadata.
    public internal(set) var metadata: [String: Any?] = [:]
    /// The RTMPStreamInfo object whose properties contain data.
    public internal(set) var info = RTMPStreamInfo()
    /// The object encoding (AMF). Framework supports AMF0 only.
    public private(set) var objectEncoding: RTMPObjectEncoding = RTMPConnection.defaultObjectEncoding
    /// The boolean value that indicates audio samples allow access or not.
    public internal(set) var audioSampleAccess = true
    /// The boolean value that indicates video samples allow access or not.
    public internal(set) var videoSampleAccess = true
    /// Incoming audio plays on the stream or not.
    public var receiveAudio = true {
        didSet {
            lockQueue.async {
                guard self.readyState == .playing else {
                    return
                }
                self.connection?.socket?.doOutput(chunk: RTMPChunk(message: RTMPCommandMessage(
                    streamId: self.id,
                    transactionId: 0,
                    objectEncoding: self.objectEncoding,
                    commandName: "receiveAudio",
                    commandObject: nil,
                    arguments: [self.receiveAudio]
                )))
            }
        }
    }
    /// Incoming video plays on the stream or not.
    public var receiveVideo = true {
        didSet {
            lockQueue.async {
                guard self.readyState == .playing else {
                    return
                }
                self.connection?.socket?.doOutput(chunk: RTMPChunk(message: RTMPCommandMessage(
                    streamId: self.id,
                    transactionId: 0,
                    objectEncoding: self.objectEncoding,
                    commandName: "receiveVideo",
                    commandObject: nil,
                    arguments: [self.receiveVideo]
                )))
            }
        }
    }
    /// Pauses playback or publish of a video stream or not.
    public var paused = false {
        didSet {
            lockQueue.async {
                switch self.readyState {
                case .publish, .publishing:
                    
                    if self.paused {
                        self.pausedStatus = .init(hasAudio: self.hasAudio, hasVideo: self.hasVideo)
                        self.hasAudio = false
                        self.hasVideo = false
                    } else {
                        self.hasAudio = self.pausedStatus.hasAudio
                        self.hasVideo = self.pausedStatus.hasVideo
                    }
                case .play, .playing:
                    self.connection?.socket?.doOutput(chunk: RTMPChunk(message: RTMPCommandMessage(
                        streamId: self.id,
                        transactionId: 0,
                        objectEncoding: self.objectEncoding,
                        commandName: "pause",
                        commandObject: nil,
                        arguments: [self.paused, floor(self.startedAt.timeIntervalSinceNow * -1000)]
                    )))
                default:
                    break
                }
            }
        }
    }
    var id: UInt32 = RTMPStream.defaultID
    var audioTimestamp: Double = 0.0
    var videoTimestamp: Double = 0.0
    private(set) lazy var muxer = {
        if self.root != nil {
            // this stream is attached to a parent muxer
            // so provide a useless muxer
            return RTMPMuxer(nil)
        }
        return RTMPMuxer(self)
    }()
    private var messages: [RTMPCommandMessage] = []
    private var startedAt = Date()
    private var frameCount: UInt16 = 0
    private var dispatcher: (any EventDispatcherConvertible)!
    private var audioWasSent = false
    private var videoWasSent = false
    private var pausedStatus = PausedStatus(hasAudio: false, hasVideo: false)
    private var howToPublish: RTMPStream.HowToPublish = .live
    private var dataTimeStamps: [String: Date] = .init()
    private weak var connection: RTMPConnection?

    private var muxerIsReadyAudio : Bool = false
    private var muxerIsReadyVideo : Bool = false
    private var dg : DispatchGroup? = nil

    /// Creates a new stream.
    public init(connection: RTMPConnection) {
        self.connection = connection
        super.init()
        dispatcher = EventDispatcher(target: self)
        connection.streams.append(self)
        addEventListener(.rtmpStatus, selector: #selector(on(status:)), observer: self)
        connection.addEventListener(.rtmpStatus, selector: #selector(on(status:)), observer: self)
        if connection.connected {
            connection.createStream(self)
        }
        mixer.muxer = muxer
    }
    
    // This makes a new stream that is connection less
    // its purpose is to receive data from the muxer and forward it to those attached
    public init(completion: @escaping () -> Void) {
        self.connection = nil
        super.init()
        dg = DispatchGroup()
        dg?.enter()
        dg?.enter()
        dg?.notify(queue: .main, execute: completion)
        dispatcher = EventDispatcher(target: self)
        addEventListener(.rtmpStatus, selector: #selector(on(status:)), observer: self)

        mixer.muxer = muxer

        // Testing this.
        lockQueue.async {
            print("LIVESTREAMER FORCE PUBLISHING THIS IS ROOT \(self)")
            self.readyState = .publishing(muxer: self.muxer)
        }
    }
    
    private var root : RTMPStream? = nil
    
    /// Creates a new stream tied to the other stream content -> other stream is responsible for encoding
    /// and this stream will transmit the same video content to another rtmp endpoint.
    public init(connection: RTMPConnection, other: RTMPStream?) {
        self.connection = connection
        if let om = other?.muxer {
            if other?.connection != nil {
                // boom this is misused!
                fatalError("parent stream is not connectionless")
            }
            self.root = other
        }
        super.init()
        dispatcher = EventDispatcher(target: self)
        connection.streams.append(self)
        addEventListener(.rtmpStatus, selector: #selector(on(status:)), observer: self)
        connection.addEventListener(.rtmpStatus, selector: #selector(on(status:)), observer: self)
        if connection.connected == true {
            connection.createStream(self)
        }
        mixer.muxer = muxer
    }
    
    deinit {
        mixer.stopRunning()
        removeEventListener(.rtmpStatus, selector: #selector(on(status:)), observer: self)
        connection?.removeEventListener(.rtmpStatus, selector: #selector(on(status:)), observer: self)
    }

    /// Plays a live stream from RTMPServer.
    public func play(_ arguments: Any?...) {
        // swiftlint:disable:next closure_body_length
        lockQueue.async {
            guard let name: String = arguments.first as? String else {
                switch self.readyState {
                case .play, .playing:
                    self.info.resourceName = nil
                    self.close(withLockQueue: false)
                default:
                    break
                }
                return
            }

            self.info.resourceName = name
            let message = RTMPCommandMessage(
                streamId: self.id,
                transactionId: 0,
                objectEncoding: self.objectEncoding,
                commandName: "play",
                commandObject: nil,
                arguments: arguments
            )

            switch self.readyState {
            case .initialized:
                self.messages.append(message)
            default:
                self.readyState = .play
                self.connection?.socket?.doOutput(chunk: RTMPChunk(message: message))
            }
        }
    }

    /// Seeks the keyframe.
    public func seek(_ offset: Double) {
        lockQueue.async {
            guard self.readyState == .playing else {
                return
            }
            self.connection?.socket?.doOutput(chunk: RTMPChunk(message: RTMPCommandMessage(
                streamId: self.id,
                transactionId: 0,
                objectEncoding: self.objectEncoding,
                commandName: "seek",
                commandObject: nil,
                arguments: [offset]
            )))
        }
    }

    /// Sends streaming audio, vidoe and data message from client.
    public func publish(_ name: String?, type: RTMPStream.HowToPublish = .live) {
        // swiftlint:disable:next closure_body_length
        lockQueue.async {
            guard let name: String = name else {
                switch self.readyState {
                case .publish, .publishing:
                    self.close(withLockQueue: false)
                default:
                    break
                }
                return
            }

            if self.info.resourceName == name && self.readyState == .publishing(muxer: self.muxer) {
                self.howToPublish = type
                return
            }

            self.info.resourceName = name
            self.howToPublish = type

            let message = RTMPCommandMessage(
                streamId: self.id,
                transactionId: 0,
                objectEncoding: self.objectEncoding,
                commandName: "publish",
                commandObject: nil,
                arguments: [name, type.rawValue]
            )

            switch self.readyState {
            case .initialized:
                self.messages.append(message)
            default:
                self.readyState = .publish
                self.connection?.socket?.doOutput(chunk: RTMPChunk(message: message))
            }
        }
    }

    /// Stops playing or publishing and makes available other uses.
    public func close() {
        close(withLockQueue: true)
    }

    /// Sends a message on a published stream to all subscribing clients.
    public func send(handlerName: String, arguments: Any?...) {
        lockQueue.async {
            guard let connection = self.connection, self.readyState == .publishing(muxer: self.muxer) else {
                return
            }
            let dataWasSent = self.dataTimeStamps[handlerName] == nil ? false : true
            let timestmap: UInt32 = dataWasSent ? UInt32((self.dataTimeStamps[handlerName]?.timeIntervalSinceNow ?? 0) * -1000) : UInt32(self.startedAt.timeIntervalSinceNow * -1000)
            let chunk = RTMPChunk(
                type: dataWasSent ? RTMPChunkType.one : RTMPChunkType.zero,
                streamId: RTMPChunk.StreamID.data.rawValue,
                message: RTMPDataMessage(
                    streamId: self.id,
                    objectEncoding: self.objectEncoding,
                    timestamp: timestmap,
                    handlerName: handlerName,
                    arguments: arguments
                ))
            let length = connection.socket?.doOutput(chunk: chunk) ?? 0
            self.dataTimeStamps[handlerName] = .init()
            self.info.byteCount.mutate { $0 += Int64(length) }
        }
    }

    /// Creates flv metadata for a stream.
    open func makeMetaData() -> ASObject {
        var metadata: [String: Any] = [:]
        if videoInputFormat != nil {
            metadata["width"] = videoSettings.videoSize.width
            metadata["height"] = videoSettings.videoSize.height
            #if os(iOS) || os(macOS) || os(tvOS)
            metadata["framerate"] = frameRate
            #endif
            switch videoSettings.format {
            case .h264:
                metadata["videocodecid"] = FLVVideoCodec.avc.rawValue
            case .hevc:
                metadata["videocodecid"] = FLVVideoFourCC.hevc.rawValue
            }
            metadata["videodatarate"] = videoSettings.bitRate / 1000
        }
        if audioInputFormat != nil {
            metadata["audiocodecid"] = FLVAudioCodec.aac.rawValue
            metadata["audiodatarate"] = audioSettings.bitRate / 1000
            if let outputFormat = mixer.audioIO.outputFormat {
                metadata["audiosamplerate"] = outputFormat.sampleRate
            }
        }
        return metadata
    }

    override public func readyStateWillChange(to readyState: IOStream.ReadyState) {
        switch self.readyState {
        case .publishing:
            FCUnpublish()
        default:
            break
        }
        super.readyStateWillChange(to: readyState)
    }

    override public func readyStateDidChange(to readyState: IOStream.ReadyState) {
        guard let connection else {
            super.readyStateDidChange(to: readyState)
            return
        }
        switch readyState {
        case .open:
            currentFPS = 0
            frameCount = 0
            audioSampleAccess = true
            videoSampleAccess = true
            metadata.removeAll()
            info.clear()
            delegate?.streamDidOpen(self)
            for message in messages {
                connection.currentTransactionId += 1
                message.streamId = id
                message.transactionId = connection.currentTransactionId
                switch message.commandName {
                case "play":
                    self.readyState = .play
                case "publish":
                    self.readyState = .publish
                default:
                    break
                }
                connection.socket?.doOutput(chunk: RTMPChunk(message: message))
            }
            messages.removeAll()
        case .play:
            startedAt = .init()
            videoTimestamp = 0
            audioTimestamp = 0
        case .publish:
            bitrateStrategy.setUp()
            startedAt = .init()
            videoWasSent = false
            audioWasSent = false
            dataTimeStamps.removeAll()
            FCPublish()
        case .publishing:
            let metadata = makeMetaData()
            send(handlerName: "@setDataFrame", arguments: "onMetaData", metadata)
            self.metadata = metadata

            // now can send the
            root?.muxer.addStream(stream: self)

        default:
            break
        }
        super.readyStateDidChange(to: readyState)
    }

    func close(withLockQueue: Bool) {
        if withLockQueue {
            lockQueue.sync {
                self.close(withLockQueue: false)
            }
            return
        }
        guard let connection, ReadyState.open.rawValue < readyState.rawValue else {
            readyState = .open
            return
        }
        readyState = .open
        connection.socket?.doOutput(chunk: RTMPChunk(
                                        type: .zero,
                                        streamId: RTMPChunk.StreamID.command.rawValue,
                                        message: RTMPCommandMessage(
                                            streamId: 0,
                                            transactionId: 0,
                                            objectEncoding: self.objectEncoding,
                                            commandName: "closeStream",
                                            commandObject: nil,
                                            arguments: [self.id]
                                        )))
    }

    func on(timer: Timer) {
        currentFPS = frameCount
        frameCount = 0
        info.on(timer: timer)
    }

    func outputAudio(_ buffer: Data, withTimestamp: Double) {
        guard let connection, readyState == .publishing(muxer: muxer) else {
            if !muxerIsReadyAudio  {
                // only once.
                muxerIsReadyAudio = true
                dg?.leave()
            }
            return
        }
        let type: FLVTagType = .audio
        let length = connection.socket?.doOutput(chunk: RTMPChunk(
            type: audioWasSent ? .one : .zero,
            streamId: type.streamId,
            message: RTMPAudioMessage(streamId: id, timestamp: UInt32(audioTimestamp), payload: buffer)
        )) ?? 0
        audioWasSent = true
        info.byteCount.mutate { $0 += Int64(length) }
        audioTimestamp = withTimestamp + (audioTimestamp - floor(audioTimestamp))
    }

    func outputVideo(_ buffer: Data, withTimestamp: Double) {
        guard let connection, readyState == .publishing(muxer: muxer) else {
            if !muxerIsReadyVideo  {
                // only once.
                muxerIsReadyVideo = true
                dg?.leave()
            }

            return
        }
        let type: FLVTagType = .video
        let length = connection.socket?.doOutput(chunk: RTMPChunk(
            type: videoWasSent ? .one : .zero,
            streamId: type.streamId,
            message: RTMPVideoMessage(streamId: id, timestamp: UInt32(videoTimestamp), payload: buffer)
        )) ?? 0
        if !videoWasSent {
            logger.debug("first video frame was sent")
        }
        videoWasSent = true
        info.byteCount.mutate { $0 += Int64(length) }
        videoTimestamp = withTimestamp + (videoTimestamp - floor(videoTimestamp))
        frameCount += 1
    }

    @objc
    private func on(status: Notification) {
        let e = Event.from(status)
        guard let connection, let data = e.data as? ASObject, let code = data["code"] as? String else {
            return
        }
        switch code {
        case RTMPConnection.Code.connectSuccess.rawValue:
            readyState = .initialized
            connection.createStream(self)
        case RTMPStream.Code.playReset.rawValue:
            readyState = .play
        case RTMPStream.Code.playStart.rawValue:
            readyState = .playing
        case RTMPStream.Code.publishStart.rawValue:
            readyState = .publishing(muxer: muxer)
        default:
            break
        }
    }
}

extension RTMPStream {
    func FCPublish() {
        guard let connection, let name = info.resourceName, connection.flashVer.contains("FMLE/") else {
            return
        }
        connection.call("FCPublish", responder: nil, arguments: name)
    }

    func FCUnpublish() {
        guard let connection, let name = info.resourceName, connection.flashVer.contains("FMLE/") else {
            return
        }
        connection.call("FCUnpublish", responder: nil, arguments: name)
    }
}

extension RTMPStream: EventDispatcherConvertible {
    // MARK: IEventDispatcher
    public func addEventListener(_ type: Event.Name, selector: Selector, observer: AnyObject? = nil, useCapture: Bool = false) {
        dispatcher.addEventListener(type, selector: selector, observer: observer, useCapture: useCapture)
    }

    public func removeEventListener(_ type: Event.Name, selector: Selector, observer: AnyObject? = nil, useCapture: Bool = false) {
        dispatcher.removeEventListener(type, selector: selector, observer: observer, useCapture: useCapture)
    }

    public func dispatch(event: Event) {
        dispatcher.dispatch(event: event)
    }

    public func dispatch(_ type: Event.Name, bubbles: Bool, data: Any?) {
        dispatcher.dispatch(type, bubbles: bubbles, data: data)
    }
}
