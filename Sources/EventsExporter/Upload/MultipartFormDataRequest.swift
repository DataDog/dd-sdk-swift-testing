/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

typealias AddFields = (MultipartFormDataRequest, Data) -> Void

struct MultipartFormDataRequest {
    private let boundary: String = UUID().uuidString
    private var httpBody = NSMutableData()
    let url: URL
    let addFieldsCallback: AddFields?

    init(url: URL, addFieldsCallback: AddFields?) {
        self.url = url
        self.addFieldsCallback = addFieldsCallback
    }

    func addTextField(named name: String, value: String) {
        httpBody.append(textFormField(named: name, value: value))
    }

    private func textFormField(named name: String, value: String) -> String {
        var fieldString = "--\(boundary)\r\n"
        fieldString += "Content-Disposition: form-data; name=\"\(name)\"\r\n"
        fieldString += "Content-Type: text/plain; charset=ISO-8859-1\r\n"
        fieldString += "Content-Transfer-Encoding: 8bit\r\n"
        fieldString += "\r\n"
        fieldString += "\(value)\r\n"

        return fieldString
    }

    func addDataField(named name: String, data: Data, mimeType: ContentType) {
        httpBody.append(dataFormField(named: name, data: data, mimeType: mimeType))
    }

    private func dataFormField(named name: String,
                               data: Data,
                               mimeType: ContentType) -> Data
    {
        let fieldData = NSMutableData()

        fieldData.append("--\(boundary)\r\n")
        if mimeType == .applicationOctetStream {
            fieldData.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"file\(name).pack\"\r\n")
        } else {
            fieldData.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"file\(name).json\"\r\n")
        }
        fieldData.append("Content-Type: \(mimeType.rawValue)\r\n")
        fieldData.append("\r\n")
        fieldData.append(data)
        fieldData.append("\r\n")

        return fieldData as Data
    }

    func asURLRequest() -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        httpBody.append("--\(boundary)--")
        let data = (httpBody as Data)
        request.httpBody = request.allHTTPHeaderFields?["Content-Encoding"] != nil ? data.deflated : data
        return request
    }
}

extension NSMutableData {
    func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.append(data)
        }
    }
}

extension URLSession {
    func dataTask(with request: MultipartFormDataRequest,
                  completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void)
        -> URLSessionDataTask
    {
        return dataTask(with: request.asURLRequest(), completionHandler: completionHandler)
    }
}
