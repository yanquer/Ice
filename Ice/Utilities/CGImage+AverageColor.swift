//
//  CGImage+AverageColor.swift
//  Ice
//
// 统一菜单栏背景颜色采样，处理透明截图并支持独立回归验证。

import CoreGraphics

extension CGImage {
    // MARK: Average Color

    /// 计算图像平均颜色；没有有效像素时返回 nil，让界面使用默认背景。
    ///
    /// - Parameters:
    ///   - alphaThreshold: An alpha value below which pixels should be ignored. Pixels with
    ///     an alpha component greater than or equal to this value contribute to the average.
    ///   - makeOpaque: A Boolean value that indicates whether the resulting color should be
    ///     made opaque, regardless of the alpha content of the image.
    func averageColor(alphaThreshold: CGFloat = 0.5, makeOpaque: Bool = false) -> CGColor? {
        /// 以固定上限采样像素，限制颜色分析的内存占用。
        func createPixelData(width: Int, height: Int) -> [UInt32]? {
            var data = [UInt32](repeating: 0, count: width * height)
            guard let context = CGContext(
                data: &data,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageByteOrderInfo.order32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else {
                return nil
            }
            context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
            return data
        }

        /// 从像素中取出指定的颜色分量。
        func computeComponent(shift: UInt32, pixel: UInt32) -> Int {
            return Int((pixel >> shift) & 255)
        }

        // Resize the image for better performance.
        let width = min(width, 10)
        let height = min(height, 10)

        guard let pixelData = createPixelData(width: width, height: height) else {
            return nil
        }

        // Convert the alpha threshold to a valid component for comparison.
        let alphaThreshold = Int((min(max(alphaThreshold, 0), 1) * 255).rounded(.toNearestOrAwayFromZero))

        var includedPixelCount = width * height
        var totals = (red: 0, green: 0, blue: 0, alpha: 0)

        for column in 0..<width {
            for row in 0..<height {
                let pixel = pixelData[(row * width) + column]

                // Check alpha before computing other components.
                let alphaComponent = computeComponent(shift: 24, pixel: pixel)

                guard alphaComponent >= alphaThreshold else {
                    includedPixelCount -= 1 // Don't include this pixel.
                    continue
                }

                // Add the components to the totals.
                totals.red += computeComponent(shift: 16, pixel: pixel)
                totals.green += computeComponent(shift: 8, pixel: pixel)
                totals.blue += computeComponent(shift: 0, pixel: pixel)
                totals.alpha += alphaComponent
            }
        }

        // Liquid Glass 菜单栏截图可能完全透明，避免除以零生成白色或无效背景。
        guard includedPixelCount > 0 else {
            return nil
        }

        // Multiply the included pixel count by 255 to convert the components
        // to their corresponding floating point values.
        let adjustedPixelCount = CGFloat(includedPixelCount * 255)

        return CGColor(
            red: CGFloat(totals.red) / adjustedPixelCount,
            green: CGFloat(totals.green) / adjustedPixelCount,
            blue: CGFloat(totals.blue) / adjustedPixelCount,
            alpha: makeOpaque ? 1 : CGFloat(totals.alpha) / adjustedPixelCount
        )
    }
}
