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
    private let queue = DispatchQueue(label: "com.periphera.scrollingStitcher", qos: .userInitiated)

    nonisolated init() {}

    nonisolated func reset() {
        queue.sync {
            baseImage = nil
            slices.removeAll()
            lastCapturedImage = nil
        }
    }

    /// Appends a newly captured frame, detecting scroll shift and buffering slices.
    /// Returns true if a new scroll slice was successfully matched and added.
    @discardableResult
    nonisolated func processNewFrame(_ frame: CGImage) -> Bool {
        queue.sync {
            guard let previous = lastCapturedImage else {
                baseImage = frame
                lastCapturedImage = frame
                return true
            }

            guard previous.width == frame.width, previous.height == frame.height else {
                return false
            }

            guard let shift = detectVerticalScrollShift(prev: previous, curr: frame) else {
                return false
            }

            // If shift is 0, user hasn't scrolled yet; skip frame
            if shift <= 0 {
                return false
            }

            slices.append((image: frame, shift: shift))
            lastCapturedImage = frame
            return true
        }
    }

    nonisolated var capturedFrameCount: Int {
        queue.sync {
            (baseImage != nil ? 1 : 0) + slices.count
        }
    }

    /// Stitches all captured slices into a single tall composite CGImage.
    nonisolated func finalizeStitchedImage() -> CGImage? {
        queue.sync {
            guard let base = baseImage else { return nil }
            if slices.isEmpty { return base }

            let width = base.width
            let totalShift = slices.reduce(0) { $0 + $1.shift }
            let totalHeight = base.height + totalShift

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

            // In CGContext, (0,0) is bottom-left. The initial base frame sits at the top.
            var currentTopY = totalHeight - base.height
            context.draw(base, in: CGRect(x: 0, y: currentTopY, width: width, height: base.height))

            // Draw each slice below it
            for slice in slices {
                let shift = slice.shift
                let img = slice.image

                let cropY = img.height - shift
                guard cropY >= 0, shift > 0,
                      let croppedSlice = img.cropping(to: CGRect(x: 0, y: cropY, width: width, height: shift)) else {
                    continue
                }

                currentTopY -= shift
                context.draw(croppedSlice, in: CGRect(x: 0, y: currentTopY, width: width, height: shift))
            }

            return context.makeImage()
        }
    }

    // MARK: - Pixel Matching Algorithm (Top-Strip Template Matching)
    private func detectVerticalScrollShift(prev: CGImage, curr: CGImage) -> Int? {
        let w = prev.width
        let h = prev.height

        guard w >= 50, h >= 50 else { return nil }

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

        // 1. Check if identical (shift = 0)
        let checkH = min(30, h / 4)
        let checkY = min(100, h / 3)
        var zeroDiff = 0
        let stepX = 6
        var zeroCount = 0

        for y in checkY..<(checkY + checkH) {
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
            return 0 // unchanged
        }

        // 2. Sample a reference strip from `curr` near top: y in [stripY, stripY + stripH]
        let stripH = min(30, h / 6)
        let stripY = min(35, h / 8)

        var bestS = 0
        var minDiff = Int.max
        let maxS = h - stripY - stripH - 8

        guard maxS > 4 else { return nil }

        for s in stride(from: 2, through: maxS, by: 2) {
            let prevY = stripY + s
            var diff = 0
            var sampleCount = 0

            for sy in 0..<stripH {
                let rowC = (stripY + sy) * bprCurr
                let rowP = (prevY + sy) * bprPrev

                for x in stride(from: 40, to: w - 40, by: stepX) {
                    let idxC = rowC + x * bppCurr
                    let idxP = rowP + x * bppPrev
                    guard idxC + 2 < lenCurr, idxP + 2 < lenPrev else { continue }

                    diff += abs(Int(ptrCurr[idxC]) - Int(ptrPrev[idxP]))
                    sampleCount += 1
                }
            }

            if sampleCount > 0 && diff < minDiff {
                minDiff = diff
                bestS = s
            }
        }

        let totalExpectedSamples = stripH * ((w - 80) / stepX)
        guard totalExpectedSamples > 0 else { return nil }

        let avgDiff = minDiff / totalExpectedSamples
        if avgDiff < 24 && bestS > 0 {
            return bestS
        }

        return nil
    }
}
