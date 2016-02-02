//
//  IndividualCache.swift
//  Parse
//
//  Created by Rex Sheng on 1/28/16.
//  Copyright © 2016 Rex Sheng. All rights reserved.
//

private func _file(className: String, key: String? = nil) -> String? {
	let home = NSSearchPathForDirectoriesInDomains(.CachesDirectory, .UserDomainMask, true).first
	if let folder = home?.stringByAppendingString("/\(Parse.applicationId)/\(className)") {
		if !NSFileManager.defaultManager().fileExistsAtPath(folder) {
			let _ = try? NSFileManager.defaultManager().createDirectoryAtPath(folder, withIntermediateDirectories: true, attributes: nil)
		}
		if let key = key {
			return "\(folder)/\(key)"
		} else {
			return folder
		}
	}
	return nil
}

private func _loadJSON(folder: String, key: String, expireAfter: NSTimeInterval) throws -> AnyObject? {
	if let filePath = _file(folder, key: key) {
		if let attr = try? NSFileManager.defaultManager().attributesOfItemAtPath(filePath),
			lastModified = attr[NSFileModificationDate] as? NSDate {
				let time = lastModified.timeIntervalSinceNow + expireAfter
				if time < 0 {
					throw ParseCacheError.Expired(time: time)
				}
		}
		if let data = NSData(contentsOfFile: filePath),
			let object = try? NSJSONSerialization.JSONObjectWithData(data, options: []) {
				return object
		}
	}
	throw ParseCacheError.NotFound
}

struct IndividualDataCache: Cache {
	typealias Element = Data
	typealias Generator = AnyGenerator<Element>
	let expireAfter: NSTimeInterval
	let className: String

	func generate() -> AnyGenerator<Element> {
		var index = 0
		if let objectIds = try? self.objectIds() {
			return anyGenerator {
				if index < objectIds.count {
					return try! self.get(objectIds[index++])
				}
				return nil
			}
		} else {
			return anyGenerator { return nil }
		}
	}

	func objectIds() throws -> [String] {
		let json: [String] = try loadJSON(".list")
		return json
	}

	private func loadJSON<U>(key: String) throws -> U {
		let json = try _loadJSON(className, key: key, expireAfter: expireAfter)
		guard let target = json as? U else {
			throw ParseCacheError.WrongFileFormat
		}
		return target
	}

	private func saveJSON(json: AnyObject, toPath: String) throws {
		if let filePath = _file(className, key: toPath) {
			let data = try NSJSONSerialization.dataWithJSONObject(json, options: [])
			data.writeToFile(filePath, atomically: false)
		}
	}

	func get(objectId: String) throws -> Element {
		let json: [String: AnyObject] = try loadJSON(objectId)
		return Data(json)
	}

	func persist(object: Data, enlist: Bool) throws {
		try saveJSON(object.raw, toPath: object.objectId)
		if enlist {
			try self.enlist([object], replace: false)
		}
		print("saved \(className):\(object.objectId)")
	}

	func enlist(objectIds: [String], replace: Bool = false) throws {
		var keys: [String]
		if replace {
			keys = []
		} else {
			keys = try self.objectIds()
		}
		for objectId in objectIds {
			if !keys.contains(objectId) {
				keys.append(objectId)
			}
		}
		try saveJSON(keys, toPath: ".list")
		print("saved \(keys.count) to \(className)/.list")
	}

	func enlist(objects: [Data], replace: Bool = false) throws {
		try enlist(objects.map { $0.objectId }, replace: replace)
	}
}

struct IndividualCache<T: ParseObject where T: Cacheable>: Cache {
	typealias Element = T
	typealias Generator = AnyGenerator<Element>
	let innerCache: IndividualDataCache

	init() {
		innerCache = IndividualDataCache(expireAfter: T.expireAfter, className: T.className)
	}

	func generate() -> AnyGenerator<Element> {
		let generator = innerCache.generate()
		return anyGenerator {
			if let data = generator.next() {
				return T(json: data)
			}
			return nil
		}
	}

	func objectIds() throws -> [String] {
		return try innerCache.objectIds()
	}

	func get(objectId: String) throws -> T {
		let data = try innerCache.get(objectId)
		return T(json: data, cache: false)
	}

	func persist(object: T, enlist: Bool) throws {
		try innerCache.persist(object.json, enlist: enlist)
	}

	func enlist(objects: [T], replace: Bool = false) throws {
		do {
			try innerCache.enlist(objects.map { $0.objectId }, replace: replace)
		} catch ParseCacheError.Expired(let time) {
			print("failed to enlist: \(T.className).list has expired \(time) secs.")
			T.list { _ in }
		}
	}
}