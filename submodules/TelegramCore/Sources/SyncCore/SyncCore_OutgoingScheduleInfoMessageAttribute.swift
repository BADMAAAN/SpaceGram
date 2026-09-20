import Foundation
import Postbox
// MARK: NAGRAM — share the same post-upload margin with the composer.
import SpaceGramSettings

public let scheduleWhenOnlineTimestamp: Int32 = 0x7ffffffe

// MARK: NAGRAM — SpaceGram delayed sends are revalidated after media upload.
public let spaceGramDelayedSendMinimumInterval: Int32 = SpaceGramDelayedSendPolicy.minimumDelay

public func spaceGramAdjustedScheduleTime(plannedTime: Int32?, currentServerTime: TimeInterval, minimumDelay: Int32?) -> Int32? {
    guard let plannedTime, let minimumDelay else {
        return plannedTime
    }
    guard currentServerTime.isFinite, currentServerTime >= 0.0 else {
        return plannedTime
    }
    guard currentServerTime <= TimeInterval(Int32.max) else {
        return Int32.max
    }
    let safeDelay = max(spaceGramDelayedSendMinimumInterval, minimumDelay)
    let minimumTime = Int64(currentServerTime.rounded(.down)) + Int64(safeDelay)
    return max(plannedTime, Int32(clamping: minimumTime))
}

public class OutgoingScheduleInfoMessageAttribute: MessageAttribute {
    public let scheduleTime: Int32
    public let repeatPeriod: Int32?
    // MARK: NAGRAM — nil keeps ordinary Telegram scheduled messages unchanged.
    public let spaceGramMinimumDelay: Int32?
    
    public init(scheduleTime: Int32, repeatPeriod: Int32?, spaceGramMinimumDelay: Int32? = nil) {
        self.scheduleTime = scheduleTime
        self.repeatPeriod = repeatPeriod
        self.spaceGramMinimumDelay = spaceGramMinimumDelay
    }
    
    required public init(decoder: PostboxDecoder) {
        self.scheduleTime = decoder.decodeInt32ForKey("t", orElse: 0)
        self.repeatPeriod = decoder.decodeOptionalInt32ForKey("rp")
        self.spaceGramMinimumDelay = decoder.decodeOptionalInt32ForKey("sgmd")
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.scheduleTime, forKey: "t")
        if let repeatPeriod = self.repeatPeriod {
            encoder.encodeInt32(repeatPeriod, forKey: "rp")
        } else {
            encoder.encodeNil(forKey: "rp")
        }
        if let spaceGramMinimumDelay = self.spaceGramMinimumDelay {
            encoder.encodeInt32(spaceGramMinimumDelay, forKey: "sgmd")
        } else {
            encoder.encodeNil(forKey: "sgmd")
        }
    }
    
    public func withUpdatedScheduleTime(_ scheduleTime: Int32) -> OutgoingScheduleInfoMessageAttribute {
        return OutgoingScheduleInfoMessageAttribute(scheduleTime: scheduleTime, repeatPeriod: self.repeatPeriod, spaceGramMinimumDelay: self.spaceGramMinimumDelay)
    }
    
    public func withUpdatedRepeatPeriod(_ repeatPeriod: Int32?) -> OutgoingScheduleInfoMessageAttribute {
        return OutgoingScheduleInfoMessageAttribute(scheduleTime: self.scheduleTime, repeatPeriod: repeatPeriod, spaceGramMinimumDelay: self.spaceGramMinimumDelay)
    }
}

public extension Message {
    var scheduleTime: Int32? {
        for attribute in self.attributes {
            if let attribute = attribute as? OutgoingScheduleInfoMessageAttribute {
                return attribute.scheduleTime
            }
        }
        return nil
    }
    
    var scheduleRepeatPeriod: Int32? {
        for attribute in self.attributes {
            if let attribute = attribute as? OutgoingScheduleInfoMessageAttribute {
                return attribute.repeatPeriod
            } else if let attribute = attribute as? ScheduledRepeatAttribute {
                return attribute.repeatPeriod
            }
        }
        return nil
    }
}
