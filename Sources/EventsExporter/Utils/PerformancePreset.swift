/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal protocol StoragePerformancePreset {
    /// Maximum size of a single file (in bytes).
    /// Each feature (logging, tracing, ...) serializes its objects data to that file for later upload.
    /// If last written file is too big to append next data, new file is created.
    var maxFileSize: UInt64 { get }
    /// Maximum size of data directory (in bytes).
    /// Each feature uses separate directory.
    /// If this size is exceeded, the oldest files are deleted until this limit is met again.
    var maxDirectorySize: UInt64 { get }
    /// Maximum age qualifying given file for reuse (in seconds).
    /// If recently used file is younger than this, it is reused - otherwise: new file is created.
    var maxFileAgeForWrite: TimeInterval { get }
    /// Minimum age qualifying given file for upload (in seconds).
    /// If the file is older than this, it is uploaded (and then deleted if upload succeeded).
    /// It has an arbitrary offset  (~0.5s) over `maxFileAgeForWrite` to ensure that no upload can start for the file being currently written.
    var minFileAgeForRead: TimeInterval { get }
    /// Maximum age qualifying given file for upload (in seconds).
    /// Files older than this are considered obsolete and get deleted without uploading.
    var maxFileAgeForRead: TimeInterval { get }
    /// Maximum number of serialized objects written to a single file.
    /// If number of objects in recently used file reaches this limit, new file is created for new data.
    var maxObjectsInFile: Int { get }
    /// Maximum size of serialized object data (in bytes).
    /// If serialized object data exceeds this limit, it is skipped (not written to file and not uploaded).
    var maxObjectSize: UInt64 { get }
    /// Write objects to file synchronously
    var synchronousWrite: Bool { get }
}

internal protocol UploadPerformancePreset {
    /// First upload delay (in seconds).
    /// It is used as a base value until no more files eligible for upload are found - then `defaultUploadDelay` is used as a new base.
    var initialUploadDelay: TimeInterval { get }
    /// Default uploads interval (in seconds).
    /// At runtime, the upload interval ranges from `minUploadDelay` to `maxUploadDelay` depending
    /// on delivery success or failure.
    var defaultUploadDelay: TimeInterval { get }
    /// Mininum  interval of data upload (in seconds).
    var minUploadDelay: TimeInterval { get }
    /// Maximum interval of data upload (in seconds).
    var maxUploadDelay: TimeInterval { get }
    /// If upload succeeds or fails, current interval is changed by this rate. Should be less or equal `1.0`.
    /// E.g: if rate is `0.1` then `delay` can be increased or decreased by `delay * 0.1`.
    var uploadDelayChangeRate: Double { get }
    /// Priority for upload queue
    var uploadQueuePriority: DispatchQoS { get }
}

public struct PerformancePreset: Equatable, StoragePerformancePreset, UploadPerformancePreset {
    public struct Storage: Equatable, StoragePerformancePreset {
        let maxFileSize: UInt64
        let maxDirectorySize: UInt64
        let maxFileAgeForWrite: TimeInterval
        let minFileAgeForRead: TimeInterval
        let maxFileAgeForRead: TimeInterval
        let maxObjectsInFile: Int
        let maxObjectSize: UInt64
        let synchronousWrite: Bool
        
        public init(maxFileSize: UInt64, maxDirectorySize: UInt64,
                    maxFileAgeForWrite: TimeInterval, minFileAgeForRead: TimeInterval,
                    maxFileAgeForRead: TimeInterval, maxObjectsInFile: Int,
                    maxObjectSize: UInt64, synchronousWrite: Bool)
        {
            self.maxFileSize = maxFileSize
            self.maxDirectorySize = maxDirectorySize
            self.maxFileAgeForWrite = maxFileAgeForWrite
            self.minFileAgeForRead = minFileAgeForRead
            self.maxFileAgeForRead = maxFileAgeForRead
            self.maxObjectsInFile = maxObjectsInFile
            self.maxObjectSize = maxObjectSize
            self.synchronousWrite = synchronousWrite
        }
    }
    
    public struct Upload: Equatable, UploadPerformancePreset {
        let initialUploadDelay: TimeInterval
        let defaultUploadDelay: TimeInterval
        let minUploadDelay: TimeInterval
        let maxUploadDelay: TimeInterval
        let uploadDelayChangeRate: Double
        let uploadQueuePriority: DispatchQoS
        
        public init(initialUploadDelay: TimeInterval, defaultUploadDelay: TimeInterval,
                    minUploadDelay: TimeInterval, maxUploadDelay: TimeInterval,
                    uploadDelayChangeRate: Double, uploadQueuePriority: DispatchQoS)
        {
            self.initialUploadDelay = initialUploadDelay
            self.defaultUploadDelay = defaultUploadDelay
            self.minUploadDelay = minUploadDelay
            self.maxUploadDelay = maxUploadDelay
            self.uploadDelayChangeRate = uploadDelayChangeRate
            self.uploadQueuePriority = uploadQueuePriority
        }
    }
    
    let storage: any StoragePerformancePreset
    let upload: any UploadPerformancePreset
    
    public init(storage: Storage, upload: Upload) {
        self.init(any: storage, upload: upload)
    }
    
    init(any storage: any StoragePerformancePreset, upload: any UploadPerformancePreset) {
        self.storage = storage
        self.upload = upload
    }
    
    // MARK: - StoragePerformancePreset

    var maxFileSize: UInt64 { storage.maxFileSize }
    var maxDirectorySize: UInt64 { storage.maxDirectorySize }
    var maxFileAgeForWrite: TimeInterval { storage.maxFileAgeForWrite }
    var minFileAgeForRead: TimeInterval { storage.minFileAgeForRead }
    var maxFileAgeForRead: TimeInterval { storage.maxFileAgeForRead }
    var maxObjectsInFile: Int { storage.maxObjectsInFile }
    var maxObjectSize: UInt64 { storage.maxObjectSize }
    var synchronousWrite: Bool { storage.synchronousWrite }

    // MARK: - UploadPerformancePreset

    var initialUploadDelay: TimeInterval { upload.initialUploadDelay }
    var defaultUploadDelay: TimeInterval { upload.defaultUploadDelay }
    var minUploadDelay: TimeInterval { upload.minUploadDelay }
    var maxUploadDelay: TimeInterval { upload.maxUploadDelay }
    var uploadDelayChangeRate: Double { upload.uploadDelayChangeRate }
    var uploadQueuePriority: DispatchQoS { upload.uploadQueuePriority }

    // MARK: - Predefined presets

    /// Default performance preset.
    public static let `default` = lowRuntimeImpact

    /// Performance preset optimized for low runtime impact.
    /// Minimalizes number of data requests send to the server.
    public static let lowRuntimeImpact = PerformancePreset(
        // persistence
        storage: .init(
            maxFileSize: 4 * 1_024 * 1_024, // 4MB
            maxDirectorySize: 512 * 1_024 * 1_024, // 512 MB
            maxFileAgeForWrite: 4.75,
            minFileAgeForRead: 4.75 + 0.5, // `maxFileAgeForWrite` + 0.5s margin
            maxFileAgeForRead: 18 * 60 * 60, // 18h
            maxObjectsInFile: 500,
            maxObjectSize: 256 * 1_024, // 256KB
            synchronousWrite: false
        ),
        // upload
        upload: .init(
            initialUploadDelay: 5, // postpone to not impact app launch time
            defaultUploadDelay: 5,
            minUploadDelay: 1,
            maxUploadDelay: 30,
            uploadDelayChangeRate: 0.1,
            uploadQueuePriority: .utility
        )
    )

    /// Performance preset optimized for instant data delivery.
    /// Minimalizes the time between receiving data form the user and delivering it to the server.
    public static let instantDataDelivery = PerformancePreset(
        // persistence
        storage: .init(
            maxFileSize: `default`.maxFileSize,
            maxDirectorySize: `default`.maxDirectorySize,
            maxFileAgeForWrite: 2.75,
            minFileAgeForRead: 2.75 + 0.5, // `maxFileAgeForWrite` + 0.5s margin
            maxFileAgeForRead: `default`.maxFileAgeForRead,
            maxObjectsInFile: `default`.maxObjectsInFile,
            maxObjectSize: `default`.maxObjectSize,
            synchronousWrite: false
        ),
        // upload
        upload: .init(
            initialUploadDelay: 5, // send quick to have a chance for upload in short-lived app extensions
            defaultUploadDelay: 3,
            minUploadDelay: 1,
            maxUploadDelay: 5,
            uploadDelayChangeRate: 0.5, // reduce significantly for more uploads in short-lived app extensions
            uploadQueuePriority: .userInitiated
        )
    )
    
    public static func == (lhs: PerformancePreset, rhs: PerformancePreset) -> Bool {
        lhs.storage.isEqual(to: rhs.storage) && lhs.upload.isEqual(to: rhs.upload)
    }
}

extension StoragePerformancePreset {
    func isEqual(to other: StoragePerformancePreset) -> Bool {
        maxFileSize == other.maxFileSize &&
        maxDirectorySize == other.maxDirectorySize &&
        maxFileAgeForWrite == other.maxFileAgeForWrite &&
        minFileAgeForRead == other.minFileAgeForRead &&
        maxFileAgeForRead == other.maxFileAgeForRead &&
        maxObjectsInFile == other.maxObjectsInFile &&
        maxObjectSize == other.maxObjectSize &&
        synchronousWrite == other.synchronousWrite
    }
}

extension UploadPerformancePreset {
    func isEqual(to other: UploadPerformancePreset) -> Bool {
        initialUploadDelay == other.initialUploadDelay &&
        defaultUploadDelay == other.defaultUploadDelay &&
        minUploadDelay == other.minUploadDelay &&
        maxUploadDelay == other.maxUploadDelay &&
        uploadDelayChangeRate == other.uploadDelayChangeRate &&
        uploadQueuePriority == other.uploadQueuePriority
    }
}
