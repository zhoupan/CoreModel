//
//  ValueJSON.swift
//  CoreModel
//
//  Created by Alsey Coleman Miller on 7/23/15.
//  Copyright © 2015 PureSwift. All rights reserved.
//

import SwiftFoundation

/// Converts the values object to JSON
public extension Entity {
    
    /// Converts ```JSON``` to **CoreModel** values.
    ///
    /// - returns: The converted values or ```nil``` if the provided values do not match the entity's properties.
    func convert(JSONObject: JSON.Object) -> ValuesObject? {
        
        var convertedValues = ValuesObject()
        
        // convert attributes
        for (key, attribute) in self.attributes {
            
            let value: Value
            
            if let jsonValue = JSONObject[key] {
                
                let attributeValue: AttributeValue
                
                switch (jsonValue, attribute.type) {
                    
                case let (JSON.Value.String(value), AttributeType.String):
                    attributeValue = .String(value)
                    
                case let (JSON.Value.Number(.Boolean(value)), AttributeType.Number(.Boolean)):
                    attributeValue = .Number(.Boolean(value))
                    
                case let (JSON.Value.Number(.Integer(value)), AttributeType.Number(.Integer)):
                    attributeValue = .Number(.Integer(value))
                    
                case let (JSON.Value.Number(.Double(value)), AttributeType.Number(.Double)):
                    attributeValue = .Number(.Double(value))
                    
                case let (JSON.Value.Number(.Double(value)), AttributeType.Date):
                    
                    let date = Date(timeIntervalSince1970: value)
                    
                    attributeValue = AttributeValue.Date(date)
                    
                case let (JSON.Value.String(value), AttributeType.Data):
                    
                    let stringData = value.utf8.map { (element) -> Byte in return element }
                    
                    let data = Base64.decode(stringData)
                    
                    attributeValue = AttributeValue.Data(data)
                    
                case (_, AttributeType.Transformable):
                    
                    if let value = jsonValue.parseTransformable() {
                        attributeValue = AttributeValue.Transformable(value)
                    } else {
                        return nil
                    }
                    
                default: return nil
                }
                
                value = .Attribute(attributeValue)
            }
            else { value = .Null }
            
            convertedValues[key] = value
        }
        
        // convert relationships
        for (key, relationship) in self.relationships {
            
            let convertedValue: Value
            
            if let jsonValue = JSONObject[key] {
                
                switch relationship.type {
                    
                case .ToOne:
                    
                    guard case let .String(value) = jsonValue
                        else { return nil }
                    
                    convertedValue = .Relationship(.ToOne(value))
                    
                case .ToMany:
                    
                    guard let jsonArray = jsonValue.arrayValue,
                        let resourceIDs = String.fromJSON(jsonArray)
                        else { return nil }
                    
                    convertedValue = .Relationship(.ToMany(resourceIDs))
                }
            }
            
            else { convertedValue = .Null }
            
            convertedValues[key] = convertedValue
        }

        return convertedValues
    }
}

public extension JSON {
    
    /// Converts **CoreModel** values to ```JSON```.
    static func fromValues(values: ValuesObject) -> JSONObject {
        
        var jsonObject = JSONObject()
        
        for (key, value) in values {
            
            let jsonValue = value.toJSON()
            
            jsonObject[key] = jsonValue
        }
        
        return jsonObject
    }
}

public extension Value {
    
    private func dataToEncodedString(d: Data) -> String {
        
        let encodedData = Base64.encode(d)
        
        var encodedString = ""
        
        for byte in encodedData {
            
            let unicodeScalar = UnicodeScalar(byte)
            
            encodedString.append(unicodeScalar)
        }

        return encodedString
    }
    
    func toJSON() -> JSON.Value {
        
        switch self {
            
        // Null
            
        case Value.Null: return JSON.Value.Null
            
        // Attribute
            
        case let .Attribute(.String(value)):
            return JSON.Value.String(value)
            
        case let .Attribute(.Number(.Boolean(value))):
            return JSON.Value.Number(.Boolean(value))
            
        case let .Attribute(.Number(.Integer(value))):
            return JSON.Value.Number(.Integer(value))
            
        case let .Attribute(.Number(.Double(value))):
            return JSON.Value.Number(.Double(value))
            
        case let .Attribute(.Number(.Float(value))):
            return JSON.Value.Number(.Double(Double(value)))

        case let .Attribute(.Transformable(value)):
            return value.toJSON()
            
        case let .Attribute(.Data(value)):
            
            let encodedData = Base64.encode(value)
            
            var encodedString = ""
            
            for byte in encodedData {
                
                let unicodeScalar = UnicodeScalar(byte)
                
                encodedString.append(unicodeScalar)
            }
            
            return JSON.Value.String(encodedString)
            
        case let .Attribute(.Date(value)):
            
            return JSON.Value.Number(.Double(value.timeIntervalSince1970))
            
        case let .Relationship(.ToOne(value)):
            
            return JSON.Value.String(value)
            
        case let .Relationship(.ToMany(value)):
            
            let jsonArray = value.map({ (element: String) -> JSON.Value in
                
                return JSON.Value.String(element)
            })
            
            return JSON.Value.Array(jsonArray)
        }
    }
}
