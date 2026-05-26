// ClipboardManager/UI/DesignSystem/FileTypeStyle.swift
import SwiftUI

enum FileTypeStyle {
    static func symbolName(for ext: String) -> String {
        switch ext {
        case "pdf":                                             return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic", "tiff":      return "photo"
        case "mp4", "mov", "m4v":                              return "film"
        case "mp3", "wav", "m4a", "aiff":                     return "music.note"
        case "zip", "tar", "gz", "7z":                        return "doc.zipper"
        case "fig":                                            return "paintbrush"
        case "sketch":                                         return "scribble"
        case "key", "pages", "numbers":                       return "doc.text"
        case "xlsx", "csv":                                    return "tablecells"
        case "docx", "rtf", "txt", "md":                      return "doc.text"
        default:                                               return "doc"
        }
    }

    static func color(for ext: String) -> Color {
        switch ext {
        case "pdf":                                            return .red
        case "fig":                                            return .purple
        case "sketch":                                         return .orange
        case "key":                                            return .blue
        case "xlsx", "csv":                                    return .green
        case "docx":                                           return .blue
        case "zip", "tar", "gz", "7z":                        return .gray
        case "png", "jpg", "jpeg", "gif", "heic", "tiff":     return .pink
        case "mp4", "mov", "m4v":                             return .purple
        default:                                               return .secondary
        }
    }
}
