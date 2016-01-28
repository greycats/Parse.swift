//
//  Query.swift
//  Parse
//
//  Created by Rex Sheng on 1/15/16.
//  Copyright © 2016 Rex Sheng. All rights reserved.
//

public enum Constraint {
	case GreaterThan(String, ParseType)
	case LessThan(String, ParseType)
	case EqualTo(String, ParseType)
	case Exists(String, Bool)
	case MatchQuery(key: String, matchKey: String, inQuery: _Query)
	case DoNotMatchQuery(key: String, dontMatchKey: String, inQuery: _Query)
	case MatchRegex(String, NSRegularExpression)
	case Or(_Query, _Query)
	case In(String, [ParseValue])
	case NotIn(String, [ParseValue])
	case RelatedTo(String, Pointer)
}

public class _Query {
	var constraints: [Constraint] = []
	let className: String

	var order: String?
	var limit: Int?
	var includeKeys: String?
	var includeRelations: String?
	var skip: Int?
	var fetchesCount = false
	var trusteCache: NSTimeInterval = 0

	init(className: String, constraints: Constraint...) {
		self.className = className
		self.constraints.appendContentsOf(constraints)
	}

	public func constraint(constraint: Constraint) -> Self {
		constraints.append(constraint)
		return self
	}

	public func whereKey<U: ParseType>(key: String, equalTo object: U) -> Self {
		if key == "objectId" && object is Pointer {
			return constraint(.EqualTo(key, ParseValue((object as! Pointer).objectId)))
		} else {
			return constraint(.EqualTo(key, object))
		}
	}

	public func whereKey(key: String, equalTo object: ParseValueLiteralConvertible) -> Self {
		if let date = object as? NSDate {
			return constraint(.EqualTo(key, Date(date: date)))
		}
		return constraint(.EqualTo(key, ParseValue(object)))
	}

	public func whereKey<U: ParseObject>(key: String, equalTo object: U) -> Self {
		if key == "objectId" {
			return constraint(.EqualTo(key, ParseValue(object.objectId)))
		} else {
			return constraint(.EqualTo(key, Pointer(object: object)))
		}
	}

	public func whereKey<U: ParseType>(key: String, greaterThan object: U) -> Self {
		return constraint(.GreaterThan(key, object))
	}

	public func whereKey(key: String, greaterThan object: ParseValueLiteralConvertible) -> Self {
		if let date = object as? NSDate {
			return constraint(.GreaterThan(key, Date(date: date)))
		}
		return constraint(.GreaterThan(key, ParseValue(object)))
	}

	public func whereKey<U: ParseType>(key: String, lessThan object: U) -> Self {
		return constraint(.LessThan(key, object))
	}

	public func whereKey(key: String, lessThan object: ParseValueLiteralConvertible) -> Self {
		if let date = object as? NSDate {
			return constraint(.LessThan(key, Date(date: date)))
		}
		return constraint(.LessThan(key, ParseValue(object)))
	}

	public func whereKey(key: String, containedIn: [ParseValue]) -> Self {
		return constraint(.In(key, containedIn))
	}

	public func whereKey(key: String, containedIn: [String]) -> Self {
		let values = containedIn.map { ParseValue($0) }
		return constraint(.In(key, values))
	}

	public func whereKey(key: String, containedIn: [Int]) -> Self {
		let values = containedIn.map({ ParseValue($0) })
		return constraint(.In(key, values))
	}

	public func whereKey(key: String, notContainedIn: [ParseValue]) -> Self {
		return constraint(.NotIn(key, notContainedIn))
	}

	public func whereKey(key: String, notContainedIn: [String]) -> Self {
		let values = notContainedIn.map({ ParseValue($0) })
		return constraint(.NotIn(key, values))
	}

	public func whereKey<U: ParseObject>(key: String, matchKey: String, inQuery: Query<U>) -> Self {
		return constraint(.MatchQuery(key: key, matchKey: matchKey, inQuery: inQuery))
	}

	public func whereKey<U: ParseObject>(key: String, dontMatchKey: String, inQuery: Query<U>) -> Self {
		return constraint(.DoNotMatchQuery(key: key, dontMatchKey: dontMatchKey, inQuery: inQuery))
	}

	public func whereKey(key: String, match: NSRegularExpression) -> Self {
		return constraint(.MatchRegex(key, match))
	}

	public func whereKey(key: String, exists: Bool) -> Self {
		return constraint(.Exists(key, exists))
	}

	public func relatedTo<U: ParseObject>(object: U, key: String) -> Self {
		return constraint(.RelatedTo(key, Pointer(object: object)))
	}

	public func relatedTo(pointer: Pointer, key: String) -> Self {
		return constraint(.RelatedTo(key, pointer))
	}

	public func relatedTo(className: String, objectId: String, key: String) -> Self {
		return relatedTo(Pointer(className: className,  objectId: objectId), key: key)
	}

	public func keys(exp: String) -> Self {
		includeKeys = exp
		return self
	}

	public func include(exp: String) -> Self {
		includeRelations = exp
		return self
	}

	public func skip(skip: Int) -> Self {
		self.skip = skip
		return self
	}

	public func order(order: String) -> Self {
		self.order = order
		return self
	}

	public func limit(limit: Int) -> Self {
		self.limit = limit
		return self
	}

	public func local(duration: NSTimeInterval) -> Self {
		trusteCache = duration
		return self
	}
}

public class Query<T: ParseObject>: _Query {
	public init(constraints: Constraint...) {
		super.init(className: T.className)
		if let target = T.self as? Cache.Type {
			trusteCache = target.expireAfter
		}
		self.constraints.appendContentsOf(constraints)
	}
}

extension ParseObject {
	public static func query() -> Query<Self> {
		return Query()
	}

	public static func relatedTo<U: ParseObject>(object: U, key: String) -> Query<Self> {
		return query().relatedTo(object, key: key)
	}
}

public func ||<T>(left: Query<T>, right: Query<T>) -> Query<T> {
	return Query<T>(constraints: .Or(left, right))
}