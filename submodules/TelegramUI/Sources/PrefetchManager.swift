import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import AccountContext
import PhotoResources
import StickerResources
import Emoji
import UniversalMediaPlayer
import ChatMessageInteractiveMediaNode
import ChatMessageAnimatedStickerItemNode
// MARK: NAGRAM — account-level SpaceGram photo/round-video capture.
import SpaceGramHistoryStorage
import SpaceGramSettings
import SpaceGramSettingsSignal

private final class SpaceGramArchiveFetchContext {
    let disposable = MetaDisposable()
    var attempts = 0

    init() {
    }
}

private struct SpaceGramArchiveFetchCandidate {
    let message: Message
    let media: Media
    let resource: MediaResource
    let kind: String
    let diagnosticId: String
    let peerType: MediaAutoDownloadPeerType
}

// Uses Telegram's FetchManager and auto-download policy. The persistent inbox is
// bounded, and this additional pass is further limited to recent/new snapshots.
private func spaceGramManagedArchiveFetches(account: Account, fetchManager: FetchManager,
        settings: Signal<MediaAutoDownloadSettings, NoError>) -> Disposable {
    let queue = fetchManager.queue
    var contexts: [String: SpaceGramArchiveFetchContext] = [:]
    var reportedDenied = Set<String>()
    let networkType = account.networkType
    |> map { value -> MediaAutoDownloadNetworkType in
        switch value {
        case .none, .cellular: return .cellular
        case .wifi: return .wifi
        }
    }
    |> distinctUntilChanged
    let viewKey = PostboxViewKey.orderedItemList(id: SpaceGramMessageSnapshotStore.collectionId)
    let candidates = combineLatest(account.postbox.combinedView(keys: [viewKey]), spaceGramSettingsChangesSignal())
    |> mapToSignal { _ -> Signal<[SpaceGramArchiveFetchCandidate], NoError> in
        return account.postbox.transaction { transaction in
            guard SpaceGramSettings.shared.captureMedia else { return [] }
            let cutoff = Int64(Date().timeIntervalSince1970) - 24 * 60 * 60
            return SpaceGramMessageSnapshotStore.list(transaction: transaction).prefix(64).compactMap { received in
                guard received.receivedTimestamp.map({ $0 >= cutoff }) == true,
                      let diagnosticId = received.diagnosticId else { return nil }
                let id = MessageId(peerId: PeerId(received.key.peerId), namespace: received.key.namespace, id: received.key.id)
                guard let message = transaction.getMessage(id), message.flags.contains(.Incoming) else { return nil }
                let peerType: MediaAutoDownloadPeerType
                if transaction.isPeerContact(peerId: id.peerId) {
                    peerType = .contact
                } else if let channel = message.peers[id.peerId] as? TelegramChannel {
                    if case .group = channel.info {
                        peerType = .group
                    } else {
                        peerType = .channel
                    }
                } else if message.peers[id.peerId] is TelegramGroup {
                    peerType = .group
                } else {
                    peerType = .otherPrivate
                }
                for media in message.effectiveMedia {
                    if let image = media as? TelegramMediaImage,
                       let representation = image.representations.max(by: {
                           Int64($0.dimensions.width) * Int64($0.dimensions.height) < Int64($1.dimensions.width) * Int64($1.dimensions.height)
                       }) {
                        return SpaceGramArchiveFetchCandidate(message: message, media: image, resource: representation.resource, kind: "photo", diagnosticId: diagnosticId, peerType: peerType)
                    } else if let file = media as? TelegramMediaFile, file.isInstantVideo {
                        return SpaceGramArchiveFetchCandidate(message: message, media: file, resource: file.resource, kind: "videoMessage", diagnosticId: diagnosticId, peerType: peerType)
                    }
                }
                return nil
            }
        }
    }
    return (combineLatest(candidates, settings, networkType)
    |> deliverOn(queue)).start(next: { candidates, settings, networkType in
        guard SpaceGramSettings.shared.captureMedia else {
            for context in contexts.values { context.disposable.dispose() }
            contexts.removeAll()
            return
        }
        var validIds = Set<String>()
        for candidate in candidates {
            let resourceId = candidate.resource.id.stringRepresentation
            guard shouldDownloadMediaAutomatically(settings: settings, peerType: candidate.peerType, networkType: networkType,
                    authorPeerId: candidate.message.author?.id, contactsPeerIds: [], media: candidate.media) else {
                if reportedDenied.insert(candidate.diagnosticId).inserted {
                    NSLog("SpaceGramMediaLifecycle id=%@ stage=fetchDenied type=%@ bytes=0 reason=autoDownloadPolicy", candidate.diagnosticId, candidate.kind)
                }
                continue
            }
            validIds.insert(resourceId)
            if contexts[resourceId] != nil { continue }
            let context = SpaceGramArchiveFetchContext()
            contexts[resourceId] = context
            NSLog("SpaceGramMediaLifecycle id=%@ stage=messageReceived type=%@ bytes=0 reason=eligible", candidate.diagnosticId, candidate.kind)
            func beginFetch() {
                guard contexts[resourceId] === context else { return }
                context.attempts += 1
                NSLog("SpaceGramMediaLifecycle id=%@ stage=fetchRequested type=%@ bytes=0 reason=nativeFetchManager", candidate.diagnosticId, candidate.kind)
                let priority: FetchManagerPriority = .backgroundPrefetch(
                    locationOrder: HistoryPreloadIndex(index: nil, threadId: nil, hasUnread: true, isMuted: false, isPriority: true),
                    localOrder: candidate.message.index)
                let signal: Signal<Void, NoError>
                if let image = candidate.media as? TelegramMediaImage {
                    signal = messageMediaImageInteractiveFetched(fetchManager: fetchManager, messageId: candidate.message.id,
                        messageReference: MessageReference(candidate.message), image: image, resource: candidate.resource,
                        userInitiated: false, priority: priority, storeToDownloadsPeerId: nil)
                } else if let file = candidate.media as? TelegramMediaFile {
                    signal = messageMediaFileInteractiveFetched(fetchManager: fetchManager, messageId: candidate.message.id,
                        messageReference: MessageReference(candidate.message), file: file, userInitiated: false, priority: priority)
                } else {
                    contexts.removeValue(forKey: resourceId)
                    return
                }
                context.disposable.set(signal.start(completed: {
                    queue.async {
                        guard contexts[resourceId] === context else { return }
                        if let path = account.postbox.mediaBox.completedResourcePath(candidate.resource),
                           let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                           let bytes = attributes[.size] as? NSNumber, bytes.int64Value > 0 {
                            NSLog("SpaceGramMediaLifecycle id=%@ stage=fetchCompleted type=%@ bytes=%lld reason=nativeFetchManager", candidate.diagnosticId, candidate.kind, bytes.int64Value)
                        } else if context.attempts < 2 {
                            queue.after(2.0, beginFetch)
                        } else {
                            NSLog("SpaceGramMediaLifecycle id=%@ stage=fetchFailed type=%@ bytes=0 reason=retryLimit", candidate.diagnosticId, candidate.kind)
                            contexts.removeValue(forKey: resourceId)
                        }
                    }
                }))
            }
            beginFetch()
        }
        for resourceId in Array(contexts.keys) where !validIds.contains(resourceId) {
            contexts.removeValue(forKey: resourceId)?.disposable.dispose()
        }
    })
}

private final class PrefetchMediaContext {
    let fetchDisposable = MetaDisposable()
    
    init() {
    }
}

public enum PrefetchMediaItem {
    case chatHistory(ChatHistoryPreloadMediaItem)
    case animatedEmojiSticker(TelegramMediaFile)
}

private final class PrefetchManagerInnerImpl {
    private let queue: Queue
    private let account: Account
    private let engine: TelegramEngine
    private let fetchManager: FetchManager
    
    private var listDisposable: Disposable?
    private let spaceGramArchiveFetchDisposable = MetaDisposable()
    
    private var contexts: [EngineMedia.Id: PrefetchMediaContext] = [:]

    private let preloadGreetingStickerDisposable = MetaDisposable()
    fileprivate let preloadedGreetingStickerPromise = Promise<TelegramMediaFile?>(nil)

    init(queue: Queue, sharedContext: SharedAccountContext, account: Account, engine: TelegramEngine, fetchManager: FetchManager) {
        self.queue = queue
        self.account = account
        self.engine = engine
        self.fetchManager = fetchManager
        
        let networkType = account.networkType
        |> map { networkType -> MediaAutoDownloadNetworkType in
            switch networkType {
                case .none, .cellular:
                    return .cellular
                case .wifi:
                    return .wifi
            }
        }
        |> distinctUntilChanged
        
        let appConfiguration = engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: PreferencesKeys.appConfiguration))
        |> take(1)
        |> map { view in
            return view?.get(AppConfiguration.self) ?? .defaultValue
        }
        
        let orderedPreloadMedia = combineLatest(account.viewTracker.orderedPreloadMedia, TelegramEngine(account: account).stickers.loadedStickerPack(reference: .animatedEmoji, forceActualized: false), appConfiguration)
        |> map { orderedPreloadMedia, stickerPack, appConfiguration -> [PrefetchMediaItem] in
            let emojiSounds = AnimatedEmojiSoundsConfiguration.with(appConfiguration: appConfiguration, account: account)
            let chatHistoryMediaItems = orderedPreloadMedia.map { PrefetchMediaItem.chatHistory($0) }
            var stickerItems: [PrefetchMediaItem] = []
            switch stickerPack {
                case let .result(_, items, _):
                    var animatedEmojiStickers: [String: StickerPackItem] = [:]
                    for item in items {
                        if let emoji = item.getStringRepresentationsOfIndexKeys().first {
                            animatedEmojiStickers[emoji.basicEmoji.0] = item
                        }
                    }
                    
                    let popularEmoji = ["\u{2764}", "👍", "👎", "😳", "😒", "🥳", "😡", "😮", "😂", "😘", "😍", "🙄", "😎"]
                    for emoji in popularEmoji {
                        if let sticker = animatedEmojiStickers[emoji] {
                            let stickerFile = sticker.file._parse()
                            if let _ = account.postbox.mediaBox.completedResourcePath(stickerFile.resource) {
                            } else {
                                stickerItems.append(.animatedEmojiSticker(stickerFile))
                            }
                        }
                    }
                default:
                    break
            }
            
            var prefetchItems: [PrefetchMediaItem] = []
            prefetchItems.append(contentsOf: chatHistoryMediaItems)
            prefetchItems.append(contentsOf: stickerItems)
            prefetchItems.append(contentsOf: emojiSounds.sounds.values.map { .animatedEmojiSticker($0) })
            
            return prefetchItems
        }
        
        self.listDisposable = (combineLatest(orderedPreloadMedia, sharedContext.automaticMediaDownloadSettings, networkType)
        |> deliverOn(self.queue)).startStrict(next: { [weak self] orderedPreloadMedia, automaticDownloadSettings, networkType in
            self?.updateOrderedPreloadMedia(orderedPreloadMedia, automaticDownloadSettings: automaticDownloadSettings, networkType: networkType)
        })
        // MARK: NAGRAM — fetch eligible received media even if its chat is not opened.
        self.spaceGramArchiveFetchDisposable.set(spaceGramManagedArchiveFetches(account: account, fetchManager: fetchManager,
            settings: sharedContext.automaticMediaDownloadSettings))
    }
    
    deinit {
        assert(self.queue.isCurrent())
        self.listDisposable?.dispose()
        self.spaceGramArchiveFetchDisposable.dispose()
    }
    
    private func updateOrderedPreloadMedia(_ items: [PrefetchMediaItem], automaticDownloadSettings: MediaAutoDownloadSettings, networkType: MediaAutoDownloadNetworkType) {
        #if DEBUG
        if "".isEmpty {
            return
        }
        #endif
        var validIds = Set<EngineMedia.Id>()
        var order: Int32 = 0
        for mediaItem in items {
            switch mediaItem {
                case let .chatHistory(mediaItem):
                    guard let id = mediaItem.media.media.id else {
                        continue
                    }
                    if validIds.contains(id) {
                        continue
                    }
                    
                    var automaticDownload: InteractiveMediaNodeAutodownloadMode = .none
                    let peerType: MediaAutoDownloadPeerType
                    if mediaItem.media.authorIsContact {
                        peerType = .contact
                    } else if let channel = mediaItem.media.peer as? TelegramChannel {
                        if case .group = channel.info {
                            peerType = .group
                        } else {
                            peerType = .channel
                        }
                    } else if mediaItem.media.peer is TelegramGroup {
                        peerType = .group
                    } else {
                        peerType = .otherPrivate
                    }
                    var mediaResource: EngineMediaResource?
                    
                    if let telegramImage = mediaItem.media.media as? TelegramMediaImage {
                        mediaResource = (largestRepresentationForPhoto(telegramImage)?.resource).flatMap(EngineMediaResource.init)
                        if shouldDownloadMediaAutomatically(settings: automaticDownloadSettings, peerType: peerType, networkType: networkType, authorPeerId: nil, contactsPeerIds: [], media: telegramImage) {
                            automaticDownload = .full
                        }
                    } else if let telegramFile = mediaItem.media.media as? TelegramMediaFile {
                        mediaResource = EngineMediaResource(telegramFile.resource)
                        if shouldDownloadMediaAutomatically(settings: automaticDownloadSettings, peerType: peerType, networkType: networkType, authorPeerId: nil, contactsPeerIds: [], media: telegramFile) {
                            automaticDownload = .full
                        } else if shouldPredownloadMedia(settings: automaticDownloadSettings, peerType: peerType, networkType: networkType, media: telegramFile) {
                            automaticDownload = .prefetch
                        }
                    }
                    
                    if case .none = automaticDownload {
                        continue
                    }
                    guard let resource = mediaResource else {
                        continue
                    }
                    
                    validIds.insert(id)
                    let context: PrefetchMediaContext
                    if let current = self.contexts[id] {
                        context = current
                    } else {
                        context = PrefetchMediaContext()
                        self.contexts[id] = context
                        
                        let media = mediaItem.media.media
                        
                        let priority: FetchManagerPriority = .backgroundPrefetch(locationOrder: mediaItem.preloadIndex, localOrder: mediaItem.media.index)
                        
                        if case .full = automaticDownload {
                            if let image = media as? TelegramMediaImage {
                                context.fetchDisposable.set(messageMediaImageInteractiveFetched(fetchManager: self.fetchManager, messageId: mediaItem.media.index.id, messageReference: MessageReference(peer: mediaItem.media.peer, author: nil, id: mediaItem.media.index.id, timestamp: mediaItem.media.index.timestamp, incoming: true, secret: false, threadId: nil), image: image, resource: resource._asResource(), userInitiated: false, priority: priority, storeToDownloadsPeerId: nil).startStrict())
                            } else if let _ = media as? TelegramMediaWebFile {
                                //strongSelf.fetchDisposable.set(chatMessageWebFileInteractiveFetched(account: context.account, image: image).startStrict())
                            } else if let file = media as? TelegramMediaFile {
                                let fetchSignal = messageMediaFileInteractiveFetched(fetchManager: self.fetchManager, messageId: mediaItem.media.index.id, messageReference: MessageReference(peer: mediaItem.media.peer, author: nil, id: mediaItem.media.index.id, timestamp: mediaItem.media.index.timestamp, incoming: true, secret: false, threadId: nil), file: file, userInitiated: false, priority: priority)
                                context.fetchDisposable.set(fetchSignal.startStrict())
                            }
                        } else if case .prefetch = automaticDownload, mediaItem.media.peer.id.namespace != Namespaces.Peer.SecretChat {
                            if let file = media as? TelegramMediaFile, let _ = file.size {
                                context.fetchDisposable.set(preloadVideoResource(postbox: self.account.postbox, userLocation: .peer(mediaItem.media.index.id.peerId), userContentType: MediaResourceUserContentType(file: file), resourceReference: FileMediaReference.message(message: MessageReference(peer: mediaItem.media.peer, author: nil, id: mediaItem.media.index.id, timestamp: mediaItem.media.index.timestamp, incoming: true, secret: false, threadId: nil), media: file).resourceReference(file.resource), duration: 4.0).startStrict())
                            }
                        }
                    }
                case let .animatedEmojiSticker(media):
                    guard let id = media.id else {
                        continue
                    }
                    if validIds.contains(id) {
                        continue
                    }

                    var automaticDownload: InteractiveMediaNodeAutodownloadMode = .none
                    let peerType = MediaAutoDownloadPeerType.contact
                    
                    if shouldDownloadMediaAutomatically(settings: automaticDownloadSettings, peerType: peerType, networkType: networkType, authorPeerId: nil, contactsPeerIds: [], media: media) {
                        automaticDownload = .full
                    }
                
                    if case .none = automaticDownload {
                        continue
                    }
   
                    validIds.insert(id)
                    let context: PrefetchMediaContext
                    if let current = self.contexts[id] {
                        context = current
                    } else {
                        context = PrefetchMediaContext()
                        self.contexts[id] = context
                        
                        let priority: FetchManagerPriority = .backgroundPrefetch(locationOrder: HistoryPreloadIndex(index: nil, threadId: nil, hasUnread: false, isMuted: false, isPriority: true), localOrder: EngineMessage.Index(id: EngineMessage.Id(peerId: EnginePeer.Id(0), namespace: 0, id: order), timestamp: 0))
                        
                        if case .full = automaticDownload {
                            let fetchSignal = freeMediaFileInteractiveFetched(fetchManager: self.fetchManager, fileReference: .standalone(media: media), priority: priority)
                            context.fetchDisposable.set(fetchSignal.startStrict())
                        }
                        
                        order += 1
                }
            }
        }
        var removeIds: [EngineMedia.Id] = []
        for key in self.contexts.keys {
            if !validIds.contains(key) {
                removeIds.append(key)
            }
        }
        for id in removeIds {
            if let context = self.contexts.removeValue(forKey: id) {
                context.fetchDisposable.dispose()
            }
        }
    }
    
    fileprivate func prepareNextGreetingSticker() {
        let account = self.account
        let engine = self.engine
        self.preloadedGreetingStickerPromise.set(.single(nil)
        |> then(engine.stickers.randomGreetingSticker()
        |> map { item in
            return item?.file
        }))
        
        self.preloadGreetingStickerDisposable.set((self.preloadedGreetingStickerPromise.get()
        |> mapToSignal { sticker -> Signal<Void, NoError> in
            if let sticker = sticker {
                return freeMediaFileInteractiveFetched(account: account, userLocation: .other, fileReference: .standalone(media: sticker))
                |> map { _ -> Void in
                    return Void()
                }
                |> `catch` { _ -> Signal<Void, NoError> in
                    return .complete()
                }
            } else {
                return .complete()
            }
        }).startStrict())
    }
}

final class PrefetchManagerImpl: PrefetchManager {
    private let queue: Queue
    
    private let impl: QueueLocalObject<PrefetchManagerInnerImpl>
    private let uuid = Atomic<UUID>(value: UUID())
    
    init(sharedContext: SharedAccountContext, account: Account, engine: TelegramEngine, fetchManager: FetchManager) {
        let queue = Queue.mainQueue()
        self.queue = queue
        self.impl = QueueLocalObject(queue: queue, generate: {
            return PrefetchManagerInnerImpl(queue: queue, sharedContext: sharedContext, account: account, engine: engine, fetchManager: fetchManager)
        })
    }
    
    var preloadedGreetingSticker: ChatGreetingData {
        let signal: Signal<TelegramMediaFile?, NoError> = Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set((impl.preloadedGreetingStickerPromise.get() |> take(1)).start(next: { file in
                    subscriber.putNext(file)
                    subscriber.putCompletion()
                }))
            }
            return disposable
        }
        return ChatGreetingData(uuid: uuid.with { $0 }, sticker: signal)
    }
    
    func prepareNextGreetingSticker() {
        let _ = uuid.swap(UUID())
        self.impl.with { impl in
            impl.prepareNextGreetingSticker()
        }
    }
}
