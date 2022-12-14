//
//  Bridge Fetch.swift
//  
//
//  Created by Morris Richman on 8/17/22.
//

import Foundation
import Vapor
import VaporCron
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FluentKit

struct BridgeCheckStreamEveryMinuteJob: VaporCronSchedulable {
    typealias T = Void
    
    static var expression: String { "*/1 * * * * *" } // every second

    static func task(on application: Application) -> EventLoopFuture<Void> {
        print("ComplexJob start")
        BridgeFetch.streamTweets(db: application.db)
        return application.eventLoopGroup.future().always { _ in
            print("ComplexJob fired")
        }
    }
}
struct BridgeFetch {
    static func postBridgeNotification(bridge: Bridge, bridgeDetails: BridgeResponse) {
        let url = URL(string: "https://fcm.googleapis.com/fcm/send")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "Post"
        request.allHTTPHeaderFields = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(Secrets.firebaseCloudMessagingBearerToken)"
        ]
        let bridgeName = "\(bridgeDetails.bridgeLocation)_\(bridge.name)".replacingOccurrences(of: " Bridge", with: "").replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "st", with: "").replacingOccurrences(of: "nd", with: "").replacingOccurrences(of: "3rd", with: "").replacingOccurrences(of: "th", with: "").replacingOccurrences(of: " ", with: "_")
        func sendNotification(status: String) {
            let message = """
            {
              "to": "/topics/\(bridgeName)",
              "priority": "high",
              "mutable_content": true,
              "notification": {
                "title": "\(bridgeDetails.bridgeLocation)",
                "body": "The \(bridge.name.capitalized) is now \(status)",
                "badge": 0,
                "sound": "default",
                "content_availible": true
              },
              "data": {
                  "interruption_level": 3
              }
            }
            """
            let data = message.data(using: .utf8)
            let task = URLSession.shared.uploadTask(with: request, from: data) { (responseData, response, error) in
                if let error = error {
                    print("Error making Post request: \(error.localizedDescription)")
                    return
                }
                
                if let responseCode = (response as? HTTPURLResponse)?.statusCode, let responseData = responseData {
                    guard responseCode == 200 else {
                        print("Invalid Firebase response code: \(responseCode)")
                        return
                    }
                    
                    if let responseJSONData = try? JSONSerialization.jsonObject(with: responseData, options: .allowFragments) {
                        print("Firebase Response JSON data = \(responseJSONData)")
                    }
                }
            }
            task.resume()
        }
        switch bridge.status {
        case .up:
            sendNotification(status: BridgeStatus.up.rawValue)
        case .down:
            sendNotification(status: BridgeStatus.down.rawValue)
        case .maintenance:
            sendNotification(status: "under maintenance")
        case .unknown:
            sendNotification(status: "in an unknown state")
        }
    }
    static func updateBridge(bridge: Bridge, db: Database) {
        getBridgeInDb(db: db) { bridges in
            let url = URL(string: "http://localhost:8080/bridges")!

            var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.allHTTPHeaderFields = [
                "Content-Type": "application/json",
                "Accept": "application/json",
                "Authorization": "Bearer \(Secrets.internalEditBearerToken)"
            ]
            let updateBridge = bridges.first { bridgeResponse in
                bridgeResponse.name == bridge.name
            }
            print("updateBridge = \(updateBridge)")
            let jsonDictionary: [String: Any] = [
                "id": updateBridge?.id ?? "",
                "name": bridge.name,
                "status": bridge.status.rawValue,
                "image_url" : "",
                "maps_url" : "",
                "address" : "",
                "latitude" : Double(0),
                "longitude" : Double(0),
                "bridge_location" : ""
            ]
            print("jsonDict = \(jsonDictionary)")
            let data = try! JSONSerialization.data(withJSONObject: jsonDictionary, options: .prettyPrinted)
            let task = URLSession.shared.uploadTask(with: request, from: data) { (responseData, response, error) in
                if let error = error {
                    print("Error making PUT request: \(error.localizedDescription)")
                    return
                }
                
                if let responseCode = (response as? HTTPURLResponse)?.statusCode, let responseData = responseData {
                    guard responseCode == 200 else {
                        print("Invalid response code: \(responseCode)")
                        return
                    }
                    
                    if let responseJSONData = try? JSONSerialization.jsonObject(with: responseData, options: .allowFragments) {
                        print("Response JSON data = \(responseJSONData)")
                    }
                }
            }
            task.resume()
            guard let updateBridge = updateBridge else {
                return
            }
            postBridgeNotification(bridge: bridge, bridgeDetails: updateBridge)
        }
    }
    static func getBridgeInDb(db: Database, completion: @escaping ([BridgeResponse]) -> Void) {
        var request = URLRequest(url: URL(string: "http://localhost:8080/bridges")!,
                                 timeoutInterval: Double.infinity)
        
        request.addValue("Bearer \(Secrets.twitterBearerToken)", forHTTPHeaderField: "Authorization")
        
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil else {
                return
            }
            
            if let response = response as? HTTPURLResponse {
                guard (200 ... 299) ~= response.statusCode else {
                    print("??? Status code is \(response.statusCode)")
                    return
                }
                
                guard let data = data else {
                    return
                }
                
                do {
                    let jsonDecoder = JSONDecoder()
                    jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
                    let bridges = try jsonDecoder.decode([BridgeResponse].self, from: data)
                    print("result = \(bridges)")
                    completion(bridges)
                } catch {
                }
            }
        }
        task.resume()
        }
    static var bridgesUsed: [Bridge] = []
    static let maintenanceKeywords = ["maintenance", "until further notice", "issue"]
    
    static func addBridge(text: String, name: String, db: Database) {
        if !bridgesUsed.contains(where: { bridge in
            bridge.name == name
        }) {
            if maintenanceKeywords.contains(text.lowercased()) {
                if text.lowercased().contains("finished") {
                    let bridge = Bridge(name: name, status: .down)
                    bridgesUsed.append(bridge)
                    BridgeFetch.updateBridge(bridge: bridge, db: db)
                } else {
                    let bridge = Bridge(name: name, status: .maintenance)
                    bridgesUsed.append(bridge)
                    BridgeFetch.updateBridge(bridge: bridge, db: db)
                }
            } else if text.lowercased().contains("closed") {
                let bridge = Bridge(name: name, status: .up)
                bridgesUsed.append(bridge)
                BridgeFetch.updateBridge(bridge: bridge, db: db)
            } else if text.lowercased().contains("open") {
                let bridge = Bridge(name: name, status: .down)
                bridgesUsed.append(bridge)
                BridgeFetch.updateBridge(bridge: bridge, db: db)
            } else {
                let bridge = Bridge(name: name, status: .unknown)
                bridgesUsed.append(bridge)
                BridgeFetch.updateBridge(bridge: bridge, db: db)
            }
        }
    }
    
    static func handleBridge(text: String, db: Database) {
        switch text {
        case let str where str.contains("Ballard Bridge"):
            BridgeFetch.addBridge(text: text, name: "Ballard Bridge", db: db)
        case let str where str.contains("Fremont Bridge"):
            BridgeFetch.addBridge(text: text, name: "Fremont Bridge", db: db)
        case let str where str.contains("Montlake Bridge"):
            BridgeFetch.addBridge(text: text, name: "Montlake Bridge", db: db)
        case let str where str.contains("Lower Spokane St Bridge"):
            BridgeFetch.addBridge(text: text, name: "Spokane St Swing Bridge", db: db)
        case let str where str.contains("South Park Bridge"):
            BridgeFetch.addBridge(text: text, name: "South Park Bridge", db: db)
        case let str where str.contains("University Bridge"):
            BridgeFetch.addBridge(text: text, name: "University Bridge", db: db)
        case let str where str.contains("1st Ave S Bridge"):
            BridgeFetch.addBridge(text: text, name: "1 Ave S Bridge", db: db)
        default:
            break
        }
    }
    
    static func fetchTweets(db: Database) {
        BridgeFetch.bridgesUsed.removeAll()
        print("fetch tweets")
        TwitterFetch.shared.fetchTweet(id: "2768116808") { response in
            switch response {
            case .success(let response):
                for tweet in response.data {
                    print("tweet.text = \(tweet.text)")
                    BridgeFetch.handleBridge(text: tweet.text, db: db)
                }
            case .failure(let error):
                print("error = \(error)")
            }
        }
        TwitterFetch.shared.fetchTweet(id: "936366064518160384") { response in
            switch response {
            case .success(let response):
                for tweet in response.data {
                    print("tweet.text = \(tweet.text)")
                    BridgeFetch.handleBridge(text: tweet.text, db: db)
                }
            case .failure(let error):
                print("error = \(error)")
            }
        }
    }
    
    static func streamTweets(db: Database) {
        print("start stream")
        TwitterFetch.shared.startStream { response in
            switch response {
            case .success(let response):
                BridgeFetch.bridgesUsed.removeAll()
                BridgeFetch.handleBridge(text: response.data.text, db: db)
            case .failure(let error):
                print("error = \(error)")
            }
        }
    }
}
struct Bridge: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let status: BridgeStatus
}
enum BridgeStatus: String {
    case up
    case down
    case maintenance
    case unknown
}
struct BridgeResponse: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let status: String
    let imageUrl: String
    let mapsUrl: String
    let address: String
    let latitude: Double
    let longitude: Double
    let bridgeLocation: String
}
