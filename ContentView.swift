//
//  ContentView.swift
//  pulse2tx
//
//  Created by Yasuhiro Matsuo on 2024/12/17.
//
import SwiftUI
import HealthKit

enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
            return
        }

        if let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }

        if let n = try? container.decode(Double.self) {
            self = .number(n)
            return
        }

        if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
            return
        }

        if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
            return
        }

        throw DecodingError.typeMismatch(JSONValue.self, DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Unknown JSON structure"
        ))
    }
}

struct TransactionData: Identifiable {
    let id = UUID()
    let signature: String
    let timestamp: Date
    var heartRate: Int?
}

struct SolanaSignatureInfo: Decodable {
    let signature: String
    let slot: Int
    let blockTime: Int?
    let err: JSONValue?
    let memo: String?
}

struct SolanaRPCErrorInfo: Decodable {
    let code: Int
    let message: String
}

struct SolanaRPCResponse<ResultType: Decodable>: Decodable {
    let jsonrpc: String
    let id: Int
    let result: ResultType?
    let error: SolanaRPCErrorInfo?
}

struct ContentView: View {
    @State private var publicKey: String = ""
    @State private var transactions: [TransactionData] = []
    @State private var isLoading: Bool = false
    @State private var isLoadingMore: Bool = false
    @State private var healthAuthorized = false
    @State private var lastFetchedSignature: String? = nil
    
    @State private var showChatView: Bool = false
    
    let apiKey = "***"
    var rpcURL: URL {
        var urlComponents = URLComponents(string: "https://mainnet.helius-rpc.com/")!
        urlComponents.queryItems = [URLQueryItem(name: "api-key", value: apiKey)]
        return urlComponents.url!
    }
    
    let transactionLimit = 30
    private let healthStore = HKHealthStore()
    
    private var dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 153/255, green: 69/255, blue: 255/255),
                        Color(red: 20/255, green: 241/255, blue: 149/255)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 20) {
                    Spacer().frame(height: 20)
                    
                    Text("Enter your Solana public key")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)

                    TextField("e.g. 9abc...", text: $publicKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: 300)
                        .padding(.horizontal)

                    Button(action: {
                        Task { await initialFetch() }
                    }) {
                        Text("Fetch Data")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(publicKey.isEmpty ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(isLoading || publicKey.isEmpty)
                    .frame(maxWidth: 300)

                    if isLoading && transactions.isEmpty {
                        ProgressView("Loading...")
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(.white)
                    } else if transactions.isEmpty {
                        Text("No transactions found")
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        HStack {
                            Text("Date/Time")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .frame(width: 100, alignment: .leading)
                            
                            Text("Signature")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .frame(width: 150, alignment: .leading)
                            
                            Text("BPM")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .frame(width: 60, alignment: .trailing)
                        }
                        .padding(.horizontal)
                        
                        List {
                            ForEach(transactions.indices, id: \.self) { i in
                                let tx = transactions[i]
                                HStack {
                                    Text(tx.timestamp, formatter: dateFormatter)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .frame(width: 100, alignment: .leading)
                                    
                                    let truncatedSignature = tx.signature.count > 6
                                        ? String(tx.signature.prefix(6)) + "..."
                                        : tx.signature
                                    
                                    Link(truncatedSignature, destination: URL(string: "https://solscan.io/tx/\(tx.signature)")!)
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                        .underline()
                                        .frame(width: 150, alignment: .leading)
                                    
                                    Text(tx.heartRate != nil ? "\(tx.heartRate!) bpm" : "No Data")
                                        .font(.subheadline)
                                        .foregroundColor(tx.heartRate != nil ? .red : .secondary)
                                        .frame(width: 60, alignment: .trailing)
                                }
                                .padding(.vertical, 4)
                                .onAppear {
                                    if i == transactions.count - 1 {
                                        Task {
                                            await loadMoreIfNeeded()
                                        }
                                    }
                                }
                            }
                            
                            if isLoadingMore {
                                ProgressView("Loading more...")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .listStyle(.plain)
                        .padding(.horizontal)
                        .frame(maxHeight: .infinity)
                    }

                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .navigationTitle("Pulse2Tx")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showChatView = true
                    }) {
                        Text("Chat")
                            .foregroundColor(.white)
                    }
                }
            }
            .navigationDestination(isPresented: $showChatView) {
                ChatView()
            }
            .onAppear {
                requestHealthAuthorization()
            }
        }
    }
    
    private func requestHealthAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }

        healthStore.requestAuthorization(toShare: [], read: [heartRateType]) { success, error in
            DispatchQueue.main.async {
                self.healthAuthorized = success && error == nil
            }
        }
    }
    
    private func initialFetch() async {
        guard !publicKey.isEmpty else { return }
        isLoading = true
        transactions = []
        lastFetchedSignature = nil
        
        await fetchAndProcessData(limit: transactionLimit, before: nil)
        
        DispatchQueue.main.async {
            self.isLoading = false
        }
    }
    
    private func loadMoreIfNeeded() async {
        guard !isLoading && !isLoadingMore else { return }
        guard let lastSig = lastFetchedSignature else { return }
        
        isLoadingMore = true
        await fetchAndProcessData(limit: transactionLimit, before: lastSig)
        isLoadingMore = false
    }
    
    private func fetchAndProcessData(limit: Int, before: String?) async {
        guard let signatureInfos = await fetchRecentTransactions(for: publicKey, limit: limit, before: before) else {
            return
        }

        let tempTx = signatureInfos.map { info -> TransactionData in
            let blockTime = info.blockTime != nil ? Date(timeIntervalSince1970: Double(info.blockTime!)) : Date()
            return TransactionData(signature: info.signature, timestamp: blockTime, heartRate: nil)
        }

        var updatedTxData = [TransactionData]()
        for tx in tempTx {
            let hr = await fetchAverageHeartRate(at: tx.timestamp)
            var newTx = tx
            newTx.heartRate = hr
            updatedTxData.append(newTx)
        }

        if let last = updatedTxData.last {
            lastFetchedSignature = last.signature
        }

        let result = updatedTxData
        DispatchQueue.main.async {
            self.transactions.append(contentsOf: result)
        }
    }

    private func fetchRecentTransactions(for publicKey: String, limit: Int, before: String?) async -> [SolanaSignatureInfo]? {
        var params: [Any] = [publicKey, ["limit": limit]]
        if let beforeSig = before {
            let options = ["limit": limit, "before": beforeSig] as [String : Any]
            params = [publicKey, options]
        }
        
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getSignaturesForAddress",
            "params": params
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else { return nil }
        
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(SolanaRPCResponse<[SolanaSignatureInfo]>.self, from: data)
            
            if let error = response.error {
                print("RPC Error: code=\(error.code), message=\(error.message)")
                return nil
            }
            
            guard let result = response.result else {
                print("No result field in response.")
                return nil
            }
            
            return result
        } catch {
            print("Error fetching transactions: \(error)")
            return nil
        }
    }

    private func fetchAverageHeartRate(at date: Date) async -> Int? {
        guard healthAuthorized else { return nil }
        
        return await withCheckedContinuation { continuation in
            guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
                continuation.resume(returning: nil)
                return
            }
            
            let start = date.addingTimeInterval(-30)
            let end = date.addingTimeInterval(30)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            
            let query = HKStatisticsQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, error in
                guard error == nil, let stats = result, let avg = stats.averageQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let bpm = avg.doubleValue(for: HKUnit(from: "count/min"))
                continuation.resume(returning: Int(bpm))
            }
            
            healthStore.execute(query)
        }
    }
}
