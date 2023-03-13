import Foundation
import ScipioKit
import ClientRuntime

public struct S3StorageConfig {
    public var bucket: String
    public var region: String
    public var endpoint: URL
    public var authenticationMode: AuthenticationMode

    public init(authenticationMode: AuthenticationMode, bucket: String, region: String, endpoint: URL) {
        self.authenticationMode = authenticationMode
        self.bucket = bucket
        self.region = region
        self.endpoint = endpoint
    }

    public enum AuthenticationMode {
        case usePublicURL
        case authorized(accessKeyID: String, secretAccessKey: String)
    }

    fileprivate var ObjectStorageClientType: any ObjectStorageClient.Type {
        switch authenticationMode {
        case .usePublicURL:
            return PublicURLObjectStorageClient.self
        case .authorized:
            return APIObjectStorageClient.self
        }
    }
}

public struct S3Storage: CacheStorage {
    private let storagePrefix: String?
    private let storageClient: any ObjectStorageClient
    private let compressor = Compressor()

    public init(config: S3StorageConfig, storagePrefix: String? = nil) async throws {
        self.storageClient = try config.ObjectStorageClientType.init(storageConfig: config)
        self.storagePrefix = storagePrefix
    }

    public func existsValidCache(for cacheKey: ScipioKit.CacheKey) async throws -> Bool {
        let objectStorageKey = try constructObjectStorageKey(from: cacheKey)
        do {
            return try await storageClient.isExistObject(at: objectStorageKey)
        } catch {
            throw error
        }
    }

    public func fetchArtifacts(for cacheKey: ScipioKit.CacheKey, to destinationDir: URL) async throws {
        let objectStorageKey = try constructObjectStorageKey(from: cacheKey)
        let archiveData = try await storageClient.fetchObject(at: objectStorageKey)
        let destinationPath = destinationDir.appendingPathComponent("\(cacheKey.targetName).xcframework")
        try compressor.extract(archiveData, to: destinationPath)
    }

    public func cacheFramework(_ frameworkPath: URL, for cacheKey: ScipioKit.CacheKey) async throws {
        let data = try compressor.compress(frameworkPath)
        let objectStorageKey = try constructObjectStorageKey(from: cacheKey)
        let stream = ByteStream.from(data: data)
        try await storageClient.putObject(stream, at: objectStorageKey)
    }

    private func constructObjectStorageKey(from cacheKey: CacheKey) throws -> String {
        let frameworkName = cacheKey.targetName
        let checksum = try cacheKey.calculateChecksum()
        let archiveName = "\(checksum).aar"
        return [storagePrefix, frameworkName, archiveName]
            .compactMap { $0 }
            .joined(separator: "/")
    }
}
