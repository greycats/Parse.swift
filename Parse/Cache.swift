//
//  Cache.swift
//  Parse
//
//  Created by Rex Sheng on 1/15/16.
//  Copyright © 2016 Rex Sheng. All rights reserved.
//

//MARK: - Local Search & Cache

public protocol Cache {
	static var expireAfter: NSTimeInterval { get }
	func persist(enlist enlist: Bool)
}

public struct CachedObjectsGenerator<T: ParseObject where T: Cache>: CollectionType {
	public typealias Index = Int
	public var startIndex: Int { return 0 }
	public var endIndex: Int { return list.count }
	public subscript(i: Int) -> T {
		return T.load(list[i])!
	}
	let list: [String]
}

let cacheHome = NSSearchPathForDirectoriesInDomains(.CachesDirectory, .UserDomainMask, true).first

extension ParseObject {
	init(json: Data, cache: Bool = true) {
		self.init()
		self.json = json
		if let this = self as? Cache where cache {
			this.persist(enlist: false)
		}
		setupFields()
	}
}

private func _loadJSON(folder: String, key: String, expireAfter: NSTimeInterval) -> AnyObject? {
	if let filePath = cacheHome?.stringByAppendingString("/\(folder)/\(key)") {
		if let attr = try? NSFileManager.defaultManager().attributesOfItemAtPath(filePath),
			lastModified = attr[NSFileModificationDate] as? NSDate {
				if lastModified.timeIntervalSinceNow < -expireAfter {
					return nil
				}
		}
		if let data = NSData(contentsOfFile: filePath),
			let object = try? NSJSONSerialization.JSONObjectWithData(data, options: []) {
				return object
		}
	}
	return nil
}

extension ParseObject where Self: Cache {
	private static func loadJSON(key: String, expireAfter: NSTimeInterval) -> AnyObject? {
		return _loadJSON(className, key: key, expireAfter: expireAfter)
	}

	private static func saveJSON(json: AnyObject, toPath: String) throws {
		if let folder = cacheHome?.stringByAppendingString("/\(className)") {
			try NSFileManager.defaultManager().createDirectoryAtPath(folder, withIntermediateDirectories: true, attributes: nil)
			let filePath = "\(folder)/\(toPath)"
			let data = try NSJSONSerialization.dataWithJSONObject(json, options: [])
			data.writeToFile(filePath, atomically: false)
		}
	}

	public static func list(closure: ([Self]) -> ()) {
		if let generator = generate() {
			let objects = generator.map { $0 }
			closure(objects)
			print("hit cache count: \(objects.count)")
			return
		}

		var collection: [Self] = []
		let group = dispatch_group_create()

		query().local(0).each(group) { json in
			collection.append(Self(json: Data(json), cache: true))
		}

		dispatch_group_notify(group, dispatch_get_main_queue()) {
			do {
				try enlist(collection, replace: true)
			} catch {
				print("failed to save keys list")
			}
			closure(collection)
		}
	}

	private static func load(objectId: String) -> Self? {
		if let json = loadJSON(objectId, expireAfter: expireAfter) as? [String: AnyObject] {
			return Self(json: Data(json), cache: false)
		}
		return nil
	}

	public static func get(objectId: String, callback: (Self) -> ()) {
		ObjectCache.get(objectId, callback: callback)
	}

	public func persist(enlist enlist: Bool) {
		do {
			try Self.saveJSON(json.raw, toPath: objectId)
			if enlist {
				try Self.enlist([self])
			}
		} catch {
			print("failed to save \(Self.className):\(objectId)")
		}
	}

	static func enlist(objects: [Self], replace: Bool = false) throws {
		var keys: [String]
		if replace {
			keys = []
		} else {
			keys = self.keys() ?? []
		}
		for object in objects {
			let objectId = object.objectId
			if !keys.contains(objectId) {
				keys.append(objectId)
			}
		}
		try saveJSON(keys, toPath: ".list")
		print("saved \(keys.count) to \(className)/.list")
	}

	private static func keys() -> [String]? {
		return loadJSON(".list", expireAfter: expireAfter) as? [String]
	}

	public static func generate() -> CachedObjectsGenerator<Self>? {
		if let list = keys() {
			return CachedObjectsGenerator(list: list)
		}
		return nil
	}
}

//MARKL Local Search

protocol LocalMatch {
	func match(json: Data) -> Bool
}

extension Constraint: LocalMatch {
	func match(json: Data) -> Bool {
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

extension Constraints: LocalMatch {
	private func allowsLocalSearch() -> Bool {
		for constraint in inner {
			switch constraint {
			case .EqualTo(_, let to):
				if let _ = to as? Pointer {
					return false
				}
			default:
				continue
			}
		}
		return true
	}

	private mutating func replaceSubQueries(keys: (String, Constraints) -> [ParseValue]) {
		var replaced = false
		for (index, constraint) in inner.enumerate() {
			switch constraint {
			case .MatchQuery(let key, let matchKey, let constraints):
				inner[index] = .In(key, keys(matchKey, constraints))
				replaced = true
			case .DoNotMatchQuery(let key, let dontMatchKey, let constraints):
				inner[index] = .NotIn(key, keys(dontMatchKey, constraints))
				replaced = true
			default:
				continue
			}
		}

		if replaced {
			print("replaced subqueries with in/notin queries \(inner)")
		}
	}

	func match(json: Data) -> Bool {
		for constraint in inner {
			let match = constraint.match(json)
			if !match {
				return false
			}
		}
		return true
	}
}

extension _Query {
	private func _searchLocal(cache: [Data]) -> [String: AnyObject] {
		self.constraints.replaceSubQueries { (key, constraints) in
			let filtered = cache.filter { constraints.match($0) }
			return filtered.map { $0.value(key) }
		}
		var results: [Data] = []
		var count = 0
		for object in cache {
			if self.constraints.match(object) {
				count++
				if !self.fetchesCount {
					results.append(object)
					//TOOD selected Keys?
				}
			}
		}
		results.sort(self.order)

		var limit = 100
		if let _limit = self.limit {
			limit = _limit
		}
		if results.count > limit {
			results = Array(results[0..<limit])
		}

		var result: [String: AnyObject] = [:]
		if self.fetchesCount {
			result["count"] = count
		} else {
			result["results"] = results.map { $0.raw }
		}
		return result
	}

	func searchLocal(closure: ([String: AnyObject]?, ErrorType?) -> Void) -> Bool {
		if trusteCache == 0 {
			return false
		}

		if let cache = _loadJSON(constraints.className, key: ".list", expireAfter: trusteCache) as? [String] {
			do {
				let data: [Data] = try cache.map { objectId in
					if let object = _loadJSON(constraints.className, key: objectId, expireAfter: trusteCache) as? [String: AnyObject] {
						return Data(object)
					} else {
						throw ParseError.CacheStructureFailure
					}
				}
				closure(_searchLocal(data), nil)
				return true
			} catch {
				return false
			}
		} else {
			return false
		}
	}
}

//MARK: Cache

private struct ObjectCache {
	typealias Timer = (objectId: String, callback: Data -> Void)
	static var timers: [String: (dispatch_source_t, [Timer])] = [:]

	static func timer(key: String) -> dispatch_source_t {
		if let timer = timers[key] {
			return timer.0
		}
		let timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue())
		dispatch_resume(timer)
		timers[key] = (timer, [])
		return timer
	}

	static func retrivePending<T: ParseObject>(type: T.Type) -> [Timer] {
		if let (timer, pending) = timers[T.className] {
			let checkouts = pending
			timers[T.className] = (timer, [])
			return checkouts
		}
		return []
	}

	static func appendCallback<T: ParseObject>(objectId: String, callback: (T) -> Void) {
		if let (timer, pending) = timers[T.className] {
			var _pending = pending
			_pending.append((objectId: objectId, callback: { callback(T(json: $0)) }))
			timers[T.className] = (timer, pending)
		}
	}

	static func get<T: ParseObject where T: Cache>(objectId: String, rush: Double = 0.25, callback: (T) -> Void) {
		if let object = T.load(objectId) {
			return callback(object)
		} else {
			let t = timer(T.className)
			appendCallback(objectId, callback: callback)
			dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, Int64(rush * Double(NSEC_PER_SEC))), DISPATCH_TIME_FOREVER, 0)
			dispatch_source_set_event_handler(t) {
				let pending = self.retrivePending(T.self)
				let objectIds = pending.map { ParseValue($0.objectId) }
				_Query(className: T.className, constraints: .In("objectId", objectIds)).data { (jsons, error) in
					for (objectId, callback) in pending {
						for json in jsons where json.objectId == objectId {
							callback(json)
							break
						}
					}
					let objects = jsons.map { T(json: $0) }
					objects.forEach { $0.persist(enlist: false) }
					do {
						try T.enlist(objects)
					} catch {
						print("failed to enlist objects")
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