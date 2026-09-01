import Foundation

/// The Lemon Squeezy License API. The three endpoints authenticate with the
/// customer's own license key, so no store secret is embedded in the app.
/// https://docs.lemonsqueezy.com/api/license-api
enum LemonSqueezy {
    private static let base = "https://api.lemonsqueezy.com/v1/licenses"

    struct LSError: LocalizedError {
        let text: String
        var errorDescription: String? { text }
    }

    /// Activate a key against this machine. On success returns the new instance id.
    static func activate(key: String, instanceName: String,
                         completion: @escaping (Result<String, Error>) -> Void) {
        post("/activate", ["license_key": key, "instance_name": instanceName]) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let json):
                if (json["activated"] as? Bool) == true,
                   let instance = json["instance"] as? [String: Any],
                   let id = instance["id"] as? String {
                    completion(.success(id))
                } else {
                    completion(.failure(LSError(text: message(from: json) ?? "That license key could not be activated.")))
                }
            }
        }
    }

    /// Validate an existing activation. Replies whether it is still valid.
    static func validate(key: String, instanceId: String,
                         completion: @escaping (Result<Bool, Error>) -> Void) {
        post("/validate", ["license_key": key, "instance_id": instanceId]) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let json): completion(.success((json["valid"] as? Bool) == true))
            }
        }
    }

    /// Release this machine's activation (so the license can move to another Mac).
    static func deactivate(key: String, instanceId: String,
                           completion: @escaping (Result<Bool, Error>) -> Void) {
        post("/deactivate", ["license_key": key, "instance_id": instanceId]) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let json): completion(.success((json["deactivated"] as? Bool) == true))
            }
        }
    }

    // MARK: - transport

    private static func message(from json: [String: Any]) -> String? {
        if let e = json["error"] as? String, !e.isEmpty { return e }
        return nil
    }

    private static func post(_ path: String, _ params: [String: String],
                             completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: base + path) else {
            completion(.failure(LSError(text: "Bad URL"))); return
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params
            .map { "\($0.key)=\(encode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error { completion(.failure(error)); return }
            guard let data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                completion(.failure(LSError(text: "Could not reach the license server. Check your connection.")))
                return
            }
            completion(.success(json))
        }.resume()
    }

    private static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
