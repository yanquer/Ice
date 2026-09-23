//
//  MenuBarImageCacheSupport.swift
//  Ice
//
// 识别菜单栏截图中的全透明图像，保留最后有效快照，避免回藏后图标变成空白。

import CoreGraphics

extension CGImage {
    /// 检查是否包含可见像素；仅分配有上限的 Alpha 缓冲，避免放大宽图标的内存占用。
    var hasVisibleMenuBarPixels: Bool {
        guard
            width > 0, height > 0,
            width <= 8_192, height <= 512,
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ),
            let data = context.data
        else {
            return false
        }
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        let alpha = data.assumingMemoryBound(to: UInt8.self)
        for row in 0..<height {
            let pixels = UnsafeBufferPointer(start: alpha + row * context.bytesPerRow, count: width)
            if pixels.contains(where: { $0 > 0 }) {
                return true
            }
        }
        return false
    }
}

extension Dictionary where Value == CGImage {
    /// 仅合并有效快照，供定时刷新和回藏前截图共用；空截图不会覆盖已有图标。
    mutating func mergeVisibleMenuBarImages(_ updates: [Key: CGImage]) {
        for (key, image) in updates where image.hasVisibleMenuBarPixels {
            self[key] = image
        }
    }
}
