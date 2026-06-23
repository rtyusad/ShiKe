import Foundation
import OSLog
/// mini-mp4 拼装器
///
/// 将 init segment + 单个 GOP subsegment 组装为合法的 mini-mp4 文件。
/// 拼装后的文件可以被 AVAssetImageGenerator 正确解码。
///
/// 智能拼接策略（基于实测）：
/// - GOP 偏移量为 0 的子段：已是自包含 mp4（含 ftyp+moov+sidx+moof+mdat）
///   无需拼接 init，直接保存即可
/// - GOP 偏移量 > 0 的子段：仅含 moof+mdat 片段数据
///   需要前插 init segment 才能构成合法 mp4
/// - 自动检测子段是否以 ftyp box 开头来判断
///
/// 无需 ffmpeg，纯二进制拼接。
struct MP4Assembler {

    /// ftyp box 的 magic bytes（用于检测子段是否为自包含 mp4）
    private static let ftypMagic: [UInt8] = [0x66, 0x74, 0x79, 0x70]  // "ftyp"

    /// 拼装 mini-mp4
    /// - Parameters:
    ///   - initData: init segment (ftyp + moov)，约 1-2KB
    ///   - subsegmentData: GOP subsegment 原始数据 (~200-800KB)
    ///   - index: 帧序号（用于生成唯一文件名）
    /// - Returns: 临时 mp4 文件的本地 URL
    func assemble(initData: Data, subsegmentData: Data, index: Int) throws -> URL {
        guard !subsegmentData.isEmpty else {
            throw AppError.mp4AssemblyFailed
        }

        let mp4Data: Data

        // 检测子段是否自包含（以 ftyp box 开头）
        if isSelfContained(subsegmentData) {
            // 子段已是完整 mp4，直接使用
            mp4Data = subsegmentData
            Logger.frameExtraction.debug("GOP[\(index)] 子段自包含，直接使用")
        } else {
            // 需要前插 init segment
            guard !initData.isEmpty else {
                throw AppError.mp4AssemblyFailed
            }
            var combined = Data()
            combined.append(initData)
            combined.append(subsegmentData)
            mp4Data = combined
            Logger.frameExtraction.debug("GOP[\(index)] 已拼接 init(\(initData.count)B) + subsegment(\(subsegmentData.count)B)")
        }

        // 写入临时文件
        let tempDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TempMP4")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileName = "mini_t\(index)_\(UUID().uuidString.prefix(8)).mp4"
        let fileURL = tempDir.appendingPathComponent(fileName)

        try mp4Data.write(to: fileURL, options: .atomic)

        Logger.frameExtraction.info("mini-mp4 拼装完成: \(fileName) (\(Int(mp4Data.count / 1024))KB)")
        return fileURL
    }

    /// 检测子段数据是否为自包含的 mp4
    /// 判断标准：数据的前 8 字节是否构成一个合法的 ftyp box
    /// ftyp box 格式：[4 bytes: box_size][4 bytes: "ftyp"]
    private func isSelfContained(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }

        // 读取 box size (big-endian)
        let boxSize = data.readUInt32BE(at: 0)

        // 检查 box 类型是否为 "ftyp"
        let boxType = data.subdata(in: 4..<8)
        guard boxType == Data(Self.ftypMagic) else { return false }

        // 验证 box size 合理（至少 8 字节，不超过数据总长度）
        return boxSize >= 8 && Int(boxSize) <= data.count
    }
}
