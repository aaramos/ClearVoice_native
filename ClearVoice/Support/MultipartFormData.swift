import Foundation

struct MultipartFormBody: Sendable {
    let contentType: String
    let body: Data
}

enum MultipartFormDataBuilder {
    static func build(
        fileFieldName: String,
        filename: String,
        mimeType: String,
        fileData: Data,
        textFields: [(name: String, value: String)]
    ) -> MultipartFormBody {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        for field in textFields {
            append("--\(boundary)\r\n", to: &body)
            append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n", to: &body)
            append("\(field.value)\r\n", to: &body)
        }

        append("--\(boundary)\r\n", to: &body)
        append(
            "Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(filename)\"\r\n",
            to: &body
        )
        append("Content-Type: \(mimeType)\r\n\r\n", to: &body)
        body.append(fileData)
        append("\r\n", to: &body)
        append("--\(boundary)--\r\n", to: &body)

        return MultipartFormBody(
            contentType: "multipart/form-data; boundary=\(boundary)",
            body: body
        )
    }

    private static func append(_ string: String, to data: inout Data) {
        data.append(Data(string.utf8))
    }
}
