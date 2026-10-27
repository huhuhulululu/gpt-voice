import Foundation

struct MultipartAudio {
    let boundary: String
    let body: Data

    init(audio: Data, filename: String, contentType: String, language: String? = nil,
         extraFields: [String: String] = [:],
         boundary: String = "----codex-dictation-\(UUID().uuidString)") {
        self.boundary = boundary
        var result = Data()
        func append(_ value: String) { result.append(Data(value.utf8)) }
        func sanitize(_ value: String) -> String {
            value.replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
        }
        let name = sanitize(filename)
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        result.append(audio)
        append("\r\n")
        var fields: [(String, String)] = []
        if let language, !language.isEmpty { fields.append(("language", language)) }
        fields.append(contentsOf: extraFields.sorted { $0.key < $1.key })
        for (key, value) in fields where !value.isEmpty {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(sanitize(key))\"\r\n\r\n\(sanitize(value))\r\n")
        }
        append("--\(boundary)--\r\n")
        body = result
    }
}
