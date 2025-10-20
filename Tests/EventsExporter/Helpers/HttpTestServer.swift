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
    private let startSemaphore = DispatchSemaphore(value: 0)
    
    // Request tracking for OTLP tests
    internal var receivedRequests: [HTTPTestRequest] = []
    internal let receivedRequestsQueue = DispatchQueue(label: "HttpTestServer.requests",
                                                       qos: .userInteractive,
                                                       target: .global(qos: .userInteractive))
    
    // Configuration for URLSession tests
    public var config: HttpTestServerConfig?
    
    // Server properties
    private var host: String
    private var port: Int
    
    // Constructor for OTLP tests (no URL/config)
    public convenience init() {
        self.init(url: nil, config: nil)
    }
    
    // Constructor for URLSession tests (with URL/config)
    public init(url: URL?, config: HttpTestServerConfig? = nil) {
        self.host = url?.host ?? "localhost"
        self.port = url?.port ?? 0  // 0 means OS will assign port
        self.config = config
    }
    
    public func start() throws {
        try start(semaphore: nil)
    }
    
    public func start(semaphore: DispatchSemaphore?) throws {
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
        if config == nil {
            let flags = fcntl(serverSocket, F_GETFL, 0)
            if flags >= 0 {
                _ = fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)
            }
        }
        
        // Bind to port
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
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
        serverQueue = DispatchQueue(label: "HttpTestServer",
                                    qos: .userInteractive,
                                    attributes: .concurrent)
        
        // Start accept loop
        serverQueue?.async { [weak self] in
            self?.acceptLoop()
        }
        
        // Signal that server is ready
        startSemaphore.signal()
        semaphore?.signal()  // For URLSession tests compatibility
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
        
        // Clear received requests
        receivedRequestsQueue.sync {
            receivedRequests.removeAll()
        }
        
        // Wait for queue to finish
        serverQueue?.sync(flags: .barrier) {}
        serverQueue = nil
    }
    
    public func shutdown() {
        stop()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - OTLP Test Support
    
    public var requests: [HTTPTestRequest] {
        return receivedRequestsQueue.sync { receivedRequests }
    }
    
    public func waitForRequest(timeout: TimeInterval = 5.0, remove: Bool = false) -> HTTPTestRequest? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            let request: HTTPTestRequest? = receivedRequestsQueue.sync {
                if remove && receivedRequests.count > 0 {
                    return receivedRequests.removeFirst()
                }
                return receivedRequests.first
            }
            if let request = request {
                return request
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }
    
    public func clearRequests() {
        receivedRequestsQueue.sync {
            receivedRequests.removeAll()
        }
    }
    
    // For backward compatibility with existing test APIs
    public func clearReceivedRequests() {
        clearRequests()
    }
    
    // Wait for the next request and provide access to headers and body
    public func receiveHeadAndVerify(_ verify: (HTTPTestRequest.Head) throws -> Void) rethrows {
        guard let request = waitForRequest() else {
            XCTFail("Timeout waiting for request")
            return
        }
        try verify(request.head)
    }
    
    public func receiveBodyAndVerify(_ verify: (Data) throws -> Void) rethrows {
        guard let lastRequest = receivedRequestsQueue.sync(execute: { receivedRequests.last }) else {
            XCTFail("No request received")
            return
        }
        try verify(lastRequest.body)
    }
    
    public func receiveEnd() throws {
        // This is a no-op for compatibility with the NIOHTTP1 test server API
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
            sendErrorResponse(socket: clientSocket)
            return
        }
        
        let headerData = totalData.subdata(in: 0..<headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            sendErrorResponse(socket: clientSocket)
            return
        }
        
        var contentLength = 0
        let lines = headerString.components(separatedBy: "\r\n")
        
        // Parse first line
        guard let firstLine = lines.first else {
            sendErrorResponse(socket: clientSocket)
            return
        }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 3 else {
            sendErrorResponse(socket: clientSocket)
            return
        }
        
        let _ = parts[0]  // method - unused but needed for parsing
        let path = parts[1]
        
        // Parse headers
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
                
                if key.lowercased() == "content-length" {
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
        
        // Handle URLSession test paths
        if config != nil {
            handleURLSessionRequest(socket: clientSocket, path: path)
            return
        }

        // Handle OTLP test requests (or when no config is provided)
        // For paths like /error without config, still handle them appropriately
        if path.hasPrefix("/error") {
            // Close without response - this simulates a network error
            return
        }

        guard let request = parseHttpRequest(rawData: totalData) else {
            sendErrorResponse(socket: clientSocket)
            return
        }
        
        // Store the request
        receivedRequestsQueue.sync {
            receivedRequests.append(request)
        }
        
        // Send success response
        sendSuccessResponse(socket: clientSocket)
    }
    
    private func handleURLSessionRequest(socket: Int32, path: String) {
        if path.hasPrefix("/success") || path.hasPrefix("/dontinstrument") {
            sendSuccessResponse(socket: socket)
            config?.successCallback?()
        } else if path.hasPrefix("/forbidden") {
            sendForbiddenResponse(socket: socket)
            config?.errorCallback?()
        } else if path.hasPrefix("/error") {
            // Close without response
            config?.errorCallback?()
        } else {
            sendNotFoundResponse(socket: socket)
        }
    }
    
    private func sendSuccessResponse(socket: Int32) {
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        _ = response.withCString { ptr in
            send(socket, ptr, strlen(ptr), 0)
        }
    }
    
    private func sendErrorResponse(socket: Int32) {
        let response = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        _ = response.withCString { ptr in
            send(socket, ptr, strlen(ptr), 0)
        }
    }
    
    private func sendForbiddenResponse(socket: Int32) {
        let response = "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        _ = response.withCString { ptr in
            send(socket, ptr, strlen(ptr), 0)
        }
    }
    
    private func sendNotFoundResponse(socket: Int32) {
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        _ = response.withCString { ptr in
            send(socket, ptr, strlen(ptr), 0)
        }
    }
    
    private func parseHttpRequest(rawData: Data) -> HTTPTestRequest? {
        // Find header end
        guard let headerEndRange = rawData.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
            return nil
        }
        
        let headerData = rawData.subdata(in: 0..<headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }
        
        // Parse request line
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 3 else {
            return nil
        }
        
        let method = parts[0]
        let uri = parts[1]
        let version = parts[2]
        
        // Parse headers
        var headers = HTTPTestRequest.Headers(headers: [:])
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let name = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers.add(.init(name: name, value: value))
            }
        }
        
        // Extract body
        let bodyStartIndex = headerEndRange.upperBound
        let body = rawData.subdata(in: bodyStartIndex..<rawData.count)
        
        return .init(head: .init(method: .init(rawValue: method),
                                 uri: uri,
                                 version: version == "HTTP/1.1" ? .http1_1 : .http2,
                                 headers: headers),
                     body: body)
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
public struct HTTPTestRequest {
    public let head: Head
    public let body: Data
    
    init(head: Head, body: Data) {
        self.head = head
        self.body = body
    }
}

public extension HTTPTestRequest {
    struct Head: Equatable {
        public let method: Method
        public let uri: String
        public let version: Version
        public let headers: Headers
    }
    
    struct Method: Equatable, RawRepresentable {
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
    
    enum Version: Equatable {
        case http1_1
        case http2
    }
    
    struct Header: Equatable {
        public let name: String
        public let value: String
    }
    
    struct Headers: Equatable {
        private var headers: [String: [Header]]
        
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
