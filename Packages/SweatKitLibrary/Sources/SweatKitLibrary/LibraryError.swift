import Foundation
import SweatKitIngest
import SweatKitModel
import SweatKitStore

/// What went wrong in the library, in terms a screen can show.
public enum LibraryError: Error, Hashable, Sendable {
    /// The file is not a FIT activity that can be read: it is not FIT, it is
    /// truncated or damaged, or it holds no activity. Nothing was stored. The
    /// value is Ingest's own error, with its own message.
    case rejected(FITDecodeError)
    /// The file is a sound FIT activity that states no start and no end and
    /// holds no samples to take them from, so it cannot be placed in the
    /// feed. Nothing was stored.
    case noTimeSpan
    /// A file handed over by URL could not be read. The value is the
    /// system's description of why.
    case unreadableFile(String)
    /// An imported file was given an identity that is not the hash of its
    /// bytes. An imported file has no other identity.
    case identityMismatch(SourceIdentity)
    /// No activity has this ID.
    case unknownActivity(SourceIdentity)
    /// The preserved original of an activity is no longer on the device, so
    /// nothing can be rebuilt from it until it is fetched again.
    case originalMissing(ContentHash)
    /// The preserved original of an activity no longer matches its hash.
    case originalDamaged(ContentHash)
    /// The work was cancelled before this item was reached.
    case cancelled
    /// The store could not read or write. The value describes the failure.
    case storage(String)
}

extension LibraryError {
    /// Any error the pipeline can meet, as a `LibraryError`.
    init(_ error: any Error) {
        switch error {
        case let error as LibraryError:
            self = error
        case let error as FITDecodeError:
            self = .rejected(error)
        case let error as StoreError:
            switch error {
            case .fileIdentityMismatch(let identity): self = .identityMismatch(identity)
            case .originalCorrupted(let hash): self = .originalDamaged(hash)
            default: self = .storage(String(describing: error))
            }
        case is CancellationError:
            self = .cancelled
        default:
            self = .storage(error.localizedDescription)
        }
    }
}

extension LibraryError: LocalizedError {
    /// The message shown for the error.
    public var errorDescription: String? {
        switch self {
        case .rejected(let reason):
            reason.errorDescription
        case .noTimeSpan:
            "This file doesn't say when its activity started and ended."
        case .unreadableFile:
            "This file couldn't be opened."
        case .identityMismatch:
            "This file was imported under a name that doesn't match its contents."
        case .unknownActivity:
            "This activity is no longer in the library."
        case .originalMissing:
            "The original file for this activity isn't on this device."
        case .originalDamaged:
            "The original file for this activity is damaged."
        case .cancelled:
            "Cancelled before this was reached."
        case .storage:
            "The library couldn't be read or written."
        }
    }
}
