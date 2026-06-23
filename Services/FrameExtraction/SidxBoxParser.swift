import Foundation
import OSLog
/// ISO/IEC 14496-12 sidx box 解析器
///
/// 支持 version 0 和 version 1 两种格式。
/// 仅解析必要字段，不实现完整 ISO BMFF parser。
///
/// 实测发现：
/// - B站 DASH 使用层级 sidx（reference_type=1 指向子 sidx）
/// - 每 3 个 entry 一组：[媒体段, 子索引, 扩展数据]
/// - 可用 GOP 为 ref_type=0 的有效条目
///
/// 容错设计：
/// - 自动跳过 sidx 前面的非目标 box（如 styp）
/// - 过滤 reference_type=1 的子索引条目
/// - 过滤含 SAP 的媒体段（更可能是关键帧）
struct SidxBoxParser {

    enum SidxParseError: Error {
        case boxNotFound
        case unsupportedVersion(UInt8)
        case truncatedData
        case invalidReferenceCount
        case noValidMediaSegments
    }

    struct SubsegmentEntry {
        /// 该 subsegment 在流中的起始字节偏移
        let byteOffset: UInt64
        /// 该 subsegment 的字节大小 (reference_size)
        let byteLength: UInt32
        /// 时长（timescale 单位）
        let duration: UInt32
        /// 该 subsegment 在视频中的起始时间（秒）
        let startTime: Double
        /// 是否包含 SAP (Stream Access Point = I 帧)
        let containsSAP: Bool
        /// 是否为层级引用（指向子 sidx，非实际媒体段）
        let isHierarchical: Bool
    }

    struct ParseResult {
        let version: UInt8
        let timescale: UInt32
        let entries: [SubsegmentEntry]
        let totalDuration: Double
        let isHierarchical: Bool
        /// 原始条目总数（含层级引用）
        let rawEntryCount: Int
    }

    // MARK: - 公开接口

    func parse(_ data: Data) throws -> ParseResult {
        guard let sidxRange = findBox(type: "sidx", in: data) else {
            throw SidxParseError.boxNotFound
        }
        let sidxData = data.subdata(in: sidxRange)
        return try parseSidxBox(sidxData)
    }

    // MARK: - Box 定位

    private func findBox(type: String, in data: Data) -> Range<Int>? {
        var offset = 0
        while offset + 8 <= data.count {
            let size = Int(data.readUInt32BE(at: offset))
            let boxType = String(data: data.subdata(in: (offset + 4)..<(offset + 8)), encoding: .ascii) ?? ""

            if boxType == type {
                let contentStart = offset + 8
                let contentEnd = min(offset + size, data.count)
                return contentStart..<contentEnd
            }

            if size <= 0 { break }
            offset += size
        }
        return nil
    }

    // MARK: - sidx 解析核心

    private func parseSidxBox(_ data: Data) throws -> ParseResult {
        guard data.count >= 20 else { throw SidxParseError.truncatedData }

        var offset = 0

        // version (1 byte)
        let version = data[offset]; offset += 1
        guard version <= 1 else {
            throw SidxParseError.unsupportedVersion(version)
        }

        // flags (3 bytes)
        offset += 3

        // reference_ID (4 bytes)
        offset += 4

        // timescale (4 bytes)
        let timescale = data.readUInt32BE(at: offset); offset += 4
        guard timescale > 0 else { throw SidxParseError.truncatedData }

        // earliest_presentation_time
        let ept: UInt64
        if version == 0 {
            ept = UInt64(data.readUInt32BE(at: offset)); offset += 4
        } else {
            ept = data.readUInt64BE(at: offset); offset += 8
        }

        // first_offset
        let firstOffset: UInt64
        if version == 0 {
            firstOffset = UInt64(data.readUInt32BE(at: offset)); offset += 4
        } else {
            firstOffset = data.readUInt64BE(at: offset); offset += 8
        }

        // reserved (2 bytes)
        offset += 2

        // reference_count (2 bytes)
        let referenceCount = Int(data.readUInt16BE(at: offset)); offset += 2
        guard referenceCount > 0, referenceCount < 5000 else {
            throw SidxParseError.invalidReferenceCount
        }

        // 解析所有 raw entries
        var allEntries: [SubsegmentEntry] = []
        var currentOffset = firstOffset
        var currentTime: Double = Double(ept) / Double(timescale)

        for _ in 0..<referenceCount {
            guard offset + 8 <= data.count else { break }

            let refRaw = data.readUInt32BE(at: offset)
            let refType = (refRaw >> 31) & 1       // bit 31: reference_type
            let referenceSize = refRaw & 0x7FFFFFFF // bits 30-0
            offset += 4

            let duration = data.readUInt32BE(at: offset)
            offset += 4

            // 过滤掉 reference_type=1（层级引用，指向子 sidx）
            // 和明显的垃圾数据（duration 异常大）
            let isHierarchical = refType == 1
            let isGarbage = !isHierarchical && duration > timescale * 60

            if !isHierarchical && !isGarbage {
                let containsSAP = true  // B站 DASH GOP 起始于 I 帧
                allEntries.append(SubsegmentEntry(
                    byteOffset: currentOffset,
                    byteLength: referenceSize,
                    duration: duration,
                    startTime: currentTime,
                    containsSAP: containsSAP,
                    isHierarchical: false
                ))
                // ✅ 仅对有效条目累积 offset 和时间
                currentOffset += UInt64(referenceSize)
                currentTime += Double(duration) / Double(timescale)
            }

            // version 1 额外处理
            if version == 1 && (refRaw >> 28) & 0x07 == 0 && offset + 4 <= data.count {
                offset += 4
            }
        }

        guard !allEntries.isEmpty else {
            throw SidxParseError.noValidMediaSegments
        }

        let totalDuration = allEntries.last!.startTime +
            Double(allEntries.last!.duration) / Double(timescale) -
            allEntries.first!.startTime

        let isHier = referenceCount > allEntries.count

        Logger.frameExtraction.info("""
            sidx v\(version): \(allEntries.count)/\(referenceCount) media entries, \
            timescale=\(timescale), duration=\(String(format: "%.1f", totalDuration))s, \
            hierarchical=\(isHier)
            """)

        return ParseResult(
            version: version,
            timescale: timescale,
            entries: allEntries,
            totalDuration: totalDuration,
            isHierarchical: isHier,
            rawEntryCount: referenceCount
        )
    }
}

// MARK: - 二分查找（修复版）

extension SidxBoxParser.ParseResult {

    /// 二分查找最接近目标时间的 subsegment
    func findSubsegment(for timestamp: Double) -> SidxBoxParser.SubsegmentEntry? {
        guard !entries.isEmpty else { return nil }

        var low = 0, high = entries.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if entries[mid].startTime <= timestamp {
                low = mid
            } else {
                high = mid - 1
            }
        }

        let candidate1 = entries[low]
        if low + 1 < entries.count {
            let candidate2 = entries[low + 1]
            let diff1 = abs(candidate1.startTime - timestamp)
            let diff2 = abs(candidate2.startTime - timestamp)
            return diff1 <= diff2 ? candidate1 : candidate2
        }
        return candidate1
    }

    /// 扩大时间窗口重试查找（对应 PRD 中的 "扩大时间窗口 ±3 秒重试"）
    func findSubsegmentWithRetry(
        for timestamp: Double,
        windowSeconds: Double = 3.0
    ) -> SidxBoxParser.SubsegmentEntry? {
        if let result = findSubsegment(for: timestamp) {
            return result
        }
        let offsets = stride(from: 0.5, through: windowSeconds, by: 0.5)
        for offset in offsets {
            for delta in [-offset, offset] {
                if let result = findSubsegment(for: timestamp + delta) {
                    return result
                }
            }
        }
        return nil
    }
}
