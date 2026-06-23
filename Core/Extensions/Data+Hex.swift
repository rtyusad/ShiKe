import Foundation

// MARK: - Data 二进制调试扩展

extension Data {

    /// 格式化为 hex 字符串（用于调试 sidx box 二进制内容）
    var hexString: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    /// 前 n 字节的 hex 预览
    func hexPreview(length: Int = 64) -> String {
        prefix(length).hexString + (count > length ? " ..." : "")
    }
}

// MARK: - UInt8 字节序读取

extension Data {
    /// 按指定偏移读取 big-endian UInt16
    func readUInt16BE(at offset: Int) -> UInt16 {
        var value: UInt16 = 0
        (self as NSData).getBytes(&value, range: NSRange(location: offset, length: 2))
        return CFSwapInt16BigToHost(value)
    }

    /// 按指定偏移读取 big-endian UInt32
    func readUInt32BE(at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        (self as NSData).getBytes(&value, range: NSRange(location: offset, length: 4))
        return CFSwapInt32BigToHost(value)
    }

    /// 按指定偏移读取 big-endian UInt64
    func readUInt64BE(at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        (self as NSData).getBytes(&value, range: NSRange(location: offset, length: 8))
        return CFSwapInt64BigToHost(value)
    }
}
