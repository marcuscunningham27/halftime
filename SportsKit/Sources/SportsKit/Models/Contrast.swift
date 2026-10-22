import Foundation

/// WCAG contrast maths, for keeping white text readable on team-coloured backgrounds.
public enum Contrast {
    /// WCAG AA for body text.
    public static let minimumRatio = 4.5

    /// Relative luminance of an sRGB colour (components 0–1).
    public static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Contrast of white text on this colour.
    public static func whiteRatio(_ r: Double, _ g: Double, _ b: Double) -> Double {
        1.05 / (luminance(r, g, b) + 0.05)
    }

    /// The brightness scale (0–1) to apply to a colour so that, even brightened by `boost` (a backdrop's
    /// lightest fold), white text on it still meets `minimumRatio`. 1 when it already does.
    /// Scaling HSB brightness scales every sRGB component, capped where the brightest one reaches 1.
    public static func readableScale(_ r: Double, _ g: Double, _ b: Double, boost: Double = 1) -> Double {
        let top = max(r, g, b, 0.0001)
        func ratio(_ scale: Double) -> Double {
            let k = min(scale * boost, 1 / top)
            return whiteRatio(r * k, g * k, b * k)
        }
        guard ratio(1) < minimumRatio else { return 1 }
        var low = 0.0, high = 1.0
        for _ in 0..<30 { let mid = (low + high) / 2; if ratio(mid) >= minimumRatio { low = mid } else { high = mid } }
        return low
    }
}
