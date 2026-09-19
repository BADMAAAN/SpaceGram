import Foundation

public enum SpaceGramAIError: Error, Equatable {
    case disabled
    case invalidRequest
    case network(String)
    case httpStatus(Int)
    case decoding
    case emptyResponse
    case streamEndedUnexpectedly
}
