import Foundation

public enum QwengramAIError: Error, Equatable {
    case disabled
    case invalidRequest
    case network(String)
    case httpStatus(Int)
    case decoding
    case emptyResponse
    case streamEndedUnexpectedly
}
