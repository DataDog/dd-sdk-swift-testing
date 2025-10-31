//
//  MultipartFormURLRequest.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 28/10/2025.
//

import Foundation

struct MultipartFormURLRequest {
    let url: URL
    var headers: [HTTPHeader] = []
    
    private let boundary: String = UUID().uuidString
    private var body: Data = Data()
    
    init(url: URL) {
        self.url = url
    }
    
    mutating func append(text: String, withName name: String) {
        body.append(contentsOf: "--".utf8)
        body.append(contentsOf: boundary.utf8)
        body.append(contentsOf: "\r\nContent-Disposition: form-data; name=\"".utf8)
        body.append(name.data(using: .ascii, allowLossyConversion: true)!)
        body.append(contentsOf: "\"\r\n".utf8)
        body.append(contentsOf: "Content-Type: text/plain; charset=UTF-8\r\n".utf8)
        body.append(contentsOf: "Content-Transfer-Encoding: 8bit\r\n\r\n".utf8)
        body.append(contentsOf: text.utf8)
        body.append(contentsOf: "\r\n".utf8)
    }
    
    mutating func append(data: Data,
                         withName name: String,
                         filename: String,
                         contentType: ContentType)
    {
        body.append(contentsOf: "--".utf8)
        body.append(contentsOf: boundary.utf8)
        body.append(contentsOf: "\r\nContent-Disposition: form-data; name=\"".utf8)
        body.append(name.data(using: .ascii, allowLossyConversion: true)!)
        body.append(contentsOf: "\"; filename=\"".utf8)
        body.append(filename.data(using: .ascii, allowLossyConversion: true)!)
        body.append(contentsOf: "\"\r\nContent-Type: ".utf8)
        body.append(contentsOf: contentType.rawValue.utf8)
        body.append(contentsOf: "\r\n\r\n".utf8)
        body.append(data)
        body.append(contentsOf: "\r\n".utf8)
    }
    
    var asURLRequest: URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpHeaders = headers
        request.setValue(.constant("multipart/form-data; boundary=\(boundary)"), forHTTPHeader: .contentTypeHeaderField)
        request.httpBody = body + Data("--\(boundary)--".utf8)
        return request
    }
}

extension HTTPClient {
    func send(request: MultipartFormURLRequest, _ completion: @escaping (Result<HTTPURLResponse, RequestError>) -> Void) {
        send(request: request.asURLRequest, completion)
    }
    
    func sendWithResponse(request: MultipartFormURLRequest, _ completion: @escaping (Result<Data, RequestError>) -> Void) {
        sendWithResponse(request: request.asURLRequest, completion)
    }
}
