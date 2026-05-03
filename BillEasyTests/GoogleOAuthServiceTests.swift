import AuthenticationServices
import Foundation
import Testing
@testable import BillEasy

@Suite(.serialized)
struct GoogleOAuthServiceTests {

    @Test("GoogleOAuthService completes native code flow and returns validated identity")
    @MainActor
    func completesCodeFlow() async throws {
        let captured = LockedGoogleAuthorizationCapture()
        let runner = GoogleOAuthAuthorizationRunnerMock { request, _ in
            let components = try #require(URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false))
            let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

            #expect(items["client_id"] == "ios-client.apps.googleusercontent.com")
            #expect(items["response_type"] == "code")
            #expect(items["scope"] == "openid email profile")
            #expect(items["audience"] == "web-client.apps.googleusercontent.com")
            #expect(items["redirect_uri"] == "br.com.billeasy:/oauth2redirect/google")
            #expect(items["code_challenge_method"] == "S256")

            captured.state = items["state"]
            captured.nonce = items["nonce"]

            return try #require(URL(string: "br.com.billeasy:/oauth2redirect/google?code=oauth-code-123&state=\(items["state"] ?? "")"))
        }

        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.absoluteString == "https://oauth2.googleapis.com/token")
            #expect(request.httpMethod == "POST")

            let body = try bodyData(from: request)
            let bodyString = try #require(String(data: body, encoding: .utf8))
            #expect(bodyString.contains("audience=web-client.apps.googleusercontent.com"))
            #expect(bodyString.contains("client_id=ios-client.apps.googleusercontent.com"))
            #expect(bodyString.contains("code=oauth-code-123"))
            #expect(bodyString.contains("grant_type=authorization_code"))
            #expect(bodyString.contains("redirect_uri=br.com.billeasy:%2Foauth2redirect%2Fgoogle"))
            #expect(bodyString.contains("code_verifier="))

            let nonce = try #require(captured.nonce)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let payload = """
            {
              "access_token":"access-token-123",
              "token_type":"Bearer",
              "id_token":"\(makeJWT(payload: [
                "sub": "google-123",
                "email": "samuel@example.com",
                "name": "Samuel Jammes",
                "nonce": nonce,
                "aud": "web-client.apps.googleusercontent.com",
                "azp": "ios-client.apps.googleusercontent.com",
                "picture": "https://lh3.googleusercontent.com/avatar-123"
              ]))"
            }
            """.data(using: .utf8)!
            return (response, payload)
        }

        let service = GoogleOAuthService(
            configuration: GoogleOAuthConfiguration(
                clientID: "ios-client.apps.googleusercontent.com",
                serverClientID: "web-client.apps.googleusercontent.com",
                redirectScheme: "br.com.billeasy",
                redirectPath: "/oauth2redirect/google"
            ),
            session: session,
            authorizationRunner: runner
        )

        let identity = try await service.authenticate(presentationAnchor: nil)
        #expect(identity.googleID == "google-123")
        #expect(identity.email == "samuel@example.com")
        #expect(identity.name == "Samuel Jammes")
        #expect(identity.avatarURL == "https://lh3.googleusercontent.com/avatar-123")
        #expect(identity.idToken.isEmpty == false)
    }

    @Test("GoogleOAuthService busca a foto no userinfo quando o id_token não traz picture")
    @MainActor
    func fetchesPictureFromUserInfoWhenNeeded() async throws {
        let captured = LockedGoogleAuthorizationCapture()
        let runner = GoogleOAuthAuthorizationRunnerMock { request, _ in
            let components = try #require(URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false))
            let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            captured.state = items["state"]
            captured.nonce = items["nonce"]
            return try #require(URL(string: "br.com.billeasy:/oauth2redirect/google?code=oauth-code-456&state=\(items["state"] ?? "")"))
        }

        let session = makeMockSession { request in
            let url = try #require(request.url)

            if url.absoluteString == "https://oauth2.googleapis.com/token" {
                let nonce = try #require(captured.nonce)
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                let payload = """
                {
                  "access_token":"access-token-456",
                  "token_type":"Bearer",
                  "id_token":"\(makeJWT(payload: [
                    "sub": "google-456",
                    "email": "samuel@example.com",
                    "name": "Samuel Jammes",
                    "nonce": nonce,
                    "aud": "web-client.apps.googleusercontent.com",
                    "azp": "ios-client.apps.googleusercontent.com"
                  ]))"
                }
                """.data(using: .utf8)!
                return (response, payload)
            }

            #expect(url.absoluteString == "https://www.googleapis.com/oauth2/v3/userinfo")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token-456")
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, #"{"picture":"https://lh3.googleusercontent.com/avatar-456"}"#.data(using: .utf8)!)
        }

        let service = GoogleOAuthService(
            configuration: GoogleOAuthConfiguration(
                clientID: "ios-client.apps.googleusercontent.com",
                serverClientID: "web-client.apps.googleusercontent.com",
                redirectScheme: "br.com.billeasy",
                redirectPath: "/oauth2redirect/google"
            ),
            session: session,
            authorizationRunner: runner
        )

        let identity = try await service.authenticate(presentationAnchor: nil)
        #expect(identity.avatarURL == "https://lh3.googleusercontent.com/avatar-456")
    }

    @Test("GoogleOAuthService rejects callback with invalid state")
    @MainActor
    func rejectsInvalidState() async {
        let runner = GoogleOAuthAuthorizationRunnerMock { _, _ in
            try #require(URL(string: "br.com.billeasy:/oauth2redirect/google?code=oauth-code-123&state=estado-invalido"))
        }

        let service = GoogleOAuthService(
            configuration: GoogleOAuthConfiguration(
                clientID: "ios-client.apps.googleusercontent.com",
                serverClientID: "web-client.apps.googleusercontent.com",
                redirectScheme: "br.com.billeasy",
                redirectPath: "/oauth2redirect/google"
            ),
            session: makeMockSession { _ in
                throw URLError(.badServerResponse)
            },
            authorizationRunner: runner
        )

        do {
            _ = try await service.authenticate(presentationAnchor: nil)
            Issue.record("Expected invalid state to abort the Google flow.")
        } catch let error as GoogleOAuthServiceError {
            if case .invalidState = error {
                // Expected.
            } else {
                Issue.record("Expected invalidState, got: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        GoogleOAuthMockURLProtocol.handler = handler

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GoogleOAuthMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            throw URLError(.zeroByteResource)
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufferSize)
            if readCount < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeRawData)
            }
            if readCount == 0 {
                break
            }
            data.append(buffer, count: readCount)
        }

        return data
    }

    private func makeJWT(payload: [String: String]) -> String {
        let header = ["alg": "none", "typ": "JWT"]
        let headerData = try! JSONSerialization.data(withJSONObject: header)
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        let signature = "signature"
        return [
            headerData.base64URLEncodedString(),
            payloadData.base64URLEncodedString(),
            signature
        ].joined(separator: ".")
    }
}

private final class GoogleOAuthAuthorizationRunnerMock: GoogleOAuthAuthorizationRunning {
    private let handler: @MainActor (GoogleOAuthAuthorizationRequest, ASPresentationAnchor?) throws -> URL

    init(
        handler: @escaping @MainActor (GoogleOAuthAuthorizationRequest, ASPresentationAnchor?) throws -> URL
    ) {
        self.handler = handler
    }

    @MainActor
    func authorize(using request: GoogleOAuthAuthorizationRequest, presentationAnchor: ASPresentationAnchor?) async throws -> URL {
        try handler(request, presentationAnchor)
    }
}

private final class GoogleOAuthMockURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class LockedGoogleAuthorizationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: (state: String?, nonce: String?) = (nil, nil)

    var state: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage.state
        }
        set {
            lock.lock()
            storage.state = newValue
            lock.unlock()
        }
    }

    var nonce: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage.nonce
        }
        set {
            lock.lock()
            storage.nonce = newValue
            lock.unlock()
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
