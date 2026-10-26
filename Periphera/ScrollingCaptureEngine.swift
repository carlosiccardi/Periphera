//
//  ScrollingCaptureEngine.swift
//  Periphera
//
//  Created by Carlo Siccardi on 25/10/2026.
//

import Cocoa
import Foundation
import CoreGraphics

nonisolated final class ScrollingCaptureEngine: @unchecked Sendable {
    private var baseImage: CGImage?
    private var slices: [(image: CGImage, shift: Int)] = []
    private var lastCapturedImage: CGImage?
    private var currentTotalHeight: Int = 0
    private let queue = DispatchQueue(label: "com.periphera.scrollingStitcher", qos: .userInitiated)

    nonisolated init() {}

    nonisolated func reset() {
        queue.sync {
            baseImage = nil
            slices.removeAll()
            lastCapturedImage = nil
            currentTotalHeight = 0
        }
    }

    /// Process a new frame captured from the screen.
    /// Returns (didAdd: whether new scrolled content was appended, totalHeight, thumbnailPreview).
    nonisolated func processNewFrame(_ frame: CGImage) -> (didAdd: Bool, totalHeight: Int, thumbnail: NSImage?) {
        queue.sync {
            guard let previous = lastCapturedImage else {
                baseImage = frame
                lastCapturedImage = frame
                currentTotalHeight = frame.height
                let thumb = makeLiveThumbnail(base: frame, currentTotalHeight: frame.height)
                return (true, currentTotalHeight, thumb)
            }

            guard previous.width == frame.width, previous.height == frame.height else {
                return (false, currentTotalHeight, nil)
            }

            guard let shift = detectConsensusVerticalShift(prev: previous, curr: frame) else {
                return (false, currentTotalHeight, nil)
            }

            // If shift is 0 or negligible, user hasn't scrolled yet; skip frame
            if shift <= 1 {
                return (false, currentTotalHeight, nil)
            }

            // Crop the bottom `shift` pixels of `frame` (the brand new content that scrolled into view)
            let cropY = frame.height - shift
            guard cropY >= 0,
                  let croppedSlice = frame.cropping(to: CGRect(x: 0, y: cropY, width: frame.width, height: shift)) else {
                return (false, currentTotalHeight, nil)
            }

            slices.append((image: croppedSlice, shift: shift))
            lastCapturedImage = frame
            currentTotalHeight += shift

            let thumb = makeLiveThumbnail(base: baseImage ?? frame, currentTotalHeight: currentTotalHeight)
            return (true, currentTotalHeight, thumb)
        }
    }

    nonisolated var capturedFrameCount: Int {
        queue.sync {
            (baseImage != nil ? 1 : 0) + slices.count
        }
    }

    nonisolated var currentHeight: Int {
        queue.sync { currentTotalHeight }
    }

    /// Stitches all captured slices into a single tall composite CGImage with 0 pixel alignment error.
    nonisolated func finalizeStitchedImage() -> CGImage? {
        queue.sync {
            guard let base = baseImage else { return nil }
            if slices.isEmpty { return base }

            let width = base.width
            let totalHeight = currentTotalHeight
            guard width > 0, totalHeight > 0 else { return base }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(
                data: nil,
                width: width,
                height: totalHeight,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return base
            }

            // In macOS CoreGraphics CGContext without CTM flipping:
            // (0,0) is bottom-left, y points up.
            // Drawing at `totalHeight - base.height` places the initial base image at the TOP of the composite.
            var currentTopY = totalHeight - base.height
            context.draw(base, in: CGRect(x: 0, y: currentTopY, width: width, height: base.height))

            // Draw each slice below it in continuous vertical succession
            for slice in slices {
                currentTopY -= slice.shift
                context.draw(slice.image, in: CGRect(x: 0, y: currentTopY, width: width, height: slice.shift))
            }

            return context.makeImage()
        }
    }

    // MARK: - Live Preview Thumbnail Generator
    private func makeLiveThumbnail(base: CGImage, currentTotalHeight: Int) -> NSImage? {
        let thumbW = 70
        let aspect = CGFloat(currentTotalHeight) / max(CGFloat(base.width), 1.0)
        let thumbH = max(40, min(140, Int(CGFloat(thumbW) * aspect)))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: thumbW,
            height: thumbH,
            bitsPerComponent: 8,
            bytesPerRow: thumbW * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // Draw downscaled base
        ctx.interpolationQuality = .medium
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: thumbW, height: thumbH))

        guard let img = ctx.makeImage() else { return nil }
        return NSImage(cgImage: img, size: NSSize(width: thumbW, height: thumbH))
    }

    // MARK: - Multi-Band Robust Vertical Shift Detection (CleanShot X Algorithm)
    /// Detects vertical scroll displacement by evaluating multiple horizontal bands
    /// to handle sticky headers/navbars, fixed sidebars, and smooth trackpad inertia.
    private func detectConsensusVerticalShift(prev: CGImage, curr: CGImage) -> Int? {
        let w = prev.width
        let h = prev.height
        guard w >= 40, h >= 60 else { return nil }

        guard let dataPrev = prev.dataProvider?.data, let ptrPrev = CFDataGetBytePtr(dataPrev),
              let dataCurr = curr.dataProvider?.data, let ptrCurr = CFDataGetBytePtr(dataCurr) else {
            return nil
        }

        let lenPrev = CFDataGetLength(dataPrev)
        let lenCurr = CFDataGetLength(dataCurr)
        guard lenPrev > 0, lenCurr > 0 else { return nil }

        let bprPrev = prev.bytesPerRow
        let bprCurr = curr.bytesPerRow
        let bppPrev = max(3, prev.bitsPerPixel / 8)
        let bppCurr = max(3, curr.bitsPerPixel / 8)

        // 1. Check if identical (shift = 0) across middle section
        let zeroCheckY = h / 3
        let zeroCheckH = min(30, h / 5)
        var zeroDiff = 0
        var zeroCount = 0
        let stepX = 6

        for y in zeroCheckY..<(zeroCheckY + zeroCheckH) {
            let rowP = y * bprPrev
            let rowC = y * bprCurr
            for x in stride(from: 40, to: w - 40, by: stepX) {
                let idxP = rowP + x * bppPrev
                let idxC = rowC + x * bppCurr
                guard idxP + 2 < lenPrev, idxC + 2 < lenCurr else { continue }
                zeroDiff += abs(Int(ptrPrev[idxP]) - Int(ptrCurr[idxC]))
                zeroCount += 1
            }
        }

        if zeroCount > 0 && (zeroDiff / zeroCount) < 3 {
            return 0 // Screen content did not move
        }

        // 2. Sample 3 candidate bands at 25%, 45%, and 65% of frame height
        let bandTargets = [
            Int(Double(h) * 0.25),
            Int(Double(h) * 0.45),
            Int(Double(h) * 0.65)
        ]
        let bandH = min(24, h / 12)
        let maxShift = min(h / 2, 380)
        guard maxShift > 4 else { return nil }

        var detectedShifts: [Int] = []

        for anchorY in bandTargets {
            guard anchorY + bandH < h else { continue }

            var bestS = -1
            var minDiff = Int.max

            // Check shift from 0 through maxShift
            for s in stride(from: 0, through: maxShift, by: 2) {
                let prevY = anchorY + s
                guard prevY + bandH < h else { break }

                var diff = 0
                var sampleCount = 0

                for sy in 0..<bandH {
                    let rowC = (anchorY + sy) * bprCurr
                    let rowP = (prevY + sy) * bprPrev

                    for x in stride(from: 40, to: w - 40, by: stepX) {
                        let idxC = rowC + x * bppCurr
                        let idxP = rowP + x * bppPrev
                        guard idxC + 2 < lenCurr, idxP + 2 < lenPrev else { continue }

                        diff += abs(Int(ptrCurr[idxC]) - Int(ptrPrev[idxP]))
                        sampleCount += 1
                    }
                }

                if sampleCount > 0 {
                    let avg = diff / sampleCount
                    if avg < minDiff {
                        minDiff = avg
                        bestS = s
                    }
                }
            }

            // Only accept band if matching difference is low (< 18 per pixel)
            if minDiff < 18, bestS >= 0 {
                detectedShifts.append(bestS)
            }
        }

        guard !detectedShifts.isEmpty else { return nil }

        // 3. Consensus Logic: Discard sticky header (shift = 0) if body bands agree on a positive shift
        let positiveShifts = detectedShifts.filter { $0 > 1 }

        if positiveShifts.isEmpty {
            return 0
        }

        if positiveShifts.count >= 2 {
            // Find pair that agrees within 2 pixels
            for i in 0..<positiveShifts.count {
                for j in (i + 1)..<positiveShifts.count {
                    if abs(positiveShifts[i] - positiveShifts[j]) <= 2 {
                        return (positiveShifts[i] + positiveShifts[j]) / 2
                    }
                }
            }
        }

        // If only 1 positive band or slight variance, take median of positive shifts
        let sorted = positiveShifts.sorted()
        return sorted[sorted.count / 2]
    }
}
