//
//  Parse.swift
//
//  Created by Rex Sheng on 2/4/15.
//
//

public struct Parse {
}

public protocol ParseType {
	var json: AnyObject { get }
}

protocol _ParseType: ParseType {
	typealias RawValue
	init?(_ json: RawValue)
}

public protocol ParseObject {
	var json: Data! { get set }
	static var className: String { get }
	var objectId: String { get }
	var createdAt: NSDate? { get }
	init()
}

public protocol AnyField {
	init(_ key: String)
	func connect(json: Data)
}

extension ParseObject {
	func setupFields() {
		let mirror = Mirror(reflecting: self)
		for (_, value) in mirror.children {
			if let value = value as? AnyField {
				value.connect(json)
			}
		}
	}
	init(json: Data) {
		self.init()
		self.json = json
		setupFields()
	}

	public var objectId: String {
		return json.objectId
	}

	public var createdAt: NSDate? {
		return json.date("createdAt")?.date
	}
}


public class Field<T>: AnyField {
	private let key: String
	private var json: ParseValue!
	public required init(_ key: String) {
		self.key = key
	}

	public func connect(json: Data) {
		self.json = json[key] as! ParseValue
	}

	public func get() -> T? {
		return json.object as? T
	}
}

public struct ParseValue: _ParseType {
	public typealias RawValue = AnyObject?
	public enum Type {
		case Number
		case String
		case Null
	}
	public let type: Type
	public let object: RawValue

	init(_ json: RawValue) {
		switch json {
		case _ as String:
			type = .String
			object = json
		case _ as Double:
			type = .Number
			object = json
		default:
			type = .Null
			object = nil
		}
	}
}

public struct Date {
	public let date: NSDate
}

public struct Bytes {
	public let bytes: NSData
}

public struct Pointer {
	public let className: String
	public let objectId: String
	public let connections: [String: Pointer]?

	public init(className: String, objectId: String, connections: [String: Pointer]? = nil) {
		self.className = className
		self.objectId = objectId
		self.connections = connections
	}
}

public struct GeoPoint {
	public let latitude: Double
	public let longitude: Double
}

public struct ACLRule {
	public let name: String
	public let write: Bool
	public let read: Bool
}

public struct ACL {
	public let rules: [ACLRule]
}

public struct Data {
	let raw: [String: AnyObject]
	var pending: [String: ParseType]?
	public init(_ raw: [String: AnyObject]) {
		self.raw = raw
	}
}


// MARK: - Data Types

struct AnyWrapper: _ParseType {
	typealias RawValue = AnyObject
	var json: RawValue
	init(_ json: RawValue) {
		self.json = json
	}
}

extension Date: _ParseType {
	typealias RawValue = [String: String]

	private static func formatter() -> NSDateFormatter {
		let dict = NSThread.currentThread().threadDictionary
		if let iso = dict["iso"] as? NSDateFormatter {
			return iso
		} else {
			let iso = NSDateFormatter()
			iso.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
			iso.timeZone = NSTimeZone(forSecondsFromGMT: 0)
			dict["iso"] = iso
			return iso
		}
	}

	init(iso: String) {
		date = Date.formatter().dateFromString(iso)!
	}

	init?(_ json: RawValue) {
		if json["__type"] == "Date" {
			date = Date.formatter().dateFromString(json["iso"]!)!
			return
		}
		return nil
	}

	public var json: AnyObject {
		return ["__type": "Date", "iso": Date.formatter().stringFromDate(date)]
	}
}

extension Bytes: _ParseType {
	public typealias RawValue = [String: String]

	init?(_ json: RawValue) {
		if json["__type"] == "Bytes" {
			bytes = NSData(base64EncodedString: json["base64"]!, options: [])!
			return
		}
		return nil
	}

	public var json: AnyObject {
		return ["__type": "Bytes", "base64": bytes.base64EncodedStringWithOptions([])]
	}
}

extension Pointer: _ParseType {
	public typealias RawValue = [String: String]

	init?(_ json: RawValue) {
		if json["__type"] == "Pointer" {
			self.className = json["className"]! as String
			self.objectId = json["objectId"]! as String
			self.connections = nil
			return
		}
		return nil
	}

	public init<T: ParseObject>(object: T) {
		var connections: [String: Pointer] = [:]
		for k in object.json.keys {
			if let p = object.json.pointer(k) {
				connections[k] = p
			}
		}
		className = T.className
		objectId = object.json.objectId
		self.connections = connections
	}

	public init(className: String, data: Data) {
		var connections: [String: Pointer] = [:]
		for k in data.keys {
			if let p = data.pointer(k) {
				connections[k] = p
			}
		}
		self.className = className
		objectId = data.objectId
		self.connections = connections
	}

	public var json: AnyObject {
		return ["__type": "Pointer", "className": className, "objectId": objectId]
	}
}

extension GeoPoint: _ParseType {
	public typealias RawValue = [String: NSObject]

	init?(_ json: RawValue) {
		if let type = json["__type"] as? String {
			if type == "GeoPoint" {
				self.latitude = json["latitude"]! as! Double
				self.longitude = json["longitude"]! as! Double
				return
			}
		}
		return nil
	}

	public var json: AnyObject {
		return ["__type": "GeoPoint", "latitude": latitude, "longitude": longitude]
	}
}

extension ACL: _ParseType {
	public typealias RawValue = [String: [String: Bool]]

	init?(_ json: RawValue) {
		var _array: [ACLRule] = []
		for (key, value) in json {
			var write = false
			var read = false
			if let w = value["write"] {
				write = w
			}
			if let r = value["read"] {
				read = r
			}
			_array.append(ACLRule(name: key, write: write, read: read))
		}
		self.rules = _array
	}

	public var json: AnyObject {
		var result: [String: [String: Bool]] = [:]
		for acl in rules {
			var rule: [String: Bool] = [:]
			if acl.write {
				rule["write"] = true
			}
			if acl.read {
				rule["read"] = true
			}
			result[acl.name] = rule
		}
		return result
	}
}

extension ParseValue {
	var int: Int? {
		return object as? Int
	}

	var double: Double {
		return object as! Double
	}

	var string: String? {
		return object as? String
	}

	var bool: Bool {
		return object as! Bool
	}

	public var json: AnyObject {
		if let o: AnyObject = object {
			return o
		} else {
			return NSNull()
		}
	}
}

extension Data {
	func check<V, T: _ParseType>(value: V?, _ t: T.Type) -> T? {
		if let value = value as? T.RawValue {
			return T(value)
		}
		return nil
	}

	public func pointer(key: String) -> Pointer? {
		return check(raw[key], Pointer.self)
	}

	public var keys: [String] {
		return Array(raw.keys)
	}

	public func date(key: String) -> Date? {
		if key == "createdAt" || key == "updatedAt" {
			if let iso = raw[key] as? String {
				return Date(iso: iso)
			}
		}
		if let date = check(raw[key], Date.self) {
			return date
		}
		return nil
	}

	public func bytes(key: String) -> Bytes? {
		return check(raw[key], Bytes.self)
	}

	public func geoPoint(key: String) -> GeoPoint? {
		return check(raw[key], GeoPoint.self)
	}

	public func value(key: String) -> ParseValue {
		return ParseValue(raw[key])
	}

	public var security: ACL? {
		return check(raw["ACL"], ACL.self)
	}

	public var objectId: String {
		return value("objectId").string!
	}
}


@objc public protocol ComparableKeyType: NSObjectProtocol {}
extension NSDate: ComparableKeyType {}
extension NSNumber: ComparableKeyType {}
extension NSString: ComparableKeyType {}

extension Pointer {
	subscript(key: String) -> Pointer {
		return connections![key]!
	}
}

//MARK: - Comparable

extension ParseValue: Comparable {}
public func ==(lhs: ParseValue, rhs: ParseValue) -> Bool {
	switch (lhs.type, rhs.type) {
	case (.Number, .Number):
		return (lhs.object as! Double) == (rhs.object as! Double)
	case (.String, .String):
		return (lhs.object as! String) == (rhs.object as! String)
	case (.Null, .Null):
		return true
	default:
		return false
	}
}

public func <(lhs: ParseValue, rhs: ParseValue) -> Bool {
	switch (lhs.type, rhs.type) {
	case (.Number, .Number):
		return (lhs.object as! Double) < (rhs.object as! Double)
	case (.String, .String):
		return (lhs.object as! String) < (rhs.object as! String)
	case (.Null, .Null):
		return true
	default:
		return false
	}
}

extension Date: Comparable {}
public func ==(lhs: Date, rhs: Date) -> Bool {
	return lhs.date.timeIntervalSinceReferenceDate == rhs.date.timeIntervalSinceReferenceDate
}

public func <(lhs: Date, rhs: Date) -> Bool {
	return lhs.date.timeIntervalSinceReferenceDate < rhs.date.timeIntervalSinceReferenceDate
}

extension Data {
	subscript(key: String) -> ParseType {
		get {
			if let d = date(key) {
				return d
			}
			return value(key)
		}
		set {
			var _pending = pending ?? [:]
			_pending[key] = newValue
			pending = _pending
		}
	}
}

extension Data: Equatable {}
public func ==(lhs: Data, rhs: Data) -> Bool {
	return lhs.objectId == rhs.objectId
}

public func ==<T: ParseObject>(lhs: T, rhs: T) -> Bool {
	return lhs.json.objectId == rhs.json.objectId
}

func ==(lhs: ParseType, rhs: ParseType) -> Bool {
	if let left = lhs as? Date {
		if let right = rhs as? Date {
			return left == right
		}
		return false
	}
	if let left = lhs as? ParseValue {
		if let right = rhs as? ParseValue {
			return left == right
		}
	}
	return false
}

func <(lhs: ParseType, rhs: ParseType) -> Bool {
	if let left = lhs as? Date {
		if let right = rhs as? Date {
			return left < right
		}
		return false
	}
	if let left = lhs as? ParseValue {
		if let right = rhs as? ParseValue {
			return left < right
		}
	}
	return false
}

extension MutableCollectionType where Generator.Element == Data, Index == Int {

	mutating func sort(keys: String?) {
		guard let keys = keys else { return }
		let orders = keys.componentsSeparatedByString(",")
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
		sortInPlace {
			for (key, asc) in comparators {
				if $1[key] == $0[key] {
					continue
				}
				//xnor
				if $0[key] < $1[key] {
					return asc
				} else {
					return !asc
				}
			}
			return true
		}
	}
}

//MARK: - Relations

public class Relation {
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

public struct Relations {
	private static var relations: [String: (dispatch_group_t, Relation)] = [:]

	public static func of<T: ParseObject, U: ParseObject>(object: T, key: String, toType: U.Type, closure: (Relation) -> Void) {
		of(Pointer(object: object), key: key, toClass: U.className, closure: closure)
	}

	public static func of<T: ParseObject, U: ParseObject>(type: T.Type, key: String, to: U, closure: (Relation) -> Void) {
		let mykey = "\(key)-\(T.className)-\(U.className)/\(to.json.objectId)"
		if let (group, relation) = relations[mykey] {
			dispatch_group_notify(group, dispatch_get_main_queue()) {
				closure(relation)
			}
		} else {
			let relation = Relation()
			let group = dispatch_group_create()
			relations[mykey] = (group, relation)
			dispatch_group_enter(group)
			Query<T>().local(false).whereKey(key, equalTo: to).getData { (data, error) in
				relation.cache = data.map { Pointer(className: T.className, data: $0) }
				print("caching relationship \(mykey): \(relation.cache)")
				dispatch_group_leave(group)
			}
			dispatch_group_notify(group, dispatch_get_main_queue()) {
				closure(relation)
			}
		}
	}

	public static func of(pointer: Pointer, key: String, toClass: String, closure: (Relation) -> Void) {
		let mykey = "\(key)-\(pointer.className)/\(pointer.objectId)-\(toClass)"
		if let (group, relation) = relations[mykey] {
			dispatch_group_notify(group, dispatch_get_main_queue()) {
				closure(relation)
			}
		} else {
			let relation = Relation()
			let group = dispatch_group_create()
			relations[mykey] = (group, relation)
			dispatch_group_enter(group)
			_Query(className: toClass, constraints: .RelatedTo(key, pointer)).getData { (data, error) in
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

//MARK: - Printable & Convertible

extension ParseValue: IntegerLiteralConvertible {
	public init(integerLiteral value: IntegerLiteralType) {
		object = value
		type = .Number
	}
}

extension ParseValue: StringLiteralConvertible {
	public init(unicodeScalarLiteral value: StringLiteralType) {
		object = value
		type = .String
	}
	public init(stringLiteral value: StringLiteralType) {
		object = value
		type = .String
	}
	public init(extendedGraphemeClusterLiteral value: StringLiteralType) {
		object = value
		type = .String
	}
}

extension ParseValue: FloatLiteralConvertible {
	public init(floatLiteral value: FloatLiteralType) {
		object = value
		type = .Number
	}
}

extension Data: DictionaryLiteralConvertible {
	public init(dictionaryLiteral elements: (String, AnyObject)...) {
		var dictionary = [String : AnyObject]()
		for (key, value) in elements {
			dictionary[key] = value
		}
		self.init(dictionary)
	}
}

extension Pointer: CustomStringConvertible {
	public var description: String {
		var string = "*\(className).\(objectId)"
		if let conn = connections {
			string += " ["
			string += conn.map { "\($0):\($1)" }.joinWithSeparator(", ")
			string += "]"
		}
		return string
	}
}