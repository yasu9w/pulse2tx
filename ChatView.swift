//
//  ChatView.swift
//  pulse2tx
//
//  Created by Yasuhiro Matsuo on 2024/12/23.
//
import SwiftUI

struct ChatView: View {
    @State private var messages: [String] = ["Welcome to Chat!"]
    @State private var inputMessage: String = ""
    
    // OpenAI API Key
    let openAIApiKey = "***"
    
    var body: some View {
        VStack {
            List(messages, id: \.self) { message in
                let isUser = message.hasPrefix("You:")

                HStack {
                    if isUser {
                        Spacer()
                        Text(message)
                            .padding()
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(8)
                    } else {
                        Text(message)
                            .padding()
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            HStack {
                TextField("Type a message...", text: $inputMessage)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                Button(action: sendMessage) {
                    Text("Send")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding()
        }
        .navigationTitle("Chat")
    }
    
    private func sendMessage() {
        guard !inputMessage.isEmpty else { return }
        messages.append("You: \(inputMessage)")
        let userMessage = inputMessage
        inputMessage = ""
        
        Task {
            if let response = await fetchChatGPTResponse(message: userMessage) {
                DispatchQueue.main.async {
                    messages.append("AI: \(response)")」
                }
            } else {
                DispatchQueue.main.async {
                    messages.append("AI: Sorry, I couldn't process your message.")
                }
            }
        }
    }
    
    private func fetchChatGPTResponse(message: String) async -> String? {
        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        let headers = [
            "Authorization": "Bearer \(openAIApiKey)",
            "Content-Type": "application/json"
        ]
        let payload: [String: Any] = [
            "model": "gpt-4",
            "messages": [["role": "user", "content": message]],
            "max_tokens": 100
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            print("JSONSerialization error")
            return nil
        }
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = jsonData
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let debugString = String(data: data, encoding: .utf8) {
                print("OpenAI response:\n\(debugString)")
            }
            
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            return response.choices.first?.message.content
        } catch {
            print("Error fetching OpenAI response: \(error)")
            return nil
        }
    }
}

struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}
