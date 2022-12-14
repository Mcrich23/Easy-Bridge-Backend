//
//  Bridge.swift
//  
//
//  Created by Morris Richman on 8/17/22.
//

import Fluent
import Vapor
import Foundation

final class BridgeModel: Model, Content {
    static let schema = "bridges"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "name")
    var name: String
    @Field(key: "status")
    var status: String
    @Field(key: "image_url")
    var image_url: String
    @Field(key: "maps_url")
    var maps_url: String
    @Field(key: "address")
    var address: String
    @Field(key: "latitude")
    var latitude: Double
    @Field(key: "longitude")
    var longitude: Double
    @Field(key: "bridge_location")
    var bridge_location: String
    
    init() {}
    
    init(id:UUID? = nil, name: String, image_url: String, status: String, maps_url: String, address: String, latitude: Double, longitude: Double, bridge_location: String) {
        self.id = id
        self.name = name
        self.status = status
        self.maps_url = maps_url
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.image_url = image_url
        self.bridge_location = bridge_location
    }
}
