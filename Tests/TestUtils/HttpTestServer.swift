/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2025-Present Datadog, Inc.
 *
 * This file includes software developed by The OpenTelemetry Authors, https://github.com/open-telemetry/opentelemetry-swift and altered by Datadog.
 * Use of this source code is governed by Apache License 2.0 license: https://github.com/open-telemetry/opentelemetry-swift/blob/main/LICENSE
 */

import Foundation
import XCTest
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A unified HTTP test server using POSIX sockets
/// Combines functionality from both OTLP exporter tests and URLSession instrumentation tests
public class HttpTestServer {
    private var serverSocket: Int32 = -1
    public private(set) var serverPort: Int = 0
    private var isRunning = false
    private var serverQueue: DispatchQueue?
    
    public var baseURL: URL { URL(string: "http://127.0.0.1:\(serverPort)")! }
    public let handler: @Sendable (HTTPTestRequest, HTTPTestResponseSender) -> Void
    
    // Constructor for URLSession tests (with config)
    public convenience init(config: HttpTestServerConfig) {
        self.init() { request, response in
            Self.handleURLSessionRequest(request: request, response: response, config: config)
        }
    }
    
    // Constructor with handler
    public init(handler: @Sendable @escaping (HTTPTestRequest, HTTPTestResponseSender) -> Void) {
        self.handler = handler
    }
    
    public func start() throws {
        // Create socket
        #if canImport(Darwin)
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        #else
        serverSocket = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard serverSocket >= 0 else {
            throw TestServerError.socketCreationFailed
        }
        
        // Allow reuse
        var yes: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        
        // Set non-blocking mode for OTLP tests
        let flags = fcntl(serverSocket, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)
        }
        
        // Bind to port
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = INADDR_ANY
        
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            bind(serverSocket, UnsafeRawPointer(ptr).assumingMemoryBound(to: sockaddr.self), socklen_t(MemoryLayout<sockaddr_in>.size))
        }
        
        guard bindResult >= 0 else {
            close(serverSocket)
            throw TestServerError.bindFailed
        }
        
        // Get assigned port if using port 0
        var actualAddr = sockaddr_in()
        var actualAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getResult = withUnsafeMutablePointer(to: &actualAddr) { ptr in
            getsockname(serverSocket, UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: sockaddr.self), &actualAddrLen)
        }
        
        guard getResult >= 0 else {
            close(serverSocket)
            throw TestServerError.portRetrievalFailed
        }
        
        // Convert from network byte order (big endian) to host byte order
        #if canImport(Darwin)
        serverPort = Int(CFSwapInt16BigToHost(actualAddr.sin_port))
        #else
        serverPort = Int(ntohs(actualAddr.sin_port))
        #endif
        
        // Listen
        guard listen(serverSocket, 10) >= 0 else {
            close(serverSocket)
            throw TestServerError.listenFailed
        }
        
        isRunning = true
        serverQueue = DispatchQueue(label: "HttpTestServer", qos: .userInteractive, attributes: .concurrent)
        
        // Start accept loop
        serverQueue?.async { [weak self] in
            self?.acceptLoop()
        }
    }
    
    public func stop() {
        isRunning = false
        
        // Close server socket
        if serverSocket >= 0 {
            // Use platform-specific shutdown
            #if canImport(Darwin)
            Darwin.shutdown(serverSocket, SHUT_RDWR)
            #elseif canImport(Glibc)
            Glibc.shutdown(serverSocket, Int32(SHUT_RDWR))
            #elseif canImport(Musl)
            Musl.shutdown(serverSocket, Int32(SHUT_RDWR))
            #endif
            close(serverSocket)
            serverSocket = -1
        }
        
        // Wait for queue to finish
        serverQueue?.sync(flags: .barrier) {}
        serverQueue = nil
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Private Implementation
    
    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_in()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                accept(serverSocket, UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: sockaddr.self), &clientAddrLen)
            }
            
            if clientSocket < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    Thread.sleep(forTimeInterval: 0.01)
                    continue
                }
                if !isRunning { break }
                continue
            }
            
            // Handle client asynchronously
            serverQueue?.async {
                self.handleClient(socket: clientSocket)
                close(clientSocket)
            }
        }
    }
    
    private func handleClient(socket clientSocket: Int32) {
        // Read the complete request including body
        var totalData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        
        // struct to send responses
        let response = HTTPTestResponseSender(socket: clientSocket)
        
        // Read headers first
        while true {
            let bytesRead = recv(clientSocket, &buffer, buffer.count, 0)
            guard bytesRead > 0 else { 
                if bytesRead < 0 && errno == EAGAIN {
                    Thread.sleep(forTimeInterval: 0.01)
                    continue
                }
                break 
            }
            totalData.append(contentsOf: buffer[0..<bytesRead])
            
            // Check if we have complete headers
            if let _ = totalData.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
                break
            }
        }
        
        // Parse headers to get content length
        guard let headerEndRange = totalData.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
            response.sendErrorResponse(error: "Headers end not found")
            return
        }
        
        let headerData = totalData.subdata(in: 0..<headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            response.sendErrorResponse(error: "Invalid header data. Can't read UTF-8")
            return
        }
        
        var contentLength = 0
        let lines = headerString.components(separatedBy: "\r\n")
        
        // Parse first line
        guard let firstLine = lines.first else {
            response.sendErrorResponse(error: "Empty header")
            return
        }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 3 else {
            response.sendErrorResponse(error: "First line is not an HTTP command: \(firstLine)")
            return
        }
        
        let method = parts[0]
        let path = parts[1]
        let version = parts[2]
        
        // Parse headers
        var headers = HTTPTestRequest.Headers(headers: [:])
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let name = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers.add(.init(name: name, value: value))
                
                if name.lowercased() == "content-length" {
                    contentLength = Int(value) ?? 0
                }
            }
        }
        
        // Read remaining body if needed
        let currentBodyLength = totalData.count - headerEndRange.upperBound
        if contentLength > currentBodyLength {
            let remainingBytes = contentLength - currentBodyLength
            var bodyBuffer = [UInt8](repeating: 0, count: remainingBytes)
            var totalRead = 0
            
            while totalRead < remainingBytes {
                let bytesRead = recv(clientSocket, &bodyBuffer[totalRead], remainingBytes - totalRead, 0)
                guard bytesRead > 0 else { 
                    if bytesRead < 0 && errno == EAGAIN {
                        Thread.sleep(forTimeInterval: 0.01)
                        continue
                    }
                    break 
                }
                totalRead += bytesRead
            }
            
            totalData.append(contentsOf: bodyBuffer[0..<totalRead])
        }
        
        let body = totalData.subdata(in: headerEndRange.upperBound..<totalData.count)
        let request = HTTPTestRequest(head: .init(method: .init(rawValue: method),
                                                  uri: path,
                                                  version: version == "HTTP/1.1" ? .http1_1 : .http2,
                                                  headers: headers),
                                      body: body)
        handler(request, response)
    }
    
    private static func handleURLSessionRequest(request: HTTPTestRequest, response: HTTPTestResponseSender, config: HttpTestServerConfig) {
        if request.head.uri.hasPrefix("/success") || request.head.uri.hasPrefix("/dontinstrument") {
            response.sendSuccessResponse()
            config.successCallback?()
        } else if request.head.uri.hasPrefix("/forbidden") {
            response.sendForbiddenResponse()
            config.errorCallback?()
        } else if request.head.uri.hasPrefix("/error") {
            response.sendErrorResponse()
            config.errorCallback?()
        } else if request.head.uri.hasPrefix("/network-error") {
            // Close without response
            config.errorCallback?()
        } else if request.head.uri.hasPrefix("/headers") {
            response.sendHeadersResponse(headers: request.head.headers)
            config.successCallback?()
        } else {
            response.sendNotFoundResponse()
        }
    }
}

// MARK: - Error Types

public enum TestServerError: Error, LocalizedError {
    case socketCreationFailed
    case bindFailed
    case listenFailed
    case portRetrievalFailed
    
    public var errorDescription: String? {
        switch self {
        case .socketCreationFailed:
            return "Failed to create socket"
        case .bindFailed:
            return "Failed to bind socket"
        case .listenFailed:
            return "Failed to listen on socket"
        case .portRetrievalFailed:
            return "Failed to retrieve port number"
        }
    }
}

// MARK: - Configuration for URLSession Tests

public typealias GenericCallback = () -> Void

public struct HttpTestServerConfig {
    public var successCallback: GenericCallback?
    public var errorCallback: GenericCallback?
    
    public init(successCallback: GenericCallback? = nil, errorCallback: GenericCallback? = nil) {
        self.successCallback = successCallback
        self.errorCallback = errorCallback
    }
}

// MARK: - HTTP Types for OTLP Tests

/// HTTPRequest wrapper for compatibility
public struct HTTPTestRequest: Sendable {
    public let head: Head
    public let body: Data
    
    init(head: Head, body: Data) {
        self.head = head
        self.body = body
    }
}

public extension HTTPTestRequest {
    struct Head: Equatable, Sendable {
        public let method: Method
        public let uri: String
        public let path: String
        public let version: Version
        public let headers: Headers
        
        init(method: Method, uri: String, version: Version, headers: Headers) {
            self.method = method
            self.uri = uri
            self.version = version
            self.headers = headers
            self.path = uri.components(separatedBy: "?").first ?? uri
        }
    }
    
    struct Method: Equatable, RawRepresentable, Sendable {
        public let rawValue: String
    
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    
        public static let GET = Self(rawValue: "GET")
        public static let POST = Self(rawValue: "POST")
        public static let PUT = Self(rawValue: "PUT")
        public static let DELETE = Self(rawValue: "DELETE")
        public static let HEAD = Self(rawValue: "HEAD")
        public static let OPTIONS = Self(rawValue: "OPTIONS")
        public static let PATCH = Self(rawValue: "PATCH")
    }
    
    enum Version: Equatable, Sendable {
        case http1_1
        case http2
    }
    
    struct Header: Equatable, Sendable {
        public let name: String
        public let value: String
    }
    
    struct Headers: Equatable, Sendable {
        public private(set) var headers: [String: [Header]]
        
        init(headers: [String : [Header]]) {
            self.headers = headers
        }
        
        public func contains(name: String) -> Bool {
            return headers[name.lowercased()] != nil
        }
        
        public func contains(where predicate: (Header) -> Bool) -> Bool {
            for array in headers.values {
                for header in array {
                    if predicate(header) {
                        return true
                    }
                }
            }
            return false
        }
        
        public func first(name: String) -> String? {
            return headers[name.lowercased()]?.first?.value
        }
        
        fileprivate mutating func add(_ header: Header) {
            let name = header.name.lowercased()
            var array = headers[name] ?? []
            array.append(header)
            headers[name] = array
        }
    }
}

public struct HTTPTestResponseSender: Sendable {
    public struct Status: Sendable, Equatable, Hashable, CustomStringConvertible {
        public let code: UInt16
        public let reason: String
        
        public var description: String {
            "\(code) \(reason)"
        }
        
        public init(code: UInt16, reason: String) {
            self.code = code
            self.reason = reason
        }
        
        static var ok: Status { Status(code: 200, reason: "OK") }
        static var badRequest: Status { Status(code: 400, reason: "Bad Request") }
        static var forbidden: Status { Status(code: 403, reason: "Forbidden") }
        static var notFound: Status { Status(code: 404, reason: "Not Found") }
        static var internalServerError: Status { Status(code: 500, reason: "Internal Server Error") }
    }
    
    
    let socket: Int32
    
    public func sendResponse(status: Status, contentType: String, body: Data) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        _ = header.withCString { send(socket, $0, strlen($0), 0) }
        _ = body.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress, !body.isEmpty else { return 0 }
            return send(socket, base, body.count, 0)
        }
    }

    public func sendSuccessResponse(data: Data, type: String) {
        sendResponse(status: .ok, contentType: "text/plain", body: data)
    }
    
    public func sendSuccessResponse(message: String = "Success response!") {
        sendSuccessResponse(data: Data(message.utf8), type: "text/plain")
    }
    
    public func sendErrorResponse(error: String = "Error response!") {
        sendResponse(status: .badRequest, contentType: "text/plain", body: Data(error.utf8))
    }
    
    public func sendForbiddenResponse(message: String = "Forbidden response!") {
        sendResponse(status: .forbidden, contentType: "text/plain", body: Data(message.utf8))
    }
    
    public func sendNotFoundResponse(message: String = "Not Found response!") {
        sendResponse(status: .notFound, contentType: "text/plain", body: Data(message.utf8))
    }
    
    public func sendHeadersResponse(headers: HTTPTestRequest.Headers) {
        let headersStr = headers.headers.flatMap { (_, vals) in
            vals.map { #""\#($0.name)":"\#($0.value)""# }
        }.joined(separator: ",")
        sendSuccessResponse(data: Data("{\(headersStr)}".utf8), type: "application/json")
    }
}
