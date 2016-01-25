//
//  Cache.swift
//  Parse
//
//  Created by Rex Sheng on 1/15/16.
//  Copyright © 2016 Rex Sheng. All rights reserved.
//

//MARK: - Local Search & Cache

private struct ClassCache {
	var inner: [Data] = []

	func data(objectId: String) -> Data? {
		for rec in inner {
			if rec.objectId == objectId {
				return rec
			}
		}
		return nil
	}

	mutating func appendData(data: Data) {
		var appended = false
		for i in 0..<inner.count {
			if inner[i].objectId == data.objectId {
				inner[i] = data
				appended = true
			}
		}
		if !appended {
			inner.append(data)
		}
	}

	mutating func removeData(data: Data) {
		for i in 0..<inner.count {
			if inner[i].objectId == data.objectId {
				defer {
					inner.removeAtIndex(i)
				}
			}
		}
	}
}

private struct LocalPersistence {
	static var classCache: [String: ClassCache] = [:]
	static let local_search_queue = dispatch_queue_create(nil, DISPATCH_QUEUE_CONCURRENT)

	static func data(pointer: Pointer) -> Data? {
		if let recs = classCache[pointer.className] {
			return recs.data(pointer.objectId)
		}
		return nil
	}

	static func appendData(data: Data, pointer: Pointer) {
		if classCache[pointer.className] == nil {
			classCache[pointer.className] = ClassCache()
		}
		classCache[pointer.className]?.appendData(data)
	}
}

struct LocalCache {
	let className: String

	func loadCache() -> [String: AnyObject]? {
		let key = "v3.\(className).json"
		let paths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)
		if let root = paths.first {
			let file = root.stringByAppendingString("/\(key)")
			if let data = NSData(contentsOfFile: file) {
				print("loading from file \(file)")
				if let json = (try? NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments)) as? [String: AnyObject] {
					return json
				}
			}
		}
		return nil
	}

	func writeCache(json: [String: AnyObject]) {
		let key = "v3.\(className).json"
		let paths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)
		if let root = paths.first {
			let file = root.stringByAppendingString("/\(key)")
			(try? NSJSONSerialization.dataWithJSONObject(json, options: []))?
				.writeToFile(file, atomically: true)
			print("\(className) data wrote to \(file)")
		}
	}

	func data(objectId: String) -> Data? {
		if let data = LocalPersistence.classCache[className]?.data(objectId) {
			return data
		}
		if let cache = loadCache() {
			if let results = cache["results"] as? [String: AnyObject],
				let raw = results[objectId] as? [String: AnyObject] {
					return Data(raw)
			}
		}
		return nil
	}

	func append(dom: Data) {
		if let cache = loadCache() {
			var results = cache["results"] as! [String: AnyObject]
			results[dom.objectId] = dom.raw
			LocalPersistence.classCache[className]?.appendData(dom)
			let json: [String: AnyObject] = [
				"time": NSDate.timeIntervalSinceReferenceDate(),
				"results": results,
				"class": className]
			writeCache(json)
		}
	}

	func remove(dom: Data) {
		if let cache = loadCache() {
			var results = cache["results"] as! [String: AnyObject]
			results.removeValueForKey(dom.objectId)
			LocalPersistence.classCache[className]?.removeData(dom)
			let json: [String: AnyObject] = [
				"time": NSDate.timeIntervalSinceReferenceDate(),
				"results": results,
				"class": className]
			writeCache(json)
		}
	}

	func persistent(maxAge: NSTimeInterval, done: ([Data] -> Void)?) {
		if let cache = loadCache() {
			if let time = cache["time"] as? Double {
				let cachedTime = NSDate(timeIntervalSinceReferenceDate: time)
				if cachedTime.timeIntervalSinceNow > -maxAge {
					if let cache = cache["results"] as? [String: [String: AnyObject]] {
						let allData = cache.map { Data($1) }
						if allData.count > 0 {
							LocalPersistence.classCache[className] = ClassCache(inner: allData)
							print("use local data \(className) count=\(allData.count)")
							done?(allData)
							return
						}
					}
				}
			}
		}
		let group = dispatch_group_create()
		var cache: [String: AnyObject] = [:]
		var jsons: [Data] = []
		print("start caching all \(className)")

		_Query(className: className).each(group) { object in
			cache[object["objectId"] as! String] = object
			jsons.append(Data(object))
		}

		dispatch_group_notify(group, dispatch_get_main_queue()) {
			LocalPersistence.classCache[self.className] = ClassCache(inner: jsons)
			print("\(self.className) ready count=\(cache.count)")
			let json: [String: AnyObject] = [
				"time": NSDate.timeIntervalSinceReferenceDate(),
				"results": cache,
				"class": self.className]
			self.writeCache(json)
			done?(jsons)
		}
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
			if let pointer = json.pointer(key) {
				return keys.contains(ParseValue(pointer.objectId))
			}
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
	func searchLocal(closure: ([String: AnyObject]?, ErrorType?) -> Void) -> Bool {
		if !useLocal || !constraints.allowsLocalSearch() {
			return false
		}
		if let cache = LocalPersistence.classCache[constraints.className]?.inner {
			dispatch_barrier_async(LocalPersistence.local_search_queue) {
				self.constraints.replaceSubQueries { (key, constraints) in
					if let innerCache = LocalPersistence.classCache[constraints.className]?.inner {
						let filtered = innerCache.filter { constraints.match($0) }
						return filtered.map { $0.value(key) }
					} else {
						return []
					}
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

				dispatch_async(dispatch_get_main_queue()) {
					var result: [String: AnyObject] = [:]
					if self.fetchesCount {
						result["count"] = count
					} else {
						result["results"] = results.map { $0.raw }
					}
					closure(result, nil)
				}
			}
			return true
		}
		return false
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

	static func get<T: ParseObject>(objectId: String, rush: Double = 0.25, callback: (T) -> Void) {
		if let object = LocalPersistence.data(Pointer(className: T.className, objectId: objectId)) {
			return callback(T(json: object))
		} else {
			let t = timer(T.className)
			appendCallback(objectId, callback: callback)
			dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, Int64(rush * Double(NSEC_PER_SEC))), DISPATCH_TIME_FOREVER, 0)
			dispatch_source_set_event_handler(t) {
				let pending = self.retrivePending(T.self)
				let objectIds = pending.map { ParseValue($0.objectId) }
				_Query(className: T.className, constraints: .In("objectId", objectIds)).data { (jsons, error) in
					for (objectId, callback) in pending {
						for json in jsons {
							if json.objectId == objectId {
								LocalPersistence.appendData(json, pointer: Pointer(className: T.className, objectId: objectId))
								callback(json)
								break
							}
						}
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
			Query<T>().local(false).whereKey(key, equalTo: to).data { (data, error) in
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

extension ParseObject {
	public static func persistent(maxAge: NSTimeInterval, done: ([Data] -> Void)? = nil) {
		LocalCache(className: className).persistent(maxAge, done: done)
	}

	public static func get(objectId: String, callback: (Self) -> ()) {
		ObjectCache.get(objectId, callback: callback)
	}
}