import Foundation

/// Clean1 (from our CleanCore engine). APFS clone facts for a file. Two clones share their data blocks, so deleting one
/// of them frees nothing; `privateBytes` is what deleting this file would actually free.
struct CloneInfo: Sendable, Equatable {
    /// Bytes owned by this file alone (not shared with clones). Nil if the volume doesn't say.
    var privateBytes: Int64?
    /// APFS clone id. Every file has one; files cloned from each other share it.
    /// On its own it does not mean the file is a clone: check `mayShareBlocks`.
    var cloneID: UInt64?
    /// The file may share some or all of its blocks with another file.
    var mayShareBlocks: Bool

    init(privateBytes: Int64?, cloneID: UInt64?, mayShareBlocks: Bool) {
        self.privateBytes = privateBytes
        self.cloneID = cloneID
        self.mayShareBlocks = mayShareBlocks
    }

    // Values from <sys/attr.h>, spelled out so they don't depend on macro import.
    private static let returnedAttrs: attrgroup_t = 0x8000_0000 // ATTR_CMN_RETURNED_ATTRS
    private static let privateSize: attrgroup_t = 0x0000_0008 // ATTR_CMNEXT_PRIVATESIZE
    private static let cloneIDAttr: attrgroup_t = 0x0000_0100 // ATTR_CMNEXT_CLONEID
    private static let extFlags: attrgroup_t = 0x0000_0200 // ATTR_CMNEXT_EXT_FLAGS
    private static let optExtended: UInt32 = 0x0000_0020 // FSOPT_ATTR_CMN_EXTENDED
    private static let mayShare: UInt64 = 0x01 // EF_MAY_SHARE_BLOCKS
    private static let sharesAll: UInt64 = 0x40 // EF_SHARES_ALL_BLOCKS

    static func read(path: String) -> CloneInfo? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = returnedAttrs
        request.forkattr = privateSize | cloneIDAttr | extFlags
        let options = UInt32(FSOPT_NOFOLLOW) | optExtended

        var buffer = [UInt8](repeating: 0, count: 128)
        let status = buffer.withUnsafeMutableBytes { raw in
            getattrlist(path, &request, raw.baseAddress, raw.count, options)
        }
        guard status == 0 else { return nil }

        return buffer.withUnsafeBytes { raw in
            var offset = MemoryLayout<UInt32>.size // total length
            let returned = raw.loadUnaligned(fromByteOffset: offset, as: attribute_set_t.self)
            offset += MemoryLayout<attribute_set_t>.size
            var info = CloneInfo(privateBytes: nil, cloneID: nil, mayShareBlocks: false)
            // Returned attributes are packed in ascending bit order.
            if returned.forkattr & privateSize != 0 {
                info.privateBytes = raw.loadUnaligned(fromByteOffset: offset, as: Int64.self)
                offset += 8
            }
            if returned.forkattr & cloneIDAttr != 0 {
                let id = raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
                info.cloneID = id == 0 ? nil : id
                offset += 8
            }
            if returned.forkattr & extFlags != 0 {
                let flags = raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
                info.mayShareBlocks = flags & (mayShare | sharesAll) != 0
            }
            return info
        }
    }
}
