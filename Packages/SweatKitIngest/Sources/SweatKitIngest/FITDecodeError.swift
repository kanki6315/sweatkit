import Foundation

/// Why a file was rejected. A rejected file produces nothing, so the library
/// is left unchanged.
///
/// The checks run in the order of the cases, and the first that fails names
/// the error.
public enum FITDecodeError: Error, Hashable, Sendable, CaseIterable {
    /// The data is not a FIT file: it is shorter than the smallest FIT header
    /// (`FITActivityDecoder.smallestHeaderSize` bytes), its first byte is not
    /// a FIT header size, or bytes 8 to 11 are not ".FIT". A zip from Garmin
    /// lands here, because unzipping happens before decoding.
    case notFIT
    /// The file is shorter than its own header says: fewer bytes than the
    /// header, the stated data size and the 2-byte checksum add up to.
    case truncated
    /// The file is the stated length but its header or contents fail their
    /// checksum, or the FIT SDK cannot read its messages. Bytes after the
    /// file that are not another FIT file land here too.
    case corrupt
    /// A sound FIT file with no session message, so not a recorded activity.
    /// Courses, settings and workout files land here.
    case noActivity
}

extension FITDecodeError: LocalizedError {
    /// The message shown when an import is rejected.
    public var errorDescription: String? {
        switch self {
        case .notFIT: "This isn't a FIT file."
        case .truncated: "This file is incomplete. It ends before its recording does."
        case .corrupt: "This file is damaged and can't be read."
        case .noActivity: "This FIT file doesn't hold a recorded activity."
        }
    }
}
