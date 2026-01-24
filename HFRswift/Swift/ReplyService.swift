import Foundation

struct ReplyService {
    static let shared = ReplyService()

    // Configure your API endpoint here
    // For now, this is a placeholder. Replace with your actual endpoint.
    private let endpointURL = URL(string: "https://example.com/api/reply")!

    /// Sends a reply text to the backend via HTTP POST.
    /// - Parameters:
    ///   - text: The reply body.
    ///   - topic: The Topic context (used to include identifiers if needed).
    ///   - currentUrl: The current forum URL string (may be useful to extract ids).
    ///   - completion: Called on a background thread with success/failure.
    func sendReply(text: String, topic: Topic, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Prepare payload. Adjust keys to match your backend contract.
        let payload: [String: Any] = [
            "topicTitle": topic._aTitle ?? "",
            //"currentUrl": currentUrl,
            "message": text
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(false)
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            // Basic success heuristic: HTTP 200-299 and no transport error
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), error == nil {
                completion(true)
            } else {
                completion(false)
            }
        }
        task.resume()
    }
}
