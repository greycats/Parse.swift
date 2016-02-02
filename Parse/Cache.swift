//
//  Cache.swift
//  Parse
//
//  Created by Rex Sheng on 1/15/16.
//  Copyright © 2016 Rex Sheng. All rights reserved.
//

//MARK: - Local Search & Cache

public protocol Cacheable {
	static var expireAfter: NSTimeInterval { get }
	func persist(enlist enlist: Bool)
}

public enum ParseCacheError: ErrorType {
	case Expired(time: NSTimeInterval)
	case NotFound
	case WrongFileFormat
}

protocol Cache: SequenceType {
	typealias Element
	typealias Index = Int
	func get(string: String) throws -> Element
	func persist(object: Element, enlist: Bool) throws
	func enlist(objects: [Element], replace: Bool) throws
}

extension ParseObject {
	init(json: Data) {
		self.init()
		self.json = json
		setupFields()
	}
}

extension ParseObject where Self: Cacheable {
	init(json: Data, cache: Bool) {
		self.init(json: json)
		if cache {
			persist(enlist: false)
		}
	}
}

extension ParseObject where Self: Cacheable {
	typealias CacheMachine = IndividualCache<Self>

	public static func list(closure: ([Self]) -> ()) {
		let cache = CacheMachine()
		if let objectIds = try? cache.objectIds() {
			do {
				let objects = try objectIds.map { try cache.get($0) }
				closure(objects)
				print("\(className).list hit cache count: \(objects.count)")
				return
			} catch ParseCacheError.Expired(let time) {
				print("\(className).list has expired \(time) secs.")
			} catch ParseCacheError.NotFound {
				print("\(className).list not found")
			} catch ParseCacheError.WrongFileFormat {
				print("\(className).list in wrong format")
			} catch {
				print("error fetching \(className).list")
			}
		}

		var collection: [Self] = []
		let group = dispatch_group_create()
		print("synchronizing \(className)...")
		query().local(0).each(group) { json in
			collection.append(Self(json: Data(json), cache: true))
		}

		dispatch_group_notify(group, dispatch_get_main_queue()) {
			do {
				try cache.enlist(collection, replace: true)
			} catch {
				print("failed to save keys list")
			}
			closure(collection)
		}
	}

	public static func get(objectId: String, callback: (Self) -> ()) {
		ObjectCache.get(CacheMachine(), objectId: objectId, callback: callback)
	}

	public func persist(enlist enlist: Bool) {
		do {
			try CacheMachine().persist(self, enlist: enlist)
		} catch let error {
			print("failed to persist \(error) \(Self.className):\(objectId)")
		}
	}
}

//MARKL Local Search

public protocol LocalMatch {
	func match(json: Data) -> Bool
}

extension Constraint: LocalMatch {
	public func match(json: Data) -> Bool {
		switch self {
		case .EqualTo(let key, let right):
			return json[key] == right
		case .GreaterThan(let key, let right):
			return right < json[key]
		case .LessThan(let key, let right):
			return json[key] < right
		case .MatchRegex(let key, let regexp):
			let string = json.value(key).string!
			return regexp.firstMatchInString(string, options: [], range: NSMakeRange(0, string.characters.count)) != nil
		case .In(let key, let keys):
			return keys.contains(json.value(key))
		case .NotIn(let key, let keys):
			return !keys.contains(json.value(key))
		case .Or(let left, let right):
			return left.match(json) || right.match(json)
		case .Exists(let key, let exists):
			let isNil = json.value(key).type == .Null
			if exists {
				return !isNil
			} else {
				return isNil
			}
		default:
			return false
		}
	}
}

private func orderExpression(expression: String) -> (lhs: Data, rhs: Data) -> Bool {
	let orders = expression.componentsSeparatedByString(",")
	var comparators: [(String, Bool)] = []
	for key in orders {
		let desc = key.hasPrefix("-")
		if desc {
			let key = key.substringFromIndex(key.startIndex.successor())
			comparators.append((key, false))
		} else {
			comparators.append((key, true))
		}
	}
	return {
		for (key, asc) in comparators {
			let v0 = $0[key], v1 = $1[key]
			if v0 == v1 {
				continue
			}
			//xnor
			if v0 < v1 {
				return asc
			} else {
				return !asc
			}
		}
		return true
	}
}

extension _Query: LocalMatch {
	private func replaceSubQueries() throws {
		for (index, constraint) in constraints.enumerate() {
			switch constraint {
			case .MatchQuery(let key, let matchKey, let inQuery):
				let keys = try inQuery._searchLocal().map { $0.value(matchKey) }
				constraints[index] = .In(key, keys)
				print("replaced \(constraint) with \(constraints[index])")
			case .DoNotMatchQuery(let key, let dontMatchKey, let inQuery):
				let keys = try inQuery._searchLocal().map { $0.value(dontMatchKey) }
				constraints[index] = .NotIn(key, keys)
				print("replaced \(constraint) with \(constraints[index])")
			default:
				continue
			}
		}
	}

	public func match(json: Data) -> Bool {
		for constraint in constraints {
			let match = constraint.match(json)
			if !match {
				return false
			}
		}
		return true
	}

	private func _countLocal() throws -> Int {
		try replaceSubQueries()
		let cache = try objectIds().map { try get($0) }
		var count = 0
		for object in cache where match(object) {
			count++
		}
		return count
	}

	private func _searchLocal() throws -> [Data] {
		try replaceSubQueries()
		let cache = try objectIds().map { try get($0) }
		var results = cache.filter(match)
		if let order = order {
			results.sortInPlace(orderExpression(order))
		}
		let _limit = limit ?? 100
		if results.count > _limit {
			results = Array(results[0..<_limit])
		}
		return results
	}

	private func get(objectId: String) throws -> Data {
		return try IndividualDataCache(expireAfter: trusteCache, className: className).get(objectId)
	}

	private func objectIds() throws -> [String] {
		return try IndividualDataCache(expireAfter: trusteCache, className: className).objectIds()
	}

	func searchLocal(closure: ([String: AnyObject]?, ErrorType?) -> Void) -> Bool {
		if trusteCache == 0 {
			return false
		}
		do {
			var result: [String: AnyObject] = [:]
			if fetchesCount {
				result["count"] = try _countLocal()
			} else {
				result["results"] = try _searchLocal().map { $0.raw }
			}
			closure(result, nil)
			return true
		} catch {
			return false
		}
	}
}

//MARK: Cache

private struct ObjectCache {
	typealias Callback = (objectId: String, callback: Data -> Void)
	static var timers: [String: (dispatch_source_t, [Callback])] = [:]

	static func timer(key: String) -> dispatch_source_t {
		if let timer = timers[key] {
			return timer.0
		}
		let source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue())
		dispatch_resume(source)
		timers[key] = (source, [])
		return source
	}

	static func retrivePending(key: String) -> [Callback] {
		if let (source, pending) = timers[key] {
			let checkouts = pending
			timers[key] = (source, [])
			return checkouts
		}
		return []
	}

	static func append(key: String, callback: Callback) {
		if let (source, pending) = timers[key] {
			var _pending = pending
			_pending.append(callback)
			timers[key] = (source, _pending)
		}
	}

	static func get<T: Cache where T.Element: ParseObject>(cache: T, objectId: String, rush: Double = 0.25, callback: (T.Element) -> Void) {
		if let object = try? cache.get(objectId) {
			return callback(object)
		} else {
			let className = T.Element.className
			let t = timer(className)
			append(className, callback: (objectId: objectId, callback: { callback(T.Element(json: $0)) }))
			dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, Int64(rush * Double(NSEC_PER_SEC))), DISPATCH_TIME_FOREVER, 0)
			dispatch_source_set_event_handler(t) {
				let pending = self.retrivePending(className)
				let objectIds = pending.map { ParseValue($0.objectId) }
				_Query(className: className, constraints: .In("objectId", objectIds)).data { (jsons, error) in
					for (objectId, callback) in pending {
						for json in jsons where json.objectId == objectId {
							callback(json)
							break
						}
					}
					let objects = jsons.map { T.Element(json: $0) }
					do {
						try objects.forEach { try cache.persist($0, enlist: false) }
						try cache.enlist(objects, replace: false)
					} catch ParseCacheError.Expired(let time) {
						print("failed to enlist: \(className).list has expired \(time) secs.")
					} catch let error as NSError {
						print("failed to enlist objects \(error)")
					}
				}
			}
		}
	}
}

//MARK: - Relations

public class ManyToMany {
	var cache: [Pointer] = []

	func addObject(object: Pointer) {
		removeObjectId(object.objectId)
		cache.append(object)
	}

	func addObject<U: ParseObject>(object: U) {
		addObject(Pointer(object: object))
	}

	func removeObjectId(object: String) {
		cache = cache.filter { $0.objectId != object}
	}

	func contains<U: ParseObject>(object: U) -> Bool {
		return contains(object.json.objectId)
	}

	func contains(objectId: String) -> Bool {
		for p in cache {
			if p.objectId == objectId {
				return true
			}
		}
		return false
	}

	var count: Int {
		return cache.count
	}
}

public struct RelationsCache {
	private static var relations: [String: (dispatch_group_t, ManyToMany)] = [:]

	public static func of<T: ParseObject, U: ParseObject>(object: T, key: String, toType: U.Type, closure: (ManyToMany) -> Void) {
		of(Pointer(object: object), key: key, toClass: U.className, closure: closure)
	}

	public static func of<T: ParseObject, U: ParseObject>(type: T.Type, key: String, to: U, closure: (ManyToMany) -> Void) {
		let mykey = "\(key)-\(T.className)-\(U.className)/\(to.json.objectId)"
		if let (group, relation) = relations[mykey] {
			dispatch_group_notify(group, dispatch_get_main_queue()) {
				closure(relation)
			}
		} else {
			let relation = ManyToMany()
			let group = dispatch_group_create()
			relations[mykey] = (group, relation)
			dispatch_group_enter(group)
			Query<T>().local(0).whereKey(key, equalTo: to).data { (data, error) in
				relation.cache = data.map { Pointer(className: T.className, data: $0) }
				print("caching relationship \(mykey): \(relation.cache)")
				dispatch_group_leave(group)
			}
			dispatch_group_notify(group, dispatch_get_main_queue()) {
				closure(relation)
			}
		}
	}

	public static func of(pointer: Pointer, key: String, toClass: String, closure: (ManyToMany) -> Void) {
		let mykey = "\(key)-\(pointer.className)/\(pointer.objectId)-\(toClass)"
		if let (group, relation) = relations[mykey] {
			dispatch_group_notify(group, dispatch_get_main_queue()) {
				closure(relation)
			}
		} else {
			let relation = ManyToMany()
			let group = dispatch_group_create()
			relations[mykey] = (group, relation)
			dispatch_group_enter(group)
			_Query(className: toClass, constraints: .RelatedTo(key, pointer)).data { (data, error) in
				relation.cache = data.map { Pointer(className: toClass, data: $0) }
				print("caching relationship \(mykey): \(relation.cache)")
				dispatch_group_leave(group)
			}
			dispatch_group_notify(group, dispatch_get_main_queue()) {
				closure(relation)
			}
		}
	}
}