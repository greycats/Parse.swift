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
	case ClearSecurity
	case DeleteColumn(String)
}

public class _Operations {
	var operations: [Operation]

	init(operations: [Operation]) {
		self.operations = operations
	}
}

public class Operations<T: ParseObject>: _Operations {
	let object: T

	public init(_ object: T, operations: [Operation]) {
		self.object = object
		super.init(operations: operations)
	}
}

extension Operations {
	func updateRelations() {
		let this = Pointer(className: T.className, objectId: object.objectId)
		for operation in operations {
			switch operation {
			case .AddRelation(let key, let pointer):
				RelationsCache.of(this, key: key, toClass: pointer.className) { (relation) in
					relation.addObject(pointer)
				}
			case .RemoveRelation(let key, let pointer):
				RelationsCache.of(this, key: key, toClass: pointer.className) { (relation) in
					relation.removeObjectId(pointer.objectId)
				}
			default:
				continue
			}
		}
	}
}

extension ParseObject {
	public func operation() -> Operations<Self> {
		return Operations(self, operations: [])
	}

	public static func operation() -> Operations<Self> {
		return Self().operation()
	}

	public func addRelation<U: ParseObject>(key: String, to: U) -> Operations<Self> {
		return operation().addRelation(key, to: to)
	}
	public func removeRelation<U: ParseObject>(key: String, to: U) -> Operations<Self> {
		return operation().removeRelation(key, to: to)
	}
}

extension _Operations {
	static func convertToOperation<U: ParseObject>(key: String, value: U?) -> Operation {
		if let value = value {
			if let file = value as? File, name = file.name.get() {
				return .SetValue(key, AnyWrapper(["name": name, "__type": "File"]))
			}
			return .SetValue(key, Pointer(object: value))
		} else {
			return .SetValue(key, ParseValue(nil))
		}
	}

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
		return operation(_Operations.convertToOperation(key, value: value))
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