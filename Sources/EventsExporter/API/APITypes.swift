/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

protocol APIAttributes {
    static var apiType: String { get }
}

extension APIAttributes {
    var apiType: String { Self.apiType }
}

protocol APIResponseAttributes: APIAttributes {
    static func isTypeValid(_ type: String) -> Bool
    static func isIdValid(request rqid: String?, response rsid: String?) -> Bool
}

protocol APICommonData: CustomDebugStringConvertible {
    associatedtype Meta
    associatedtype Attributes: APIAttributes

    var id: String? { get }
    var type: String { get }
    var attributes: Attributes { get }
}

extension APICommonData {
    var debugDescription: String {
        var out: String = #"{"type": "\#(type)""#
        if let id {
            out.append(#", "id": "\#(id)""#)
        }
        if attributes as? APIVoidValue == nil {
            out.append(#", "attributes": \#(attributes)"#)
        }
        out.append("}")
        return out
    }
}

protocol APIRequestData: APICommonData, Encodable where Attributes: Encodable, Meta: Encodable {}
protocol APIResponseData: APICommonData, Decodable where Attributes: Decodable & APIResponseAttributes, Meta: Decodable {
    var isTypeValid: Bool { get }
    func isIdValid(_ id: String?) -> Bool
}

extension APIResponseData {
    var isTypeValid: Bool { Attributes.isTypeValid(type) }
    func isIdValid(_ id: String?) -> Bool { Attributes.isIdValid(request: id, response: self.id) }
}

extension Array: APIAttributes, APIAttributesAutoId, APIAttributesNoId where Element: APIAttributes {
    static var apiType: String { Element.apiType }
}

extension Array: APIResponseAttributes, APIResponseAttributesNoId where Element: APIResponseAttributes {
    static func isTypeValid(_ type: String) -> Bool { Element.isTypeValid(type) }
}

extension Array: APICommonData where Element: APICommonData {
    typealias Meta = Element.Meta
    typealias Attributes = Array<Element.Attributes>

    var id: String? { nil }
    var type: String { Attributes.apiType }
    var attributes: Array<Element.Attributes> { map { $0.attributes } }
}

extension Array: APIRequestData where Element: APIRequestData {}
extension Array: APIResponseData where Element: APIResponseData {
    var isTypeValid: Bool { allSatisfy { $0.isTypeValid } }
}

public protocol APIService {
    var endpoint: Endpoint { get set }
    var headers: [HTTPHeader] { get set }
    var encoder: JSONEncoder { get set }
    var decoder: JSONDecoder { get set }

    var endpointURLs: Set<URL> { get }
}

internal protocol APIServiceConstructible: APIService {
    init(config: APIServiceConfig, httpClient: any HTTPClientType, log: Logger)
}

protocol APIVoidValue {
    static var void: Self { get }
}

struct APIData<Meta, Attributes: APIAttributes>: APICommonData {
    typealias Meta = Meta
    typealias Attributes = Attributes

    let id: String?
    let type: String
    let attributes: Attributes

    enum CodingKeys: CodingKey {
        case id
        case type
        case attributes
    }

    init(id: String?, attributes: Attributes) {
        self.id = id
        self.type = Attributes.apiType
        self.attributes = attributes
    }
}

typealias APIDataNoMeta<Attributes: APIAttributes> = APIData<APIVoidMeta, Attributes>

protocol APIAttributesAutoId: APIAttributes {
    static var nextId: String? { get }
}

protocol APIAttributesNoId: APIAttributesAutoId {}
extension APIAttributesNoId {
    static var nextId: String? { nil }
}

protocol APIAttributesUUID: APIAttributesAutoId {}
extension APIAttributesUUID {
    static var nextId: String? { UUID().uuidString }
}

protocol APIResponseAttributesHasType: APIResponseAttributes {}
extension APIResponseAttributesHasType {
    static func isTypeValid(_ type: String) -> Bool { Self.apiType == type }
}

protocol APIResponseAttributesIgnoreType: APIResponseAttributes {}
extension APIResponseAttributesIgnoreType {
    static func isTypeValid(_ type: String) -> Bool { true }
}

protocol APIResponseAttributesHasId: APIResponseAttributes {}
extension APIResponseAttributesHasId {
    static func isIdValid(request: String?, response: String?) -> Bool {
        request != nil && response != nil && request == response
    }
}

protocol APIResponseAttributesBrokenId: APIResponseAttributes {}
extension APIResponseAttributesBrokenId {
    static func isIdValid(request: String?, response: String?) -> Bool {
        response != nil
    }
}

protocol APIResponseAttributesNoId: APIResponseAttributes {}
extension APIResponseAttributesNoId {
    static func isIdValid(request: String?, response: String?) -> Bool {
        response == nil
    }
}

extension APIData where Attributes: APIVoidValue {
    init(id: String?) {
        self.init(id: id, attributes: .void)
    }
}

extension APIData where Attributes: APIAttributesAutoId {
    init(attributes: Attributes) {
        self.init(id: Attributes.nextId, attributes: attributes)
    }
}

extension APIData where Attributes: APIVoidValue & APIAttributesAutoId {
    init() {
        self.init(id: Attributes.nextId)
    }
}

extension APIData: Encodable where Attributes: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(type, forKey: .type)
        if attributes as? APIVoidValue == nil {
            try container.encode(attributes, forKey: .attributes)
        }
    }
}
extension APIData: Decodable where Attributes: Decodable {
    init(from decoder: any Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        if let void = Attributes.self as? APIVoidValue.Type {
            attributes = void.void as! Attributes
        } else {
            attributes = try container.decode(Attributes.self, forKey: .attributes)
        }
    }
}

extension APIData: APIRequestData where Meta: Encodable, Attributes: Encodable {}
extension APIData: APIResponseData where Meta: Decodable, Attributes: Decodable & APIResponseAttributes {}

struct APIVoidMeta: APIVoidValue, Codable {
    static var void: Self { .init() }
}

struct APIEnvelope<Data: APICommonData>: CustomDebugStringConvertible {
    let meta: Data.Meta
    let data: Data

    init(meta: Data.Meta, data: Data) {
        self.meta = meta
        self.data = data
    }

    enum CodingKeys: CodingKey {
        case meta
        case data
    }
    
    var debugDescription: String {
        if meta as? APIVoidValue == nil {
            return #"{"data": \#(data)}"#
        } else {
            return #"{"meta": \#(meta), "data": \#(data)}"#
        }
    }
}

extension APIEnvelope where Data.Meta: APIVoidValue {
    init(data: Data) {
        self.meta = .void
        self.data = data
    }
}

extension APIEnvelope: Encodable where Data: APIRequestData {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if meta as? APIVoidValue == nil {
            try container.encode(meta, forKey: .meta)
        }
        try container.encode(data, forKey: .data)
    }
}
extension APIEnvelope: Decodable where Data: APIResponseData {
    init(from decoder: any Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        if let void = Data.Meta.self as? APIVoidValue.Type {
            meta = void.void as! Data.Meta
        } else {
            meta = try container.decode(Data.Meta.self, forKey: .meta)
        }
        data = try container.decode(Data.self, forKey: .data)
    }
}

// Helper struct to describe API call with request+response
struct APICall<Request: APIRequestData, Response: APIResponseData> {
    static func request(meta: Request.Meta, data: Request,
                        coder: JSONEncoder) throws(APICallError) -> (id: String?, body: Data)
    {
        let body = try coder.apiEncode(APIEnvelope<Request>(meta: meta, data: data))
        return (data.id, body)
    }

    static func response(from data: Data,
                         requestId: String?,
                         coder: JSONDecoder) throws(APICallError) -> APIEnvelope<Response>
    {
        let response = try coder.apiDecode(APIEnvelope<Response>.self, from: data)
        guard response.data.isIdValid(requestId) else {
            throw .idMismatch(expected: requestId, got: response.data.id)
        }
        guard response.data.isTypeValid else {
            throw .typeMismatch(expected: Response.Attributes.apiType,
                                got: response.data.type)
        }
        return response
    }

    private init() {}
}

public enum APICallError: Error {
    case transport(any Error)
    case httpError(code: Int, headers: [HTTPHeader.Field: String], body: Data?)
    case encoding(value: any Encodable, error: EncodingError)
    case decoding(body: Data, error: DecodingError)
    case idMismatch(expected: String?, got: String?)
    case typeMismatch(expected: String, got: String)
    case fileSystem(any Error)
    case unknownError(any Error)

    init(from error: HTTPClient.RequestError) {
        switch error {
        case .http(code: let code, headers: let headers, body: let body):
            self = .httpError(code: code, headers: headers, body: body)
        case .transport(let err):
            self = .transport(err)
        default:
            self = .transport(error)
        }
    }

    public var isUnauthorized: Bool {
        switch self {
        case .httpError(code: 401, headers: _, body: _),
             .httpError(code: 403, headers: _, body: _):
            return true
        default: return false
        }
    }
}

extension APICallError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .transport(let error):
            return "transport error: \(error.localizedDescription)"
        case .httpError(code: let code, headers: _, body: let body):
            if let body, let text = String(data: body, encoding: .utf8), !text.isEmpty {
                return "HTTP \(code): \(text)"
            }
            return "HTTP \(code)"
        case .encoding(_, let error):
            return "encoding error: \(error.localizedDescription)"
        case .decoding(_, let error):
            return "decoding error: \(error.localizedDescription)"
        case .idMismatch(let expected, let got):
            return "id mismatch: expected \(expected ?? "nil"), got \(got ?? "nil")"
        case .typeMismatch(let expected, let got):
            return "type mismatch: expected \(expected), got \(got)"
        case .fileSystem(let error):
            return "file system error: \(error.localizedDescription)"
        case .unknownError(let error):
            return "unknown error: \(error.localizedDescription)"
        }
    }
}

internal struct APIServiceConfig {
    let serviceName: String
    let environment: String
    let applicationName: String
    /// Version of the application under test (from its bundle).
    let applicationVersion: String
    /// Version of the DatadogSDKTesting library itself.
    let libraryVersion: String
    let device: Device
    let hostname: String?
    let kernelInfo: KernelInfo
    let languageVersion: String
    let runtimeName: String
    let runtimeVersion: String

    /// API key for authentication
    let apiKey: String

    /// Endpoint that will be used for reporting.
    let endpoint: Endpoint

    /// Client ID for tracing
    let clientId: String

    /// API will deflate payloads before sending
    let payloadCompression: Bool

    let encoder: JSONEncoder = .apiEncoder
    let decoder: JSONDecoder = .apiDecoder

    var defaultHeaders: [HTTPHeader] {
        [
            .userAgentHeader(
                appName: applicationName,
                appVersion: applicationVersion,
                device: device
            ),
            .apiKeyHeader(apiKey: apiKey),
            .traceIDHeader(traceID: clientId),
            .parentSpanIDHeader(parentSpanID: clientId),
            .samplingPriorityHeader()
        ] + (hostname != nil ? [.hostnameHeader(hostname: hostname!)] : [])
    }

    init(serviceName: String, environment: String,
         applicationName: String,
         applicationVersion: String, libraryVersion: String,
         device: Device, hostname: String?,
         kernelInfo: KernelInfo, languageVersion: String,
         runtimeName: String, runtimeVersion: String,
         apiKey: String, endpoint: Endpoint,
         clientId: String, payloadCompression: Bool)
    {
        self.serviceName = serviceName
        self.environment = environment
        self.applicationName = applicationName
        self.applicationVersion = applicationVersion
        self.libraryVersion = libraryVersion
        self.device = device
        self.hostname = hostname
        self.kernelInfo = kernelInfo
        self.languageVersion = languageVersion
        self.runtimeName = runtimeName
        self.runtimeVersion = runtimeVersion
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.clientId = clientId
        self.payloadCompression = payloadCompression
    }
}

extension JSONEncoder {
    internal static let apiEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatted = iso8601DateFormatter.string(from: date)
            try container.encode(formatted)
        }
        encoder.dataEncodingStrategy = .base64
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.nonConformingFloatEncodingStrategy = .throw
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    func apiEncode(_ value: some Encodable) throws(APICallError) -> Data {
        do {
            return try encode(value)
        } catch let err as EncodingError {
            throw .encoding(value: value, error: err)
        } catch {
            throw .unknownError(error)
        }
    }
}

extension JSONDecoder {
    internal static let apiDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = iso8601DateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container,
                                                       debugDescription: "Bad date: \(string)")
            }
            return date
        }
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dataDecodingStrategy = .base64
        return decoder
    }()

    func apiDecode<T: Decodable>(_ type: T.Type, from data: Data) throws(APICallError) -> T {
        do {
            return try decode(type, from: data)
        } catch let err as DecodingError {
            throw .decoding(body: data, error: err)
        } catch {
            throw .unknownError(error)
        }
    }
}

extension HTTPClientType {
    func call<Request, Response>(
        _ call: APICall<Request, Response>.Type,
        url: URL, meta: Request.Meta, data: Request,
        headers: [HTTPHeader]? = nil,
        coders: (JSONEncoder, JSONDecoder) = (.apiEncoder, .apiDecoder),
        observer: RequestObserver? = nil
    ) async throws(APICallError) -> APIEnvelope<Response>
    where Request: APIRequestData, Response: APIResponseData
    {
        let (requestId, requestData) = try call.request(meta: meta, data: data, coder: coders.0)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let headers = headers {
            request.httpHeaders = headers
        }
        request.httpBody = requestData

        let body: Data = try await sendWithResponse(api: request, observer: observer)
        return try call.response(from: body, requestId: requestId, coder: coders.1)
    }

    func call<Request, Response>(
        _ call: APICall<Request, Response>.Type,
        url: URL, data: Request,
        headers: [HTTPHeader]? = nil,
        coders: (JSONEncoder, JSONDecoder) = (.apiEncoder, .apiDecoder),
        observer: RequestObserver? = nil
    ) async throws(APICallError) -> APIEnvelope<Response>
    where Request: APIRequestData, Response: APIResponseData, Request.Meta: APIVoidValue
    {
        try await self.call(call, url: url, meta: .void, data: data, headers: headers, coders: coders, observer: observer)
    }

    func send(api request: URLRequest, observer: RequestObserver? = nil) async throws(APICallError) -> HTTPURLResponse {
        do {
            return try await send(request: request, observer: observer)
        } catch {
            throw APICallError(from: error)
        }
    }

    func sendWithResponse(api request: URLRequest, observer: RequestObserver? = nil) async throws(APICallError) -> Data {
        do {
            return try await sendWithResponse(request: request, observer: observer)
        } catch {
            throw APICallError(from: error)
        }
    }

    func send(api request: MultipartFormURLRequest, observer: RequestObserver? = nil) async throws(APICallError) -> HTTPURLResponse {
        try await send(api: request.asURLRequest, observer: observer)
    }

    func sendWithResponse(api request: MultipartFormURLRequest, observer: RequestObserver? = nil) async throws(APICallError) -> Data {
        try await sendWithResponse(api: request.asURLRequest, observer: observer)
    }
}
