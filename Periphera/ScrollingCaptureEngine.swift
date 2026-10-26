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

    // Limit max composite height to 30,000px to prevent memory exhaustion
    private let maxCompositeHeight = 30_000

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

            if currentTotalHeight >= maxCompositeHeight {
                return (false, currentTotalHeight, nil)
            }

            guard let shift = detectConsensusVerticalShift(prev: previous, curr: frame) else {
                return (false, currentTotalHeight, nil)
            }

            // If shift is 0 or negligible, user hasn't scrolled; skip frame
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

    /// Stitches all captured slices into a single tall composite CGImage with zero pixel alignment error.
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

            // In Quartz coordinates, (0,0) is bottom-left, y points up.
            // Drawing at `totalHeight - base.height` places the initial base image at the TOP.
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

        ctx.interpolationQuality = .medium
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: thumbW, height: thumbH))

        guard let img = ctx.makeImage() else { return nil }
        return NSImage(cgImage: img, size: NSSize(width: thumbW, height: thumbH))
    }

    // MARK: - Multi-Band Robust Vertical Shift Detection (CleanShot X Algorithm)
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

        // 1. Check if completely static (shift = 0) across middle section
        let zeroCheckY = h / 3
        let zeroCheckH = min(24, h / 8)
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

        // 2. Candidate bands placed in upper 45% of curr image to maximize downward scroll headroom
        let bandTargets = [
            max(15, Int(Double(h) * 0.05)),
            max(30, Int(Double(h) * 0.12)),
            max(45, Int(Double(h) * 0.20)),
            max(60, Int(Double(h) * 0.30)),
            max(75, Int(Double(h) * 0.40))
        ]
        let bandH = min(20, max(8, h / 20))

        var detectedShifts: [Int] = []

        for anchorY in bandTargets {
            guard anchorY + bandH < h else { continue }

            // Check band texture: skip solid white or solid color areas
            var sampleSamples: [Int] = []
            let checkRow = (anchorY + bandH / 2) * bprCurr
            for x in stride(from: 40, to: w - 40, by: stepX * 2) {
                let idx = checkRow + x * bppCurr
                if idx < lenCurr {
                    sampleSamples.append(Int(ptrCurr[idx]))
                }
            }
            if !sampleSamples.isEmpty {
                let mean = sampleSamples.reduce(0, +) / sampleSamples.count
                let diffSum = sampleSamples.reduce(0) { $0 + abs($1 - mean) }
                let variance = diffSum / sampleSamples.count
                if variance < 4 {
                    continue // Skip low-texture band (e.g. whitespace)
                }
            }

            // Maximum shift this band can search without exceeding prev bounds
            let maxShiftForBand = min(h - bandH - anchorY, 950)
            guard maxShiftForBand > 4 else { continue }

            // Phase 1: Coarse search (stride 4)
            var bestCoarseS = -1
            var minCoarseDiff = Int.max

            for s in stride(from: 0, through: maxShiftForBand, by: 4) {
                let prevY = anchorY + s
                guard prevY + bandH < h else { break }

                var diff = 0
                var sampleCount = 0

                for sy in stride(from: 0, to: bandH, by: 2) {
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
                    if avg < minCoarseDiff {
                        minCoarseDiff = avg
                        bestCoarseS = s
                    }
                }
            }

            guard bestCoarseS >= 0, minCoarseDiff < 45 else { continue }

            // Phase 2: Fine search around bestCoarseS (stride 1)
            let fineStart = max(0, bestCoarseS - 4)
            let fineEnd = min(maxShiftForBand, bestCoarseS + 4)
            var bestFineS = bestCoarseS
            var minFineDiff = minCoarseDiff

            for s in fineStart...fineEnd {
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
                    if avg < minFineDiff {
                        minFineDiff = avg
                        bestFineS = s
                    }
                }
            }

            // Accept band if pixel difference is within subpixel tolerance (< 42)
            if minFineDiff < 42 {
                detectedShifts.append(bestFineS)
            }
        }

        guard !detectedShifts.isEmpty else { return nil }

        // 3. Consensus Logic: Discard sticky headers (shift = 0) if body bands agree on positive shift
        let positiveShifts = detectedShifts.filter { $0 > 1 }

        if positiveShifts.isEmpty {
            return 0 // All textured bands detected 0 shift
        }

        // If at least 2 positive bands agree within 2 pixels, return consensus
        if positiveShifts.count >= 2 {
            for i in 0..<positiveShifts.count {
                for j in (i + 1)..<positiveShifts.count {
                    if abs(positiveShifts[i] - positiveShifts[j]) <= 2 {
                        return (positiveShifts[i] + positiveShifts[j]) / 2
                    }
                }
            }
        }

        // If single positive band or slight spread, return median
        let sorted = positiveShifts.sorted()
        return sorted[sorted.count / 2]
    }
}
