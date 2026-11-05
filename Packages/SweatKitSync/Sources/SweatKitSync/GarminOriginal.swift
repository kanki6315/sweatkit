import Foundation

/// The original file inside a Garmin download.
///
/// M0 found every download to be a zip holding one file, `<id>_ACTIVITY.fit`,
/// byte for byte the original. The file inside is what is kept and hashed;
/// the zip is only a container.
public enum GarminOriginal {
    /// The original inside `download`.
    ///
    /// - A zip holding one file gives that file.
    /// - A zip holding several gives the one `.fit` file among them, and is
    ///   refused if there is not exactly one.
    /// - Bytes that are already a FIT file, with `.FIT` at bytes 8 to 11, are
    ///   taken as the original, in case Garmin stops zipping.
    public static func extract(from download: Data) throws(ZipError) -> Data {
        if isFIT(download) { return download }
        let archive = try ZipArchive(download)
        let files = archive.files
        if files.count == 1 { return try archive.contents(of: files[0]) }
        let fits = files.filter { $0.name.lowercased().hasSuffix(".fit") }
        guard fits.count == 1 else { throw .noSingleOriginal(files: files.count) }
        return try archive.contents(of: fits[0])
    }

    static func isFIT(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        return bytes.count == 12 && bytes[8...11].elementsEqual(Array(".FIT".utf8))
    }
}
