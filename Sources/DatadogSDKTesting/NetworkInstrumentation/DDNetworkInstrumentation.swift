/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

struct NetworkRequestState {
    var request: URLRequest?
    var dataProcessed: Data?
    var response: URLResponse?
}

private var idKey: Void?

class DDNetworkInstrumentation {
    private var requestMap = [String: NetworkRequestState]()
    
    var excludedURLs = Set<String>()
    
    var recordPayload: Bool {
        return DDTestMonitor.instance?.recordPayload ?? false
    }
    
    private var injectHeaders: Bool {
        return DDTestMonitor.instance?.injectHeaders ?? false
    }
    
    private let queue = DispatchQueue(label: "com.datadoghq.ddnetworkinstrumentation")
    
    static var instrumentedKey = "com.datadoghq.instrumentedCall"
    
    init() {
        self.injectInNSURLClasses()
        excludedURLs = ["https://mobile-http-intake.logs",
                        "https://public-trace-http-intake.logs.",
                        "https://rum-http-intake.logs."]
    }
    
    func injectInNSURLClasses() {
        let selectors = [
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:)),
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:completionHandler:)),
            #selector(URLSessionDataDelegate.urlSession(_:task:didCompleteWithError:)),
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didBecome:)! as (URLSessionDataDelegate) -> (URLSession, URLSessionDataTask, URLSessionDownloadTask) -> Void),
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didBecome:)! as (URLSessionDataDelegate) -> (URLSession, URLSessionDataTask, URLSessionStreamTask) -> Void)
        ]
        
        let classes = DDNetworkInstrumentation.objc_getClassList()
        classes.forEach {
            guard $0 != Self.self else { return }
            var selectorFound = false
            var methodCount: UInt32 = 0
            guard let methodList = class_copyMethodList($0, &methodCount) else { return }
            
            for i in 0..<Int(methodCount) {
                for j in 0..<selectors.count {
                    if method_getName(methodList[i]) == selectors[j] {
                        selectorFound = true
                        injectIntoDelegateClass(cls: $0)
                        break
                    }
                }
                if selectorFound {
                    break
                }
            }
        }
        injectIntoNSURLSessionCreateTaskMethods()
        injectIntoNSURLSessionCreateTaskWithParameterMethods()
        injectIntoNSURLSessionAsyncDataAndDownloadTaskMethods()
        injectIntoNSURLSessionAsyncUploadTaskMethods()
    }
    
    func injectIntoDelegateClass(cls: AnyClass) {
        // Sessions
        injectTaskDidReceiveDataIntoDelegateClass(cls: cls)
        injectTaskDidReceiveResponseIntoDelegateClass(cls: cls)
        injectTaskDidCompleteWithErrorIntoDelegateClass(cls: cls)
        injectRespondsToSelectorIntoDelegateClass(cls: cls)
        
        // Data tasks
        injectDataTaskDidBecomeDownloadTaskIntoDelegateClass(cls: cls)
    }
    
    func injectIntoNSURLSessionCreateTaskMethods() {
        let cls = URLSession.self
        [
            #selector(URLSession.dataTask(with:) as (URLSession) -> (URLRequest) -> URLSessionDataTask),
            #selector(URLSession.dataTask(with:) as (URLSession) -> (URL) -> URLSessionDataTask),
            #selector(URLSession.uploadTask(withStreamedRequest:)),
            #selector(URLSession.downloadTask(with:) as (URLSession) -> (URLRequest) -> URLSessionDownloadTask),
            #selector(URLSession.downloadTask(with:) as (URLSession) -> (URL) -> URLSessionDownloadTask),
            #selector(URLSession.downloadTask(withResumeData:))
        ].forEach {
            let selector = $0
            guard let original = class_getInstanceMethod(cls, selector) else {
                print("injectInto \(selector.description) failed")
                return
            }
            var originalIMP: IMP?
            let sessionTaskId = UUID().uuidString
            
            let block: @convention(block) (URLSession, AnyObject) -> URLSessionTask = { session, argument in
                if let url = argument as? URL,
                   self.injectHeaders == true {
                    let request = URLRequest(url: url)
                    if selector == #selector(URLSession.dataTask(with:) as (URLSession) -> (URL) -> URLSessionDataTask) {
                        return session.dataTask(with: request)
                    } else {
                        return session.downloadTask(with: request)
                    }
                }
                
                let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (URLSession, Selector, Any) -> URLSessionDataTask).self)
                var task: URLSessionTask
                
                if let request = argument as? URLRequest, objc_getAssociatedObject(argument, &idKey) == nil {
                    let instrumentedRequest = self.instrumentedRequest(for: request)
                    task = castedIMP(session, selector, instrumentedRequest)
                    DDNetworkActivityLogger.log(request: instrumentedRequest, sessionTaskId: sessionTaskId)
                } else {
                    task = castedIMP(session, selector, argument)
                    if objc_getAssociatedObject(argument, &idKey) == nil,
                       let currentRequest = task.currentRequest {
                        DDNetworkActivityLogger.log(request: currentRequest, sessionTaskId: sessionTaskId)
                    }
                }
                self.setIdKey(value: sessionTaskId, for: task)
                return task
            }
            let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
            originalIMP = method_setImplementation(original, swizzledIMP)
        }
    }
    
    func injectIntoNSURLSessionCreateTaskWithParameterMethods() {
        let cls = URLSession.self
        [
            #selector(URLSession.uploadTask(with:from:)),
            #selector(URLSession.uploadTask(with:fromFile:))
        ].forEach {
            let selector = $0
            guard let original = class_getInstanceMethod(cls, selector) else {
                print("injectInto \(selector.description) failed")
                return
            }
            var originalIMP: IMP?
            let sessionTaskId = UUID().uuidString
            
            let block: @convention(block) (URLSession, URLRequest, AnyObject) -> URLSessionTask = { session, request, argument in
                let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (URLSession, Selector, URLRequest, AnyObject) -> URLSessionDataTask).self)
                let instrumentedRequest = self.instrumentedRequest(for: request)
                let task = castedIMP(session, selector, instrumentedRequest, argument)
                DDNetworkActivityLogger.log(request: instrumentedRequest, sessionTaskId: sessionTaskId)
                self.setIdKey(value: sessionTaskId, for: task)
                return task
            }
            let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
            originalIMP = method_setImplementation(original, swizzledIMP)
        }
    }
    
    func injectIntoNSURLSessionAsyncDataAndDownloadTaskMethods() {
        let cls = URLSession.self
        [
            #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask),
            #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask),
            #selector(URLSession.downloadTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask),
            #selector(URLSession.downloadTask(with:completionHandler:) as (URLSession) -> (URL, @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask),
            #selector(URLSession.downloadTask(withResumeData:completionHandler:))
        ].forEach {
            let selector = $0
            guard let original = class_getInstanceMethod(cls, selector) else {
                print("injectInto \(selector.description) failed")
                return
            }
            var originalIMP: IMP?
            let sessionTaskId = UUID().uuidString
            
            let block: @convention(block) (URLSession, AnyObject, @escaping (Any?, URLResponse?, Error?) -> Void) -> URLSessionTask = { session, argument, completion in
                if let url = argument as? URL,
                   self.injectHeaders == true {
                    let request = URLRequest(url: url)
                    
                    if selector == #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask) {
                        return session.dataTask(with: request, completionHandler: completion)
                    } else {
                        return session.downloadTask(with: request, completionHandler: completion)
                    }
                }
                
                let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (URLSession, Selector, Any, @escaping (Any?, URLResponse?, Error?) -> Void) -> URLSessionDataTask).self)
                var task: URLSessionTask
                
                var completionBlock = completion
                if objc_getAssociatedObject(argument, &idKey) == nil {
                    let completionWrapper: (Any?, URLResponse?, Error?) -> Void = { object, response, error in
                        if error != nil {
                            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                            DDNetworkActivityLogger.log(error: error!, dataOrFile: object, statusCode: status, sessionTaskId: sessionTaskId)
                        } else {
                            if let response = response {
                                DDNetworkActivityLogger.log(response: response, dataOrFile: object, sessionTaskId: sessionTaskId)
                            }
                        }
                        completion(object, response, error)
                    }
                    completionBlock = completionWrapper
                }
                
                if let request = argument as? URLRequest, objc_getAssociatedObject(argument, &idKey) == nil {
                    let instrumentedRequest = self.instrumentedRequest(for: request)
                    task = castedIMP(session, selector, instrumentedRequest, completionBlock)
                    DDNetworkActivityLogger.log(request: instrumentedRequest, sessionTaskId: sessionTaskId)
                } else {
                    task = castedIMP(session, selector, argument, completionBlock)
                    if objc_getAssociatedObject(argument, &idKey) == nil,
                       let currentRequest = task.currentRequest {
                        DDNetworkActivityLogger.log(request: currentRequest, sessionTaskId: sessionTaskId)
                    }
                }
                self.setIdKey(value: sessionTaskId, for: task)
                return task
            }
            let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
            originalIMP = method_setImplementation(original, swizzledIMP)
        }
    }
    
    func injectIntoNSURLSessionAsyncUploadTaskMethods() {
        let cls = URLSession.self
        [
            #selector(URLSession.uploadTask(with:from:completionHandler:)),
            #selector(URLSession.uploadTask(with:fromFile:completionHandler:))
        ].forEach {
            let selector = $0
            guard let original = class_getInstanceMethod(cls, selector) else {
                print("injectInto \(selector.description) failed")
                return
            }
            var originalIMP: IMP?
            let sessionTaskId = UUID().uuidString
            
            let block: @convention(block) (URLSession, URLRequest, AnyObject, @escaping (Any?, URLResponse?, Error?) -> Void) -> URLSessionTask = { session, request, argument, completion in
                
                let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (URLSession, Selector, URLRequest, AnyObject, @escaping (Any?, URLResponse?, Error?) -> Void) -> URLSessionDataTask).self)
                
                var completionBlock = completion
                if objc_getAssociatedObject(argument, &idKey) == nil {
                    let completionWrapper: (Any?, URLResponse?, Error?) -> Void = { object, response, error in
                        if error != nil {
                            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                            DDNetworkActivityLogger.log(error: error!, dataOrFile: object, statusCode: status, sessionTaskId: sessionTaskId)
                        } else {
                            if let response = response {
                                DDNetworkActivityLogger.log(response: response, dataOrFile: object, sessionTaskId: sessionTaskId)
                            }
                        }
                        completion(object, response, error)
                    }
                    completionBlock = completionWrapper
                }
                
                let instrumentedRequest = self.instrumentedRequest(for: request)
                let task = castedIMP(session, selector, instrumentedRequest, argument, completionBlock)
                DDNetworkActivityLogger.log(request: instrumentedRequest, sessionTaskId: sessionTaskId)
                
                self.setIdKey(value: sessionTaskId, for: task)
                return task
            }
            let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
            originalIMP = method_setImplementation(original, swizzledIMP)
        }
    }
    
    // Delegate methods
    func injectTaskDidReceiveDataIntoDelegateClass(cls: AnyClass) {
        let selector = #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:))
        guard let original = class_getInstanceMethod(cls, selector) else {
            return
        }
        var originalIMP: IMP?
        let block: @convention(block) (Any, URLSession, URLSessionDataTask, Data) -> Void = { object, session, dataTask, data in
            if objc_getAssociatedObject(session, &idKey) == nil {
                self.urlSession(session, dataTask: dataTask, didReceive: data)
            }
            let key = String(selector.hashValue)
            objc_setAssociatedObject(session, key, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (Any, Selector, URLSession, URLSessionDataTask, Data) -> Void).self)
            castedIMP(object, selector, session, dataTask, data)
            objc_setAssociatedObject(session, key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        originalIMP = method_setImplementation(original, swizzledIMP)
    }
    
    func injectTaskDidReceiveResponseIntoDelegateClass(cls: AnyClass) {
        let selector = #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:completionHandler:))
        guard let original = class_getInstanceMethod(cls, selector) else {
            return
        }
        var originalIMP: IMP?
        let block: @convention(block) (Any, URLSession, URLSessionDataTask, URLResponse, @escaping (URLSession.ResponseDisposition) -> Void) -> Void = { object, session, dataTask, response, completion in
            if objc_getAssociatedObject(session, &idKey) == nil {
                self.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completion)
                completion(.allow)
            }
            let key = String(selector.hashValue)
            objc_setAssociatedObject(session, key, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (Any, Selector, URLSession, URLSessionDataTask, URLResponse, @escaping (URLSession.ResponseDisposition) -> Void) -> Void).self)
            castedIMP(object, selector, session, dataTask, response, completion)
            objc_setAssociatedObject(session, key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        originalIMP = method_setImplementation(original, swizzledIMP)
    }
    
    func injectTaskDidCompleteWithErrorIntoDelegateClass(cls: AnyClass) {
        let selector = #selector(URLSessionDataDelegate.urlSession(_:task:didCompleteWithError:))
        guard let original = class_getInstanceMethod(cls, selector) else {
            return
        }
        var originalIMP: IMP?
        let block: @convention(block) (Any, URLSession, URLSessionTask, Error?) -> Void = { object, session, task, error in
            if objc_getAssociatedObject(session, &idKey) == nil {
                self.urlSession(session, task: task, didCompleteWithError: error)
            }
            let key = String(selector.hashValue)
            objc_setAssociatedObject(session, key, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (Any, Selector, URLSession, URLSessionTask, Error?) -> Void).self)
            castedIMP(object, selector, session, task, error)
            objc_setAssociatedObject(session, key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        originalIMP = method_setImplementation(original, swizzledIMP)
    }
    
    func injectRespondsToSelectorIntoDelegateClass(cls: AnyClass) {
        let selector = #selector(NSObject.responds(to:))
        guard let original = class_getInstanceMethod(cls, selector),
              DDNetworkInstrumentation.instanceRespondsAndImplements(cls: cls, selector: selector) else {
            return
        }

        var originalIMP: IMP?
        let block: @convention(block) (Any, Selector) -> Bool = { object, respondsTo in
            if respondsTo == #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:completionHandler:)) {
                return true
            }
            let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (Any, Selector, Selector) -> Bool).self)
            return castedIMP(object, selector, respondsTo)
        }
        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        originalIMP = method_setImplementation(original, swizzledIMP)
    }
    
    func injectDataTaskDidBecomeDownloadTaskIntoDelegateClass(cls: AnyClass) {
        let selector = #selector(URLSessionDataDelegate.urlSession(_:dataTask:didBecome:)! as (URLSessionDataDelegate) -> (URLSession, URLSessionDataTask, URLSessionDownloadTask) -> Void)
        guard let original = class_getInstanceMethod(cls, selector) else {
            return
        }
        var originalIMP: IMP?
        let block: @convention(block) (Any, URLSession, URLSessionDataTask, URLSessionDownloadTask) -> Void = { object, session, dataTask, downloadTask in
            if objc_getAssociatedObject(session, &idKey) == nil {
                self.urlSession(session, dataTask: dataTask, didBecome: downloadTask)
            }
            let key = String(selector.hashValue)
            objc_setAssociatedObject(session, key, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (Any, Selector, URLSession, URLSessionDataTask, URLSessionDownloadTask) -> Void).self)
            castedIMP(object, selector, session, dataTask, downloadTask)
            objc_setAssociatedObject(session, key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        originalIMP = method_setImplementation(original, swizzledIMP)
    }
    
    // URLSessionTask methods
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard self.recordPayload else { return }
        let dataCopy = data
        queue.async {
            let taskId = self.idKeyForTask(dataTask)
            if (self.requestMap[taskId]?.request) != nil {
                var requestState = self.requestState(for: taskId)
                requestState.dataProcessed?.append(dataCopy)
            }
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard self.recordPayload else { return }
        queue.async {
            let taskId = self.idKeyForTask(dataTask)
            if (self.requestMap[taskId]?.request) != nil {
                var requestState = self.requestState(for: taskId)
                if response.expectedContentLength < 0 {
                    requestState.dataProcessed = Data()
                } else {
                    requestState.dataProcessed = Data(capacity: Int(response.expectedContentLength))
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskId = self.idKeyForTask(task)
        if (self.requestMap[taskId]?.request) != nil {
            let requestState = self.requestState(for: taskId)
            if let error = error {
                let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
                DDNetworkActivityLogger.log(error: error, dataOrFile: requestState.dataProcessed, statusCode: status, sessionTaskId: taskId)
            } else if let response = task.response {
                DDNetworkActivityLogger.log(response: response, dataOrFile: requestState.dataProcessed, sessionTaskId: taskId)
            }
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        queue.async {
            let id = self.idKeyForTask(dataTask)
            self.setIdKey(value: id, for: downloadTask)
        }
    }
    
    // Helpers
    func idKeyForTask(_ task: URLSessionTask) -> String {
        var id = objc_getAssociatedObject(task, &idKey) as? String
        if id == nil {
            id = UUID().uuidString
            objc_setAssociatedObject(task, &idKey, id, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        return id!
    }
    
    func setIdKey(value: String, for task: URLSessionTask) {
        objc_setAssociatedObject(task, &idKey, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    func requestState(for id: String) -> NetworkRequestState {
        var state = requestMap[id]
        if state == nil {
            state = NetworkRequestState()
            requestMap[id] = state
        }
        return state!
    }
    
    func instrumentedRequest(for request: URLRequest) -> URLRequest {
        guard injectHeaders == true,
              let tracer = DDTestMonitor.instance?.tracer,
              tracer.activeSpan != nil,
              !excludes(request.url) else {
            return request
        }
        var instrumentedRequest = request
        objc_setAssociatedObject(instrumentedRequest, &DDNetworkInstrumentation.instrumentedKey, true, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        var traceHeaders = tracer.tracePropagationHTTPHeaders()
        if let originalHeaders = request.allHTTPHeaderFields {
            traceHeaders.merge(originalHeaders) { _, new in new }
        }
        instrumentedRequest.allHTTPHeaderFields = traceHeaders
        return instrumentedRequest
    }
    
    func excludes(_ url: URL?) -> Bool {
        if let absoluteString = url?.absoluteString {
            return excludedURLs.contains {
                absoluteString.starts(with: $0)
            }
        }
        return true
    }
    
    static func objc_getClassList() -> [AnyClass] {
        let expectedClassCount = ObjectiveC.objc_getClassList(nil, 0)
        let allClasses = UnsafeMutablePointer<AnyClass>.allocate(capacity: Int(expectedClassCount))
        let autoreleasingAllClasses = AutoreleasingUnsafeMutablePointer<AnyClass>(allClasses)
        let actualClassCount: Int32 = ObjectiveC.objc_getClassList(autoreleasingAllClasses, expectedClassCount)
        
        var classes = [AnyClass]()
        for i in 0..<actualClassCount {
            classes.append(allClasses[Int(i)])
        }
        allClasses.deallocate()
        return classes
    }

    static func instanceRespondsAndImplements(cls: AnyClass, selector: Selector) -> Bool {
        var implements = false
        if cls.instancesRespond(to: selector) {
            var methodCount: UInt32 = 0
            let methodList = class_copyMethodList(cls, &methodCount)
            defer {
                free(methodList)
            }
            if let methodList = methodList, methodCount > 0 {
                enumerateCArray(array: methodList, count: methodCount) { _, m in
                    let sel = method_getName(m)
                    if sel == selector {
                        implements = true
                        return
                    }
                }
            }
        }
        return implements
    }

    private static func enumerateCArray<T>(array: UnsafePointer<T>, count: UInt32, f: (UInt32, T) -> ()) {
        var ptr = array
        for i in 0..<count {
            f(i, ptr.pointee)
            ptr = ptr.successor()
        }
    }
}
