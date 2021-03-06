//
//  CoreDataValues.swift
//  CoreModel
//
//  Created by Alsey Coleman Miller on 7/23/15.
//  Copyright © 2015 PureSwift. All rights reserved.
//

#if os(OSX)

import Foundation
import CoreData
import SwiftFoundation

public extension NSManagedObject {
    
    func values(store: CoreDataStore) throws -> ValuesObject {
        
        var values = ValuesObject()
        
        for (attributeName, attributeDescription) in self.entity.attributesByName {
            
            // skip resource ID value
            if attributeName == store.resourceIDAttributeName { continue }
        
            guard let CoreDataValue = self.valueForKey(attributeName)
                else { values[attributeName] = Value.Null; continue }
            
            guard let value = AttributeValue(CoreDataValue: CoreDataValue, attributeDescription: attributeDescription)
                else { fatalError("Could not convert Core Data attribute value \(CoreDataValue)") }
            
            values[attributeName] = Value.Attribute(value)
        }
        
        for (relationshipName, relationship) in self.entity.relationshipsByName {
            
            guard let CoreDataValue = self.valueForKey(relationshipName)
                else { values[relationshipName] = Value.Null; continue }
            
            // to-one
            if !relationship.toMany {
                
                let destinationManagedObject = CoreDataValue as! NSManagedObject
                
                let resourceID = destinationManagedObject.valueForKey(relationshipName) as! String
                
                values[relationshipName] = Value.Relationship(.ToOne(resourceID))
            }
                
            // to-many
            else {
                
                let destinationManagedObjects = self.arrayValueForToManyRelationship(relationship: relationshipName)!
                
                var resourceIDs = [String]()
                
                for destinationManagedObject in destinationManagedObjects {
                    
                    let resourceID = destinationManagedObject.valueForKey(relationshipName) as! String
                    
                    resourceIDs.append(resourceID)
                }
                
                values[relationshipName] = Value.Relationship(.ToMany(resourceIDs))
            }
        }
        
        return values
    }
    
    /// Set the properties from a ```ValuesObject```. Does not save managed object context.
    func setValues(values: ValuesObject, store: CoreDataStore) throws {
        
        guard let entityName = self.entity.name else { fatalError("Core Data Entity is unnamed") }
        
        guard let _ = store.model[entityName]
            else { fatalError("No entity named '\(entityName)' in CoreDataStore") }
        
        // TODO: Fix values validation
        // sanity check
        //try store.validate(values, forEntity: entity)
        
        for (key, value) in values {
            
            guard key != store.resourceIDAttributeName else { continue }
            
            // validate entity exists
            guard let property = self.entity.propertiesByName[key] else { throw StoreError.InvalidValues }
            
            let value: AnyObject? = try {
                
                switch value {
                    
                case .Null: return nil
                    
                case .Attribute(let attributeValue):
                    
                    guard (property as? NSAttributeDescription != nil)
                        else { throw StoreError.InvalidValues }
                    
                    return attributeValue.toCoreDataValue()
                    
                case .Relationship(let relationshipValue):
                    
                    guard let relationshipDescription = property as? NSRelationshipDescription
                        else { throw StoreError.InvalidValues }
                    
                    switch relationshipValue {
                        
                    case .ToOne(let resourceID):
                        
                        guard let destinationObjectID = try store.findEntity(relationshipDescription.destinationEntity!, withResourceID: resourceID)
                            else { throw StoreError.InvalidValues }
                        
                        let destinationManagedObject = store.managedObjectContext.objectWithID(destinationObjectID)
                        
                        return destinationManagedObject
                        
                    case .ToMany(let resourceIDs):
                        
                        var destinationManagedObjects = [NSManagedObject]()
                        
                        for resourceID in resourceIDs {
                            
                            guard let destinationObjectID = try store.findEntity(relationshipDescription.destinationEntity!, withResourceID: resourceID)
                                else { throw StoreError.InvalidValues }
                            
                            let destinationManagedObject = store.managedObjectContext.objectWithID(destinationObjectID)
                            
                            destinationManagedObjects.append(destinationManagedObject)
                        }
                        
                        if relationshipDescription.ordered {
                            
                            return NSOrderedSet(array: destinationManagedObjects)
                        }
                        
                        return NSSet(array: destinationManagedObjects)
                    }
                }
                
                }()
            
            self.setValue(value, forKey: key)
        }
    }
}

public extension AttributeValue {
    
    init?(CoreDataValue: AnyObject, attributeDescription: NSAttributeDescription) {
        
        switch attributeDescription.attributeType {
        case .StringAttributeType:
            guard let value = CoreDataValue as? NSString else {
                fatalError("Attribute is \(attributeDescription.attributeType), but couldn't cast to NSString")
            }
            
            self = .String(value as StringValue)
            
        case .DateAttributeType:
            guard let value = CoreDataValue as? NSDate else {
                fatalError("Attribute is \(attributeDescription.attributeType), but couldn't cast to NSDate")
            }
            
            let date = SwiftFoundation.Date(foundation: value)
            self = .Date(date)
            
        case .BinaryDataAttributeType:
            guard let value = CoreDataValue as? NSData else {
                fatalError("Attribute is \(attributeDescription.attributeType), but couldn't cast to NSData")
            }
            
            let data = value.arrayOfBytes()
            
            self = .Data(data)
            
        case .BooleanAttributeType:
            guard let value = CoreDataValue as? Bool else {
                fatalError("Attribute is \(attributeDescription.attributeType), but couldn't cast to Bool")
            }
            
            self = .Number(.Boolean(value))

        case .Integer16AttributeType, .Integer32AttributeType, .Integer64AttributeType:
            guard let value = CoreDataValue as? NSNumber else {
                fatalError("Attribute is \(attributeDescription.attributeType), but couldn't cast to Int")
            }
            
            self = .Number(.Integer(value.integerValue))
            
        case .FloatAttributeType:
            guard let value = CoreDataValue as? NSNumber else {
                fatalError("Attribute is \(attributeDescription.attributeType), but couldn't cast to Float")
            }
            
            self = .Number(.Float(value.floatValue))
            
        case .DoubleAttributeType:
            guard let value = CoreDataValue as? NSNumber else {
                fatalError("Attribute is \(attributeDescription.attributeType), but couldn't cast to Double")
            }
            
            self = .Number(.Double(value.doubleValue))

        case .DecimalAttributeType:
            fatalError("Decimal conversion not implemented")
            
        case .TransformableAttributeType:
            guard let value = CoreDataValue as? DataConvertible else {
                fatalError("CoreDataValue is Transformable, but couldn't cast to DataConvertible")
            }
            
            print("\(value)")
            self = .Transformable(value)
            
        case .UndefinedAttributeType:
            fatalError("Transient / Undefined attribute conversion not implemented")
            
        default:
            return nil
        }
    }
    
    func toCoreDataValue() -> AnyObject {
        
        switch self {
            
        case .String(let value): return value
        case .Date(let value): return value.toFoundation()
        case .Data(let value): return NSData(bytes: value)
        case .Transformable(let value): return value.toFoundation()
        case .Number(let number):
            switch number {
                
            case .Boolean(let value): return NSNumber(bool: value)
            case .Integer(let value): return NSNumber(integer: Int(value))
            case .Double(let value): return NSNumber(double: value)
            case .Float(let value): return NSNumber(float: value)
            }
        }
    }
}

#endif
