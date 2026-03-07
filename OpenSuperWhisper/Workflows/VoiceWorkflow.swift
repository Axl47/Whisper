import Foundation

#if canImport(AppKit)
import AppKit
import SwiftUI
#endif

enum VoiceWorkflowLaunchMode: String, Codable, CaseIterable, Sendable {
    case executable
    case shell

    var displayName: String {
        switch self {
        case .executable:
            return "Executable"
        case .shell:
            return "Shell"
        }
    }
}

struct VoiceWorkflow: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var aliases: [String]
    var launchMode: VoiceWorkflowLaunchMode
    var executablePath: String
    var arguments: [String]
    var shellCommand: String
    var accentColorHex: String?

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        aliases: [String],
        launchMode: VoiceWorkflowLaunchMode = .executable,
        executablePath: String,
        arguments: [String],
        shellCommand: String = "",
        accentColorHex: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.aliases = aliases
        self.launchMode = launchMode
        self.executablePath = executablePath
        self.arguments = arguments
        self.shellCommand = shellCommand
        self.accentColorHex = accentColorHex
    }
}

extension VoiceWorkflow {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isEnabled
        case aliases
        case launchMode
        case executablePath
        case arguments
        case shellCommand
        case accentColorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        aliases = try container.decode([String].self, forKey: .aliases)
        launchMode = try container.decodeIfPresent(VoiceWorkflowLaunchMode.self, forKey: .launchMode) ?? .executable
        executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath) ?? ""
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        shellCommand = try container.decodeIfPresent(String.self, forKey: .shellCommand) ?? ""
        accentColorHex = try container.decodeIfPresent(String.self, forKey: .accentColorHex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(aliases, forKey: .aliases)
        try container.encode(launchMode, forKey: .launchMode)
        try container.encode(executablePath, forKey: .executablePath)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(shellCommand, forKey: .shellCommand)
        try container.encodeIfPresent(accentColorHex, forKey: .accentColorHex)
    }
}

#if canImport(AppKit)
extension VoiceWorkflow {
    var accentColor: Color? {
        guard let accentColorHex else {
            return nil
        }
        return Color(workflowHex: accentColorHex)
    }
}

extension Color {
    init?(workflowHex: String) {
        let hex = workflowHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 8, let value = UInt64(hex, radix: 16) else {
            return nil
        }

        let red = Double((value >> 24) & 0xFF) / 255
        let green = Double((value >> 16) & 0xFF) / 255
        let blue = Double((value >> 8) & 0xFF) / 255
        let opacity = Double(value & 0xFF) / 255
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    func workflowHexString() -> String? {
        let nsColor = NSColor(self).usingColorSpace(.sRGB)
        guard let color = nsColor else {
            return nil
        }

        let red = UInt8((color.redComponent * 255).rounded())
        let green = UInt8((color.greenComponent * 255).rounded())
        let blue = UInt8((color.blueComponent * 255).rounded())
        let alpha = UInt8((color.alphaComponent * 255).rounded())
        return String(format: "%02X%02X%02X%02X", red, green, blue, alpha)
    }
}
#endif
