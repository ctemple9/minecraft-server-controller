//
//  MSCStyles.swift
//  MinecraftServerController
//
//  Centralized design tokens and reusable view modifiers for visual consistency.
//  Drop this file into your Xcode project — everything else references it.
//

import SwiftUI

// MARK: - Design Tokens

/// Single source of truth for every spacing, radius, and color in the app.
/// Using an enum (not a struct) prevents accidental instantiation.
enum MSC {

    // MARK: Spacing

    /// Consistent spacing scale (4-pt grid).
    enum Spacing {
        static let xxs: CGFloat  = 2
        static let xs: CGFloat   = 4
        static let sm: CGFloat   = 8
        static let md: CGFloat   = 12
        static let lg: CGFloat   = 16
        static let xl: CGFloat   = 20
        static let xxl: CGFloat  = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: Corner Radius

    enum Radius {
        static let sm: CGFloat  = 6
        static let md: CGFloat  = 10
        static let lg: CGFloat  = 14
        static let xl: CGFloat  = 18
    }

    // MARK: Colors

    /// Semantic color palette — works automatically in light and dark mode.
    enum Colors {
        // Surfaces (legacy — retained for backwards compatibility)
        static let cardBackground   = Color(nsColor: .windowBackgroundColor)
        static let cardBorder       = Color(nsColor: .separatorColor).opacity(0.35)
        static let subtleBackground = Color(nsColor: .controlBackgroundColor)
        static let insetBackground  = Color(nsColor: .textBackgroundColor).opacity(0.5)

        // Semantic status
        static let success    = Color.green
        static let warning    = Color.orange
        static let error      = Color.red
        static let info       = Color.blue
        static let neutral    = Color.secondary.opacity(0.5)

        // Text
        static let heading    = Color.primary
        static let body       = Color.primary
        static let caption    = Color.secondary
        static let tertiary   = Color(nsColor: .tertiaryLabelColor)

        // Accent (system tint — used for primary buttons, toggles, etc.)
        // Changing this one value recolors the entire app.
        static let accent     = Color.accentColor

        // ─────────────────────────────────────────────────────────────────
        // MARK: Vitreous Surface Tiers
        // ─────────────────────────────────────────────────────────────────

        /// Tier A — Atmosphere: darkest backdrop behind all content.
        /// Use for: window background, outermost container.
        static let tierAtmosphere = Color(red: 0.051, green: 0.051, blue: 0.059)

        /// Tier B — Chrome: shell surfaces that frame the content.
        /// Use for: sidebar, banner, tab strip, details header.
        static let tierChrome     = Color(red: 0.078, green: 0.078, blue: 0.090)

        /// Tier C — Content: the working surface cards and panels sit on.
        /// Use for: cards, info panels, settings rows.
        static let tierContent    = Color(red: 0.110, green: 0.110, blue: 0.130)

        /// Tier D — Terminal: the deepest, most grounded surface.
        /// Use for: console, dense operational log panels.
        static let tierTerminal   = Color(red: 0.039, green: 0.039, blue: 0.047)

        // ─────────────────────────────────────────────────────────────────
        // MARK: Border Values
        // ─────────────────────────────────────────────────────────────────

        /// Chrome border — use sparingly; 0.5pt stroke.
        static let chromeBorder   = Color.white.opacity(0.05)

        /// Content border — standard card stroke; 1pt.
        static let contentBorder  = Color.white.opacity(0.08)

        // Terminal surfaces use no border — they ground themselves via darkness.

        // ─────────────────────────────────────────────────────────────────
        // MARK: Router Guide Section Accents
        // ─────────────────────────────────────────────────────────────────

        /// Firmware warning strip — amber tint, used for disclaimer banners.
        static let guideWarning        = Color.orange
        static let guideWarningFill    = Color.orange.opacity(0.08)
        static let guideWarningBorder  = Color.orange.opacity(0.20)

        /// Menu path breadcrumb row — purple tint.
        static let guideMenuPath       = Color.purple
        static let guideMenuPathFill   = Color.purple.opacity(0.06)
        static let guideMenuPathBorder = Color.purple.opacity(0.18)

        /// Prerequisites / info card — blue tint.
        static let guideInfo           = Color.blue
        static let guideInfoFill       = Color.blue.opacity(0.06)
        static let guideInfoBorder     = Color.blue.opacity(0.18)

        /// Step card / success accent — green tint.
        static let guideStep           = Color.green
        static let guideStepFill       = Color.green.opacity(0.06)
        static let guideStepBorder     = Color.green.opacity(0.18)

        /// Neutral card surface (notes, value summary, troubleshooting rows).
        static let guideNeutralFill    = Color.secondary.opacity(0.06)
        static let guideNeutralBorder  = Color.secondary.opacity(0.15)
        static let guideNeutralDivider = Color.secondary.opacity(0.12)
        static let guideNeutralChip    = Color.secondary.opacity(0.08)
        static let guideNeutralChipBorder = Color.secondary.opacity(0.18)

        // ─────────────────────────────────────────────────────────────────
        // MARK: Connection Status Dots
        // ─────────────────────────────────────────────────────────────────

        /// Bedrock / Java online indicator — warm green.
        static let connectionOnline  = Color(red: 0.30, green: 0.78, blue: 0.47)
        /// Warning / partial state — warm orange.
        static let connectionWarning = Color(red: 1.0,  green: 0.57, blue: 0.24)
        /// Bedrock-specific accent dot — soft blue.
        static let connectionBedrock = Color(red: 0.35, green: 0.63, blue: 1.0)

        // ─────────────────────────────────────────────────────────────────
        // MARK: Accent Helper
        // ─────────────────────────────────────────────────────────────────

        /// Returns the given banner color at a controlled opacity — used to
        /// tint shell surfaces without overwhelming them.
        ///
        /// Usage:
        ///   MSC.Colors.accent(from: server.bannerColor, opacity: 0.20) // banner wash
        ///   MSC.Colors.accent(from: server.bannerColor, opacity: 0.08) // header wash
        ///   MSC.Colors.accent(from: server.bannerColor, opacity: 0.15) // sidebar selection
        static func accent(from bannerColor: Color, opacity: CGFloat) -> Color {
            bannerColor.opacity(opacity)
        }
    }

    // MARK: Typography

    /// Named type styles that map to a clear hierarchy.
    enum Typography {
        // ── Existing roles (unchanged) ───────────────────────────────────
        static let pageTitle      = Font.title2.bold()
        static let sectionHeader  = Font.headline
        static let cardTitle      = Font.system(size: 13, weight: .semibold)
        static let body           = Font.body
        static let caption        = Font.caption
        static let captionBold    = Font.caption.bold()
        static let mono           = Font.system(size: 12, design: .monospaced)
        static let monoSmall      = Font.system(size: 11, design: .monospaced)
        /// Uppercase tracking label — size 9. Use MSCOverline component directly.
        static let overline       = Font.system(size: 9, weight: .semibold)

        // MARK: Shared overlays

        /// Uppercase section label — size 10, semibold.
        /// Use for overline labels in chrome/sidebar regions.
        static let overlineLabel  = Font.system(size: 10, weight: .semibold)

        /// Banner / shell app name — size 15, semibold.
        /// Use for the app name text in the top banner.
        static let shellTitle     = Font.system(size: 15, weight: .semibold)

        /// Metadata that should visually recede — size 11, regular.
        /// Use for ports, paths, secondary info rows.
        static let metaCaption    = Font.system(size: 11)
    }

    // MARK: Animation

    /// Motion tokens — keeps animation feel consistent across the app.
    enum Animation {
        /// Tab switch crossfade — quick, purposeful.
        static let tabSwitch: SwiftUI.Animation = .easeInOut(duration: 0.18)

        /// HUD / toast appear — spring with light bounce.
        static let hudAppear: SwiftUI.Animation = .spring(response: 0.3, dampingFraction: 0.75)

        /// Button press / release — quick tactile compression.
        static let buttonPress: SwiftUI.Animation = .easeOut(duration: 0.12)

        /// Premium chrome glide for tabs and lifted shell controls.
        static let chromeSpring: SwiftUI.Animation = .spring(response: 0.42, dampingFraction: 0.82)
    }
}

// MARK: - Card Modifier (original — unchanged)

/// Wraps content in a consistent rounded card with border.
/// Uses system material background — appropriate for legacy surfaces.
/// Usage:  VStack { ... }.modifier(MSCCard())
struct MSCCard: ViewModifier {
    var padding: CGFloat = MSC.Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                    .fill(MSC.Colors.cardBackground.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                    .stroke(MSC.Colors.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    /// Convenience: `.pscCard()` instead of `.modifier(MSCCard())`
    func pscCard(padding: CGFloat = MSC.Spacing.lg) -> some View {
        modifier(MSCCard(padding: padding))
    }
}

// MARK: - Content Card Modifier

/// Wraps content in a Tier C (content) surface card with a 1pt content border.
/// This is the preferred card for the redesigned surface hierarchy — use this
/// in place of MSCCard for cards and info panels in the details region.
///
/// Usage:  VStack { ... }.modifier(MSCContentCard())
///         VStack { ... }.pscContentCard()
struct MSCContentCard: ViewModifier {
    var padding: CGFloat = MSC.Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                    .fill(MSC.Colors.tierContent)
            )
            .overlay(
                        RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                            .stroke(MSC.Colors.contentBorder, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)
                }
            }

            extension View {
                /// Convenience: `.pscContentCard()` instead of `.modifier(MSCContentCard())`
    func pscContentCard(padding: CGFloat = MSC.Spacing.lg) -> some View {
        modifier(MSCContentCard(padding: padding))
    }
}

// MARK: - Glass Card Modifier (Liquid Glass update)
 
/// Wraps content in a true liquid glass surface:
///   • .ultraThinMaterial blurs whatever sits behind — the real glass effect
///   • Tier C tint overlay keeps it anchored to the content surface tier
///   • Specular gradient simulates ambient light catching the top curved edge
///   • Content border at 0.5pt — glassware has a rim, not a frame
///
/// Use this wherever MSCContentCard is used for prominent cards that should
/// feel lifted rather than painted. Console and sidebar stay on flat tiers.
///
/// Usage:  VStack { ... }.modifier(MSCGlassCard())
///         VStack { ... }.pscGlassCard()
struct MSCGlassCard: ViewModifier {
    var padding: CGFloat = MSC.Spacing.lg
 
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    // Layer 1: System compositor blur — the actual glass
                    RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                        .fill(.ultraThinMaterial)
 
                    // Layer 2: Content tier tint — dark enough to stay readable
                    RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                        .fill(MSC.Colors.tierContent.opacity(0.55))
 
                    // Layer 3: Specular highlight — top curved edge catches light
                    RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.09), Color.clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.45)
                            )
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.lg, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
    }
}
 
extension View {
    /// Convenience: `.pscGlassCard()` instead of `.modifier(MSCGlassCard())`
    func pscGlassCard(padding: CGFloat = MSC.Spacing.lg) -> some View {
        modifier(MSCGlassCard(padding: padding))
    }
}
 
 
// MARK: - Section Header

/// Consistent section header with optional trailing content.
/// Usage:  MSCSectionHeader("Maintenance")
///         MSCSectionHeader("Players") { Button("Refresh") { ... } }
struct MSCSectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(MSC.Typography.sectionHeader)
                .foregroundStyle(MSC.Colors.heading)
            Spacer()
            trailing
        }
    }
}

extension MSCSectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

// MARK: - Overline Label

/// Small uppercase tracking label for sub-sections (like "WORLD", "SETTINGS").
/// Usage:  MSCOverline("World")
struct MSCOverline: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(MSC.Typography.overline)
            .tracking(0.8)
            .foregroundStyle(MSC.Colors.tertiary)
    }
}

// MARK: - Status Dot

/// Colored dot with label for showing running/stopped/warning states.
/// Usage:  MSCStatusDot(color: .green, label: "Running")
struct MSCStatusDot: View {
    let color: Color
    let label: String
    var size: CGFloat = 8

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
            Text(label)
                .font(MSC.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Button Styles

/// Primary action button — filled with accent color.
/// Usage:  Button("Create Server") { ... }.buttonStyle(MSCPrimaryButtonStyle())
struct MSCPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fillColor = isEnabled ? MSC.Colors.accent : MSC.Colors.neutral

        return configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(isEnabled ? 0.98 : 0.72))
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.vertical, MSC.Spacing.sm)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(fillColor)

                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isEnabled ? 0.18 : 0.08), Color.clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.72)
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.10 : 0.04), lineWidth: 0.5)
            }
            .shadow(color: isEnabled ? fillColor.opacity(0.20) : .clear, radius: 10, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.70)
            .animation(MSC.Animation.buttonPress, value: configuration.isPressed)
    }
}

/// Secondary action button — bordered, no fill.
/// Usage:  Button("Cancel") { ... }.buttonStyle(MSCSecondaryButtonStyle())
struct MSCSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isEnabled ? Color.white.opacity(0.92) : Color.white.opacity(0.42))
            .padding(.horizontal, MSC.Spacing.sm + 1)
            .padding(.vertical, MSC.Spacing.xs + 1)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(MSC.Colors.tierContent.opacity(isEnabled ? 0.58 : 0.38))

                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isEnabled ? 0.11 : 0.05), Color.clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.72)
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.10 : 0.05), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(isEnabled ? 0.20 : 0.08), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.78)
            .animation(MSC.Animation.buttonPress, value: configuration.isPressed)
    }
}

/// Destructive button — red text, subtle red background.
/// Usage:  Button("Delete") { ... }.buttonStyle(MSCDestructiveButtonStyle())
struct MSCDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isEnabled ? MSC.Colors.error : MSC.Colors.caption)
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.vertical, MSC.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(MSC.Colors.error.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(MSC.Colors.error.opacity(0.2), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

/// Inline / compact icon-label button for sidebar and toolbars.
/// Usage:  Button { ... } label: { Label("Jars", systemImage: "shippingbox") }
///             .buttonStyle(MSCCompactButtonStyle())
struct MSCCompactButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isEnabled ? Color.white.opacity(0.90) : Color.white.opacity(0.42))
            .padding(.horizontal, MSC.Spacing.sm)
            .padding(.vertical, MSC.Spacing.xs + 2)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(MSC.Colors.tierContent.opacity(isEnabled ? 0.60 : 0.42))

                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isEnabled ? 0.10 : 0.04), Color.clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.72)
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.08 : 0.04), lineWidth: 0.5)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.78)
            .animation(MSC.Animation.buttonPress, value: configuration.isPressed)
    }
}

/// Colored action button — use for state-driven actions like Start (green) / Stop (red).
/// Usage:  Button("Start") { ... }.buttonStyle(MSCActionButtonStyle(color: .green))
struct MSCActionButtonStyle: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fillColor = isEnabled ? color : MSC.Colors.neutral

        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(isEnabled ? .white.opacity(0.98) : MSC.Colors.caption)
            .padding(.horizontal, MSC.Spacing.sm + 1)
            .padding(.vertical, MSC.Spacing.xs + 1)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(fillColor)

                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isEnabled ? 0.16 : 0.06), Color.clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.72)
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.10 : 0.04), lineWidth: 0.5)
            }
            .shadow(color: isEnabled ? fillColor.opacity(0.22) : .clear, radius: 10, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.70)
            .animation(MSC.Animation.buttonPress, value: configuration.isPressed)
    }
}

/// Small shell button — used in banner / chrome utility rows without introducing heavy fills.
struct MSCChromeMiniButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isEnabled ? Color.white.opacity(0.84) : Color.white.opacity(0.38))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(MSC.Colors.tierContent.opacity(isEnabled ? 0.40 : 0.28))

                    RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isEnabled ? 0.12 : 0.05), Color.clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.70)
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.12 : 0.05), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(isEnabled ? 0.18 : 0.08), radius: 6, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(MSC.Animation.buttonPress, value: configuration.isPressed)
    }
}

/// Subtle icon-only chrome button for toolbar / header affordances.
struct MSCGhostIconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isEnabled ? Color.white.opacity(0.72) : Color.white.opacity(0.34))
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: max(8, size * 0.36), style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: max(8, size * 0.36), style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.08 : 0.04), lineWidth: 0.5)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(MSC.Animation.buttonPress, value: configuration.isPressed)
    }
}

// MARK: - Stat Chip (sidebar live metrics)

/// Compact status badge for TPS / player count in the sidebar.
/// Usage:  MSCStatChip(icon: "person.2.fill", value: "3", label: "online", color: .green)
struct MSCStatChip: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.1)))
        .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 0.5))
    }
}

// MARK: - Save HUD Banner (reusable toast)

/// Drop-in toast notification for confirmations.
/// Usage:  .overlay(alignment: .top) { if showHUD { MSCSaveHUD(text: "Saved") } }
struct MSCSaveHUD: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.vertical, MSC.Spacing.sm)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.75))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            )
    }
}

// MARK: - Sheet Header

/// Standard sheet header row with title and close button.
/// Usage:  MSCSheetHeader("Backups") { isPresented = false }
struct MSCSheetHeader: View {
    let title: String
    let subtitle: String?
    let onClose: () -> Void

    init(_ title: String, subtitle: String? = nil, onClose: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(MSC.Typography.pageTitle)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(MSCSecondaryButtonStyle())
            }
            .padding(.bottom, MSC.Spacing.md)

            Divider()
        }
    }
}

