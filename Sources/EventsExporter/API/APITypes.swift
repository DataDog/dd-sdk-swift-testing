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

protocol APICommonData {
    associatedtype Meta
    associatedtype Attributes: APIAttributes

    var id: String? { get }
    var type: String { get }
    var attributes: Attributes { get }
}

protocol APIRequestData: APICommonData, Encodable where Attributes: Encodable, Meta: Encodable {}
protocol APIResponseData: APICommonData, Decodable where Attributes: Decodable, Meta: Decodable {
    var isTypeValid: Bool { get }
    func isIdValid(_ id: String?) -> Bool
}

extension APIResponseData {
    var isTypeValid: Bool { type == Attributes.apiType }
    func isIdValid(_ id: String?) -> Bool { id == self.id }
}

extension Array: APIAttributes where Element: APIAttributes {
    static var apiType: String { Element.apiType }
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

internal protocol APIService {
    var endpoint: Endpoint { get set }
    var headers: [HTTPHeader] { get set }
    var encoder: JSONEncoder { get set }
    var decoder: JSONDecoder { get set }

    var endpointURLs: Set<URL> { get }

    init(config: APIServiceConfig, httpClient: HTTPClient, log: Logger)
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
extension APIData: APIResponseData where Meta: Decodable, Attributes: Decodable {}

struct APIVoidMeta: APIVoidValue, Codable {
    static var void: Self { .init() }
}

struct APIEnvelope<Data: APICommonData> {
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

internal enum APICallError: Error {
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

    var isUnauthorized: Bool {
        switch self {
        case .httpError(code: 401, headers: _, body: _),
             .httpError(code: 403, headers: _, body: _):
            return true
        default: return false
        }
    }
}

internal struct APIServiceConfig {
    let serviceName: String
    let environment: String
    let applicationName: String
    let version: String
    let device: Device
    let hostname: String?

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
                appVersion: version,
                device: device
            ),
            .apiKeyHeader(apiKey: apiKey),
            .traceIDHeader(traceID: clientId),
            .parentSpanIDHeader(parentSpanID: clientId),
            .samplingPriorityHeader()
        ] + (payloadCompression ? [.contentEncodingHeader(contentEncoding: .deflate)] : []) +
            (hostname != nil ? [.hostnameHeader(hostname: hostname!)] : [])
    }

    init(serviceName: String, environment: String,
         applicationName: String, version: String,
         device: Device, hostname: String?, apiKey: String,
         endpoint: Endpoint, clientId: String, payloadCompression: Bool)
    {
        self.serviceName = serviceName
        self.environment = environment
        self.applicationName = applicationName
        self.version = version
        self.device = device
        self.hostname = hostname
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.clientId = clientId
        self.payloadCompression = payloadCompression
    }
}

extension JSONEncoder {
    internal static let apiEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.nonConformingFloatEncodingStrategy = .throw
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
        decoder.dateDecodingStrategy = .iso8601
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

extension HTTPClient {
    func call<Request, Response>(
        _ call: APICall<Request, Response>.Type,
        url: URL, meta: Request.Meta, data: Request,
        headers: [HTTPHeader]? = nil,
        coders: (JSONEncoder, JSONDecoder) = (.apiEncoder, .apiDecoder)
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

        let body: Data
        do {
            body = try await sendWithResponse(request: request)
        } catch let err {
            throw APICallError(from: err)
        }
        return try call.response(from: body, requestId: requestId, coder: coders.1)
    }

    func call<Request, Response>(
        _ call: APICall<Request, Response>.Type,
        url: URL, data: Request,
        headers: [HTTPHeader]? = nil,
        coders: (JSONEncoder, JSONDecoder) = (.apiEncoder, .apiDecoder)
    ) async throws(APICallError) -> APIEnvelope<Response>
    where Request: APIRequestData, Response: APIResponseData, Request.Meta: APIVoidValue
    {
        try await self.call(call, url: url, meta: .void, data: data, headers: headers, coders: coders)
    }
}
