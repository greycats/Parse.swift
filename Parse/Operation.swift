//
//  Operation.swift
//  Parse
//
//  Created by Rex Sheng on 1/15/16.
//  Copyright © 2016 Rex Sheng. All rights reserved.
//

public enum Operation {
	case AddUnique(String, [AnyObject])
	case Remove(String, [AnyObject])
	case Add(String, [AnyObject])
	case Increase(String, Int)
	case SetValue(String, ParseType)
	case AddRelation(String, Pointer)
	case RemoveRelation(String, Pointer)
	case SetSecurity(String)
	case DeleteColumn(String)
}

public class _Operations<T: ParseObject> {
	var operations: [Operation]

	init(operations: [Operation]) {
		self.operations = operations
	}
}

public class ClassOperations<T: ParseObject>: _Operations<T> {
	public init() {
		super.init(operations: [])
	}
}

public class ObjectOperations<T: ParseObject>: _Operations<T> {
	let objectId: String

	public init(_ objectId: String, operations: [Operation]) {
		self.objectId = objectId
		super.init(operations: operations)
	}
}

extension ObjectOperations {
	func updateRelations() {
		let this = Pointer(className: T.className, objectId: objectId)
		for operation in operations {
			switch operation {
			case .AddRelation(let key, let pointer):
				Relations.of(this, key: key, toClass: pointer.className) { (relation) in
					relation.addObject(pointer)
				}
			case .RemoveRelation(let key, let pointer):
				Relations.of(this, key: key, toClass: pointer.className) { (relation) in
					relation.removeObjectId(pointer.objectId)
				}
			default:
				continue
			}
		}
	}
}

extension ParseObject {
	public func operation() -> ObjectOperations<Self> {
		return ObjectOperations(objectId, operations: [])
	}

	public static func query() -> Query<Self> {
		return Query()
	}

	public func addRelation<U: ParseObject>(key: String, to: U) -> ObjectOperations<Self> {
		return operation().addRelation(key, to: to)
	}
	public func removeRelation<U: ParseObject>(key: String, to: U) -> ObjectOperations<Self> {
		return operation().removeRelation(key, to: to)
	}

	public static func relatedTo<U: ParseObject>(object: U, key: String) -> Query<Self> {
		return query().relatedTo(object, key: key)
	}
}

extension Parse {
	public static func operation<T: ParseObject>(on on: T) -> ObjectOperations<T> {
		let operations = ObjectOperations<T>(on.json.objectId, operations: [])
		if let pending = on.json.pending {
			for (key, value) in pending {
				switch value {
				case let v as ParseValue:
					operations.set(key, value: v)
				case let p as Pointer:
					operations.set(key, value: p)
				case let d as Date:
					operations.set(key, value: d)
				default:
					break
				}
			}
		}
		return operations
	}
}

extension _Operations {
	public func operation(operation: Operation) -> Self {
		operations.append(operation)
		return self
	}

	public func set(key: String, value: [AnyObject]) -> Self {
		return operation(.SetValue(key, AnyWrapper(value)))
	}

	public func set(key: String, value: ComparableKeyType) -> Self {
		if let date = value as? NSDate {
			return set(key, value: Date(date: date))
		}
		return set(key, value: ParseValue(value))
	}

	public func set<U: ParseObject>(key: String, value: U) -> Self {
		return operation(.SetValue(key, Pointer(object: value)))
	}

	public func set<U: ParseType>(key: String, value: U) -> Self {
		return operation(.SetValue(key, value))
	}

	public func addRelation<U: ParseObject>(key: String, to: U) -> Self {
		return operation(.AddRelation(key, Pointer(object: to)))
	}

	public func addUnique(key: String, object: AnyObject) -> Self {
		return operation(.AddUnique(key, [object]))
	}

	public func add(key: String, object: AnyObject) -> Self {
		return operation(.Add(key, [object]))
	}

	public func remove(key: String, object: AnyObject) -> Self {
		return operation(.Remove(key, [object]))
	}

	public func addUnique(key: String, objects: [AnyObject]) -> Self {
		return operation(.AddUnique(key, objects))
	}

	public func add(key: String, objects: [AnyObject]) -> Self {
		return operation(.Add(key, objects))
	}

	public func remove(key: String, objects: [AnyObject]) -> Self {
		return operation(.Remove(key, objects))
	}

	public func increase(key: String, amount: Int) -> Self {
		return operation(.Increase(key, amount))
	}

	public func removeRelation<U: ParseObject>(key: String, to: U) -> Self {
		return operation(.RemoveRelation(key, Pointer(object: to)))
	}
}